# Cross-model rally protocol review

**Scope.** Staff-engineering review of the current `main` implementation at
`f2cada1`: the Codex-to-Claude rally, the Claude-to-Codex skills, installation,
and their executable verification. This is a protocol/reliability review, not a
claim that either model should be trusted merely because it produced a report.

## Overall assessment

The repository has the right high-level shape: bounded rounds, an external
mailbox for Claude write work, explicit human decision states, and independent
verification are meaningful improvements over terminal-copy handoffs. The
implementation is still mostly a **written convention**. The critical boundary
conditions—who owns a job, which paths changed, whether a state transition is
legal, and whether the worker result is the one being reviewed—are not enforced
by the scripts. Treat it as a useful assisted workflow, not a reliable
orchestration system, until the first three findings are addressed.

## Required before relying on write jobs

### Critical — The job state machine and immutable artifacts are not enforced

**Evidence:** The protocol calls `manifest.json` the source of truth and says
artifacts are immutable ([job protocol](../../skills/codex-claude-rally/references/job-protocol.md),
lines 17–28 and 48–53). `create-rally-job.sh` creates plain files (lines 23–59),
while `validate-rally-job.sh` only validates a small JSON shape and the primary
checkout's `HEAD` (lines 14–27). There is no transition command, lock, expected
previous-state check, round/artifact consistency check, or write-once guard.
The launch instructions then ask a worker to append events and the operator to
edit the manifest manually ([SKILL.md](../../skills/codex-claude-rally/SKILL.md),
lines 54–60).

**Failure mode:** Two actors can race a transition, a stale/mistaken response
can be accepted as the current round, and “append-only”/“immutable” is only a
request to a fully privileged process. Recovery cannot distinguish a genuine
worker result from a partially published or overwritten one.

**Change:** Add a small `rallyctl`/shell command set that is the only supported
writer of protocol metadata: `claim`, `publish-response`, `begin-verify`,
`record-review`, `stop`. Use a per-job `flock`, atomic `mkdir` on creation,
temporary-file + `rename`, and compare-and-swap state/round checks. Validate
that exactly one request/response/review exists for each applicable round and
record an artifact digest in the event. Make the validator reject illegal
transitions rather than merely recognising state names.

### Critical — Write-job isolation and scope are asserted but neither created nor verified

**Evidence:** The skill says to use write mode only when Claude is the sole
writer and to record the *actual* worktree after launch ([SKILL.md](../../skills/codex-claude-rally/SKILL.md),
lines 37–44). The launch command, however, starts `claude --bg` from the current
checkout (lines 50–57); it does not create or pass an isolated worktree. The
validator reads `repository_path` and compares that checkout's `HEAD` to the
base commit, but never validates `worker_cwd`, a worker worktree, changed paths,
or `allowed_paths`/`proof_command` (validate script, lines 14–27).

**Failure mode:** A write worker can modify the caller's checkout, collide with
Codex or a human, and a verification step can inspect the wrong tree. A change
outside the declared scope has no machine-detectable rejection path.

**Change:** Make isolation explicit and fail closed: create a job-owned `git
worktree` at job creation (or require a supplied worktree and verify it is a
worktree at `base_commit`), launch Claude with that directory, and persist its
canonical path before it can work. At hand-back, run `git -C "$worker_cwd" diff
--name-only "$base_commit" --` and reject paths not matched by a normalized,
non-empty allowlist; verify the worktree's merge-base and untracked files too.
Run proof in that exact worktree. Require an explicit human apply/cherry-pick
step after the verifier records the reviewed commit/diff digest.

### Critical — The advertised bidirectional durable protocol does not exist in the Claude → Codex direction

**Evidence:** The README says “Both directions use durable artifacts and
independent verification” ([SKILL.md](../../skills/codex-claude-rally/SKILL.md),
lines 76–78). In contrast, `codex-review` communicates via mutable `PLAN.md`,
`PLAN-REVIEW-LOG.md`, a captured thread ID, and the global
`/tmp/codex-verdict.txt` ([codex-review](../../skills/codex-review/SKILL.md),
lines 70–112). `codex-build` likewise uses the fixed
`/tmp/codex-build.txt` (lines 60–89). Those files collide across simultaneous
jobs and are neither versioned nor bound to a job/thread.

**Failure mode:** Parallel reviews/builds can read another job's last message,
and a resumed Codex session is not connected to an immutable request/review
record. The two direction claims give operators a false common reliability
model.

**Change:** Either narrow the README/protocol claim to Codex → Claude, or make
the rally job format provider-neutral. Put Codex prompt, thread ID, stdout
metadata, last message, review, and proof under the job/round directory; use
per-job output files rather than `/tmp`; validate that a resume uses the stored
thread ID. The latter is preferable because it gives a single operator mental
model and enables an auditable role flip.

### Critical — The “contract” test can pass while the environment is unusable

**Evidence:** `verify-environment.sh` prints `FAIL` for every failed check but
never exits nonzero (lines 8–30). `test_contract.sh` captures its output and
only greps for labels, not `PASS` values (lines 8–11); it therefore accepts the
presence of `Codex CLI: FAIL`, `Claude Code CLI: FAIL`, or a failed subscription
check. The current `bash skills/codex-claude-rally/scripts/test_contract.sh`
returns `Rally skill contract: PASS`; this demonstrates syntax and label
presence, not the advertised preflight contract.

**Failure mode:** CI or an operator can get a successful “contract” result on a
machine that cannot safely launch either provider. This undermines the primary
gate users are told to run before a rally.

**Change:** Have the verifier accumulate failures and `exit 1` if any mandatory
check fails, while retaining readable per-check lines. In the contract test,
run isolated positive and negative fixtures, assert exact `…: PASS` output and
exit code, and test the gate with representative blocked authentication
environment variables. Add an integration test with fake `claude`/`codex`
binaries that verifies launch arguments, response publication, and a rejected
out-of-scope diff without invoking paid services.

## Important reliability improvements

### Important — No deadline, liveness lease, or deterministic resume record

**Evidence:** A job manifest has `created_at` but no launch time, deadline,
heartbeat, attempt, or resume provenance (create script, lines 24–41). Recovery
is prose—“inspect logs” and respawn from a new request—rather than a recorded
operation ([job protocol](../../skills/codex-claude-rally/references/job-protocol.md),
lines 61–68). The launch output is copied to an undocumented
`claude-launch-001.txt` (rally SKILL lines 54–56), while the worker/session IDs
are manually recorded afterwards.

**Change:** Store launch attempt ID, provider version, worker/session ID,
started/last-observed/deadline timestamps, and an explicit `attempt` artifact.
Have a `status` command reconcile the provider status with manifest state and
move an expired job to `WAITING_FOR_HUMAN` (never silently respawn). Require a
new request that names the prior failed attempt and records why a resume or
respawn is safe.

### Important — Validation checks the wrong revision for a worker worktree

**Evidence:** `validate-rally-job.sh` only compares
`git -C "$repository_path" rev-parse HEAD` with `base_commit` (lines 23–27),
although write hand-back is defined against the recorded worker worktree (job
protocol, lines 55–57). It also rejects a changed primary checkout even if the
worker worktree remains valid, while failing to notice that the worker started
from or was rebased onto a different revision.

**Change:** Separate `source_repository`, `source_base_commit`,
`worker_worktree`, and `worker_head_at_launch`. Verify all four relevant Git
identities. A primary checkout advance should be a clear human-rebase decision,
not a generic validation failure; the worker tree mismatch must be a hard stop.

### Important — Full-access inheritance conflates authorization detection with a safe execution contract

**Evidence:** `detect-full-access.sh` infers authorization from two literal
config lines or an environment variable (lines 4–10). The rally's “read-only”
mode still grants a full-access Claude worker when that condition is true
(rally SKILL lines 18–20 and 52–55); allowed paths are only words in the
prompt. Claude-side review instructions duplicate fragile config parsing with
`rg` in three skills (for example `codex-review`, lines 76–85).

**Change:** Centralize a provider-agnostic access resolver and persist both the
user authorization evidence and the exact launch flags. Keep full access where
authorized, but distinguish *tool permission* from *job scope*: enforce scope
after execution and have the worker worktree prevent accidental checkout
collisions. Add a preflight assertion that the selected CLI supports the chosen
flag; do not infer support from configuration alone.

### Important — Portable installation and dependencies are underspecified

**Evidence:** `install.sh` installs symlinks but does not check the source
exists, executable permissions, required commands (`git`, `jq`, `rg`,
`mktemp`), or supported provider CLI capabilities. `claude-handoff` hard-codes
`$HOME/.codex/skills/codex-claude-rally/...` instead of resolving its own linked
source (lines 6–8), so moving `CODEX_HOME`, using an alternate installation, or
installing only `claude-handoff` breaks its gate.

**Change:** Add `install --check` that reports versions/capabilities and makes
dependencies explicit. Resolve sibling scripts relative to `${BASH_SOURCE[0]}`
or document that `claude-handoff` has a hard dependency on the rally skill and
make `install.sh` install them atomically. Use `command -v` checks before jq/rg
operations and report a targeted fix.

## Useful polish after the safety work

### Consider — Replace duplicated provider recipes with one parameterized reference

The three Claude plan-review skills repeat near-identical Codex command blocks,
including sensitive-to-CLI-semantics access handling and fixed `/tmp` paths.
One version will drift first. Extract the command contract to a shared
reference/script and leave each skill focused on its unique planning behavior.

### Consider — Make terminal-state ownership and human gates explicit in the schema

The state diagram says “only the owner” changes the manifest, but `owner` is
not constrained or transition-specific. Define a transition table
(`state`, `actor`, `next_state`, required artifacts) and have the transition
tool enforce it. Require a recorded human decision ID/text before
`ACCEPTED` for write jobs and before any apply operation.

### Consider — Document concurrency and retention explicitly

State whether multiple read-only jobs can share one source checkout; currently
the rule only bans another *writer*. Also define cleanup/retention because
external jobs otherwise accumulate indefinitely. Cleanup must require a
terminal state and preserve a compact manifest/review summary when needed for
audit.

## Suggested delivery order

1. Add a real verifier/fixture suite and fix its failure exit semantics.
2. Implement atomic state-transition and artifact-publication helpers.
3. Add job-owned worktree creation plus allowed-path/worker-revision/proof
   validation for write jobs.
4. Move Claude → Codex review/build artifacts into the same job protocol and
   eliminate global `/tmp` output names.
5. Add liveness/recovery metadata, then reduce duplicated skill instructions.

## Verification performed

- Inspected README, installer, all six skill entry points, the rally protocol,
  and every rally shell script.
- Ran `bash -n` on `install.sh` and every rally script: passed.
- Ran `bash skills/codex-claude-rally/scripts/test_contract.sh`: printed
  `Rally skill contract: PASS`.
- Ran `git diff --check`: clean.

No files other than this review were changed; no provider worker was launched
for this review.
