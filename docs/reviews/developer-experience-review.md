# Developer Experience Review

Reviewed 2026-07-11 from two perspectives: an open-source maintainer trying to
install, update, test, and support the projects, and a daily Claude Code/Codex
user trying to choose the right workflow quickly. This is a design review, not
an implementation change.

## Executive assessment

`cowork-claude-codex` has a useful and unusually concrete collaboration model:
durable artifacts, bounded rounds, explicit ownership, and independent proof
are all strong foundations. Its main usability risk is that the contract is
spread across six long skills and several scripts, while the setup and
compatibility assumptions are implicit.

`codex-mobile-wsl-full-access` is concise and focused, but it is not yet
discoverable or self-service as a public project: it has no root README or
installer, and its verifier is informative rather than a reliable automation
gate.

The best next investment is a small, portable product surface around the
existing mechanics—not more workflow rules.

## Prioritized improvements

| Priority | Repository | Recommendation | Why it matters | Acceptance signal |
|---|---|---|---|---|
| P0 | mobile WSL | Add a root `README.md` with purpose, supported platform boundary, prerequisites, installation, first run, verification, recovery, and uninstall/update instructions. | GitHub visitors currently land on a repository with no explanation or install path. The only documentation is embedded in a skill, which is invisible before installation. | A new user can reach a successful verification from the README without inspecting source files. |
| P0 | both | Make verifiers return non-zero when any required check fails, while retaining a `--report` mode that always exits zero for diagnosis. | `verify_host.sh` and `verify-environment.sh` print `FAIL` but normally exit zero. Shell automation, CI, and calling agents can incorrectly treat a failed environment as ready. | `verify …` exits `1` for a failed required check; `verify --report` prints all results and exits `0`. |
| P0 | cowork | Replace the environment-dependent `test_contract.sh` with hermetic unit/contract tests, and keep a separate explicit live smoke test. | The current contract test invokes real subscription authentication and local configuration. It can fail on a healthy code change for account reasons, or pass without exercising failure branches. | Tests use temporary `HOME`, `PATH`, and stubbed `claude`/`codex`/`jq`; a separately named smoke command documents its live prerequisites. |
| P1 | cowork | Add one short workflow chooser at the top of the README: “plan from scratch”, “review an existing plan”, “Codex builds a frozen spec”, “Codex delegates to Claude”, and “hand off a session”. | Six skills are understandable after reading them, but hard to select correctly from names alone. This is the daily-user friction point. | Each outcome has one command, required inputs, expected artifact, and a link to the detailed skill. |
| P1 | cowork | Extract duplicated Claude→Codex review mechanics from `grill-me-codex`, `grill-with-docs-codex`, and `codex-review` into one canonical reference or executable helper. | The near-identical command blocks, access policy, timeout notes, and round loop will drift. A correction currently needs several coordinated edits. | The skills retain their different entry criteria, but refer to one maintained review-runner contract. |
| P1 | both | Publish a compatibility matrix and make preflight check it: OS support, Bash version, Claude Code and Codex minimum versions, required tools (`git`, `jq`, `rg`, Docker where relevant), and optional tools. | The repos assume Linux/WSL utilities. `install.sh` uses GNU `readlink -f`; stock macOS lacks it. `jq`, `rg`, `timeout`, and selected Claude subcommands are required but not declared. | README lists supported/unsupported combinations; preflight identifies each missing dependency with an actionable remedy. |
| P1 | cowork | Make installation lifecycle complete: `install`, `status`, `update`, and `uninstall` (all idempotent and non-destructive). | Symlink installation is a good single-source-of-truth choice, but a user cannot easily audit existing links, repair a moved clone, or remove only links owned by this project. | `install.sh --check`, `--uninstall`, and clear collision diagnostics work without overwriting unrelated skills. |
| P1 | mobile WSL | Add an installer analogous to the cowork repo and a package/skill discovery note for Codex. | A user has to infer the destination directory and symlink mechanics. This makes adoption and upgrades unnecessarily manual. | One documented command installs the skill, reports its destination, and supports a no-write check. |
| P1 | mobile WSL | Make the host verifier structured and bounded: add JSON output, per-check exit semantics, and time limits around Docker and daemon checks. | Agents need machine-readable evidence; a stalled Docker daemon should not stall setup indefinitely. | `verify_host.sh --json` has stable keys, and slow checks return a distinct timeout/failure result. |
| P1 | both | Add CI that runs syntax, hermetic contracts, link/package checks, and Markdown link checks on supported Linux. | Public skills need regression protection, especially where command-line syntax and protocol invariants matter. Current local tests do not prove a clean checkout can install. | A pull request receives deterministic checks without requiring local credentials, Docker, WSL, or paid accounts. |
| P2 | cowork | Introduce a minimal `cowork doctor` command that combines dependency checks, safe configuration checks, artifact-root writability, and version reporting. | Daily users should not have to know which of five scripts to run when a rally fails. | One command emits a concise readiness report and links each failure to the recovery section. |
| P2 | cowork | Define artifact retention and cleanup ergonomics: `list`, `show`, `archive`, `prune`, and a documented default retention policy. | External job directories are correct for worktree isolation, but they will accumulate and are hard to inspect manually. | Users can identify active jobs and remove only terminal jobs without touching source checkouts. |
| P2 | both | Add a short troubleshooting section based on observable symptoms, not internal implementation terms. | The skills contain recovery guidance, but a person sees symptoms such as “nothing happened”, “cannot resume”, or “Docker check fails”. | README maps each common symptom to one diagnostic command and the next safe action. |
| P2 | cowork | Reduce hard-coded temporary paths and expose an overridable runtime directory for command output as well as job artifacts. | `/tmp/codex-build.txt` and `/tmp/codex-verdict.txt` collide across concurrent projects/users and are weak audit artifacts. | Each run uses a unique, job-scoped temporary directory with cleanup behavior documented. |
| P2 | mobile WSL | Remove or clearly classify the “Managed app-server daemon” check. | The completion criteria emphasize remote control, yet the verifier treats a second process as a peer signal. This makes the readiness model harder to understand and may create false failures. | The verifier labels checks as required versus diagnostic, and the documented success criteria match required checks exactly. |

## Maintainer notes and rationale

### Installation and updates

The cowork installer is deliberately conservative about collisions, which is
good. Its use of absolute symlinks means a `git pull` updates installed skills
immediately, another good choice. The missing piece is lifecycle visibility:
there is no supported way to list installed links, detect a deleted/moved
checkout, or remove only links this installer created. A small manifest is not
necessary; resolving each expected symlink is sufficient and keeps the design
simple.

Portability needs an explicit decision. Either support Linux/WSL only and say
so prominently, or replace GNU-only assumptions such as `readlink -f` and
`timeout` with portable alternatives. Silent partial support is the least
maintainable option.

### Skill discoverability and documentation

The cowork README explains the architecture well, but it starts at the
protocol level. Most users begin with an outcome, not a protocol. A chooser
plus a “five-minute first successful review” tutorial would turn the existing
documentation into a usable front door.

The mobile repository needs that front door first. It should be a standalone
public artifact even though the actual logic remains in `SKILL.md`. Its README
should explicitly say that it is for Windows + WSL2 + Codex Desktop/mobile
remote control, and should state what it does *not* support. This reduces
support requests caused by users attempting native Linux, macOS, or unrelated
remote-control setups.

### Testability and reliability

Both current test scripts are valuable smoke checks, but they are not tests of
the interesting behavior. The mobile test checks that labels exist and permits
all live checks to be `FAIL`. The cowork test depends on the current machine's
authentication and configuration, then checks a few strings. Neither can
reliably prevent regressions in parsing, failure behavior, or compatibility.

The practical split is:

- Hermetic unit/contract tests: stub commands and fixtures for every pass/fail
  branch, including malformed JSON, missing dependencies, unsupported CLI
  output, and timeouts.
- Live smoke tests: opt-in commands for an authenticated environment, clearly
  marked as requiring a real account/host.

This preserves the useful real-environment validation without making every
contributor recreate one.

### Accidental complexity

The rally protocol itself is justified complexity: it solves real
cross-worktree ownership and audit problems. The accidental complexity is the
repetition of operational command recipes across long Markdown skills. Keep
the distinct user flows, but centralize the shared execution semantics in a
reference or thin script. This will also make version and capability handling
consistent.

Avoid adding an orchestration daemon, database, or background scheduler. The
existing filesystem artifacts plus explicit worker IDs are debuggable and fit
the product. Improvements should make that model easier to enter and diagnose,
not replace it.

## Suggested delivery order

1. Correct verifier exit status and split hermetic versus live tests.
2. Add the mobile README and installer; add the cowork workflow chooser and
   lifecycle commands.
3. Publish compatibility/dependency policy and add preflight diagnostics.
4. Extract the shared Claude→Codex review execution contract.
5. Add CI and artifact lifecycle commands.

## Evidence gathered

- `cowork-claude-codex`: inspected README, installer, all rally scripts and
  protocol, and representative Claude/Codex skill instructions. `bash -n`,
  `scripts/test_contract.sh`, and `git diff --check` passed in the reviewed
  checkout.
- `codex-mobile-wsl-full-access`: inspected the skill, agent metadata,
  verifier, and verifier test. It has no root README or installer.
  `scripts/test_verify_host.sh` and `git diff --check` passed in the reviewed
  checkout.

Passing current checks is useful evidence of syntax and basic local wiring; it
does not change the test-isolation findings above.
