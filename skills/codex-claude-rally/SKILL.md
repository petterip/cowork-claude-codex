---
name: codex-claude-rally
description: "Delegate work from Codex to a persistent Claude Code background agent and exchange results through durable workspace artifacts. Use when the user asks to hand work to Claude, toss work between Codex and Claude, get Claude's independent implementation or review, or continue a Claude worker without claude -p."
---

# Codex-Claude Rally

Use this skill for a two-way, asynchronous collaboration. Codex launches Claude with `claude --bg`; Claude writes its result to a shared job folder; Codex reads, verifies, and either finishes the task or sends a bounded follow-up. Do not use `claude -p`.

## Subscription-only gate

Run `scripts/assert-subscription-auth.sh` before every Claude launch and resume. It fails closed when API keys, gateway tokens, an API-key helper, Bedrock, Vertex, Foundry, or non-subscription authentication is detected. It also requires `CLAUDE_RALLY_SUBSCRIPTION_ONLY=1` as an explicit confirmation that usage credits are disabled in the Claude account. Do not set this variable on behalf of the user.

Anthropic account settings cannot be inspected from the CLI. If the user has enabled usage credits, disable them before setting the confirmation variable; otherwise Claude may bill usage beyond the subscription limit. If the gate fails, do not unset a credential or change authentication automatically: report the blocker and let the user choose.

## Create a job

From the target repository root, choose a short unique `JOB_ID` and create `.model-rally/$JOB_ID/`. Do not use this skill when the working tree has unrelated edits that a worker could overwrite; inspect `git status --short` first and agree on the allowed paths.

Write `.model-rally/$JOB_ID/request.md` with the task, exact allowed paths and actions, key context, expected deliverable, and a rule that Claude must not commit, push, deploy, change credentials, or start another worker. Require it to write `response.md` with outcome, decisions, files changed, commands run, remaining risks, and a final `READY_FOR_CODEX` or `NEEDS_CODEX` line.

For a review-only job, make the allowed actions read-only and require ranked findings. Never let Codex and Claude edit the same paths concurrently.

## Launch Claude

From the target repository root:

```bash
JOB_ID=<short-id>
JOB_DIR=".model-rally/$JOB_ID"
"$HOME/.codex/skills/codex-claude-rally/scripts/assert-subscription-auth.sh"
claude --bg --name "codex-$JOB_ID" "$(cat "$JOB_DIR/request.md")" \
  | tee "$JOB_DIR/claude-launch.txt"
claude agents --cwd "$PWD" --all --json
```

Record the job ID, repository root, start time, launch output, and Claude session ID in `$JOB_DIR/state.md`. The durable result is always `$JOB_DIR/response.md`, not the background-command output.

## Receive and verify Claude's work

When `response.md` appears or the worker completes:

1. Read `response.md`, `git status --short`, and the full diff for allowed paths.
2. Independently run the proof commands relevant to the claimed work.
3. Write `$JOB_DIR/from-codex.md` with `ACCEPTED`, a precise follow-up, or `NEEDS_HUMAN`.
4. Do not claim success from Claude's report alone.

## Continue the rally

Use at most two Claude follow-up rounds. Put a precise request in `$JOB_DIR/follow-up-N.md`, then resume the recorded session:

```bash
"$HOME/.codex/skills/codex-claude-rally/scripts/assert-subscription-auth.sh"
claude --bg --resume "$CLAUDE_SESSION_ID" --name "codex-$JOB_ID-rN" \
  "$(cat "$JOB_DIR/follow-up-N.md")" \
  | tee "$JOB_DIR/claude-launch-round-N.txt"
```

Capture the new worker/session IDs with `claude agents --cwd "$PWD" --all --json`. If Claude writes `NEEDS_CODEX`, answer in `from-codex.md` and resume it. Stop delegation after two unsuccessful follow-ups.

## Pair with the Claude skills

`/grill-me-codex`, `/codex-review`, and `/codex-build` cover Claude → Codex work. This skill supplies the inverse Codex → Claude entry point. Use shared `.model-rally` artifacts whenever either side hands control back.
