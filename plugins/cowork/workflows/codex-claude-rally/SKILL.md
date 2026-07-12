---
name: codex-claude-rally
description: "Delegate bounded work from Codex to a persistent Claude Code background worker and exchange verified results through durable, versioned job artifacts. Use when the user asks to hand work between Codex and Claude, request independent Claude implementation or review, or resume a Claude worker without claude -p."
---

# Codex-Claude Rally

Use this skill for asynchronous, two-way collaboration. Codex launches Claude with `claude --bg`; Claude publishes an immutable response; Codex independently verifies it and either accepts it, asks one bounded follow-up, or escalates. Do not use `claude -p`.

Read [the job protocol](references/job-protocol.md) before creating or resuming a job.

## Subscription authentication gate

Run `scripts/assert-subscription-auth.sh` before every Claude launch and resume. It fails closed when API keys, gateway tokens, an API-key helper, Bedrock, Vertex, Foundry, or non-subscription authentication is detected. It then requires Claude Code to report an eligible first-party Claude subscription.

Anthropic account credit settings cannot be inspected from the CLI. This gate verifies subscription authentication and excludes known API/provider routes; it cannot prove whether an account has enabled optional usage credits. If the gate fails, do not change credentials automatically: report the blocker and let the user decide.

## Full-access inheritance

If the user authorized full access or Codex already has `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, every Claude and Codex child must inherit full access. `scripts/detect-full-access.sh` records this in `manifest.json`; do not silently downgrade a child to manual, read-only, or approval-gated mode.

## Preflight and recovery

Before launching a job, run `scripts/verify-environment.sh`.

- Missing worker/session: inspect `claude logs <worker-id>`; if it cannot resume, create the next immutable request and respawn.
- Unexpected permission prompt or missing full-access flag: stop the round, record `WAITING_FOR_HUMAN`, and inspect the child launch policy. Never silently downgrade access.
- Base commit, allowed-path, or proof mismatch: record `WAITING_FOR_HUMAN`; do not continue the worker speculatively.
- User cancellation: `claude stop <worker-id>`, preserve artifacts, and record `STOPPED`.

## Create a job

From the target repository root, create an external job directory. It must be outside the checkout because Claude background write sessions may move into an isolated worktree.

```bash
JOB_ID=<short-id>
scripts/create-rally-job.sh "$JOB_ID" read-only --allowed-path docs --proof-command 'none'
# Use `write` only when Claude is the sole writer for the requested paths.
RALLY_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs/$JOB_ID"
```

Replace the placeholders in `$RALLY_DIR/requests/001.md`. Include the task, mode, exact allowed paths, source-of-truth references, proof command, non-goals, and the absolute `$RALLY_DIR` path. Keep the request bounded; link to long artifacts rather than copying them.

For a write job, require every allowed path and the proof command at creation, then bind the actual isolated worker worktree before moving the job to `RUNNING`:

```bash
scripts/create-rally-job.sh "$JOB_ID" write --allowed-path src/feature --proof-command 'pnpm test -- feature'
scripts/rallyctl.sh bind-worker "$RALLY_DIR" /absolute/worker-worktree
scripts/rallyctl.sh transition "$RALLY_DIR" CREATED RUNNING codex
```

Never let Claude and Codex edit the same paths concurrently.

## Launch Claude

Run the gate, then pass Claude the immutable request and the absolute artifact directory. Claude must write only to a temporary response file and rename it to `responses/001.md` when complete.

```bash
"$HOME/.codex/skills/codex-claude-rally/scripts/assert-subscription-auth.sh"
ACCESS_ARGS=()
if [[ "$(scripts/detect-full-access.sh)" == full ]]; then ACCESS_ARGS=(--dangerously-skip-permissions); fi
claude --bg "${ACCESS_ARGS[@]}" --name "codex-$JOB_ID" \
  "Read $RALLY_DIR/requests/001.md. Work only within its allowed paths. Publish the result atomically to $RALLY_DIR/responses/001.md, append state events to $RALLY_DIR/events.ndjson, and end the response with READY_FOR_CODEX, NEEDS_CODEX, or WAITING_FOR_HUMAN." \
  | tee "$RALLY_DIR/claude-launch-001.txt"
claude agents --cwd "$PWD" --all --json
```

Record the launch-printed worker ID, available Claude session ID, and actual worker CWD atomically: `scripts/rallyctl.sh record-worker "$RALLY_DIR" <worker-id> <session-id-or-null> "$PWD"`. Record the Codex thread ID when one exists. If the installed Claude version does not support a background resume, use its documented `logs`, `attach`, `stop`, or respawn workflow; do not scrape terminal output.

## Verify and continue

When a response appears, publish it by atomic rename, then transition the manifest and run:

```bash
scripts/rallyctl.sh transition "$RALLY_DIR" RUNNING WAITING_FOR_CODEX claude
scripts/rallyctl.sh transition "$RALLY_DIR" WAITING_FOR_CODEX VERIFYING codex
scripts/validate-rally-job.sh "$RALLY_DIR"
```

Read the immutable response, inspect the full allowed-path diff against the recorded base commit, and run the proof command yourself. Write the independent finding to `reviews/001.md`; append an event and transition to `ACCEPTED`, `WAITING_FOR_HUMAN`, or `RUNNING`.

For a material fix, create `requests/002.md`; never overwrite round 001. Allow at most two transitions from `VERIFYING` back to `RUNNING`. Before any resume, re-run the subscription gate and verify the recorded base commit, worktree path, and allowed paths. Mismatch means `WAITING_FOR_HUMAN`. When `full_access_authorized` is true, resume Claude with `--dangerously-skip-permissions`. Before `ACCEPTED` or `REJECTED`, write the independent `reviews/001.md`; `rallyctl` stores its digest with the state transition.

For cancellation, use `claude stop <worker-id>`, preserve the artifacts, and transition to `STOPPED`.

## Pair with the Claude skills

`/cowork:plan`, `/cowork:review`, and `/cowork:build` cover Claude → Codex work. This skill supplies the inverse Codex → Claude entry point. Both directions use durable artifacts and independent verification rather than trusting a model's terminal report.
