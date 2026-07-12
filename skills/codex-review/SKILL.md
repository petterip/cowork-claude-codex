---
name: codex-review
description: "Cross-model plan review: Claude drafts or loads PLAN.md, Codex critiques it in a read-only sandbox, and Claude revises in the same Codex session until APPROVED or MAX_ROUNDS. Require human approval before implementation. Use for /codex-review, adversarial review of an existing implementation plan, or high-stakes work needing a second-model check. Use /grill-me-codex when requirements also need interviewing. Do not use for trivial changes or existing-code review."
---

# Codex-Review — Adversarial Plan-Review Loop

Two models, one plan, a bounded argument. **Claude is the builder and orchestrator. Codex is a read-only critic** that can read the repo and the plan but cannot touch a single file. They communicate strictly through `PLAN.md` + a Codex session that persists across rounds. The human enters at exactly two points: kickoff and final sign-off.

This is a **deliberate, high-stakes tool** — reach for it on auth, data models, concurrency, migrations, payments, anything expensive to get wrong. Skip it for obvious/cheap work.

## Prerequisites (verify once, fast)

- Codex CLI installed and recent: `codex --version` (need ≥ 0.130; the default `gpt-5.5` model errors on older CLIs).
- Codex authenticated: a prior `codex login` (ChatGPT account is fine). If a run returns an auth/model error, surface it to the user — do not silently retry.
- Do NOT pin `-m` unless the user asks. The user's `~/.codex/config.toml` default model is used. Pinning `gpt-5.x-codex` variants fails on ChatGPT-account auth.
- **Echo the active model before Round 1** so the user can confirm: read the `model` line from `~/.codex/config.toml` (absent = "CLI default"); state it with the resolved tunables. If the user objects, stop before burning a round.
- **Sandbox flag differs between the two commands.** `codex exec` accepts `-s read-only`. `codex exec resume` does NOT — it rejects `-s` ("unexpected argument"). On resume you MUST force read-only via `-c sandbox_mode="read-only"`, because `config.toml` may default `sandbox_mode` to `danger-full-access` (+ `approval_policy="never"`) — which would let Codex WRITE files mid-loop. This is the single most important safety detail in this skill: verified end-to-end on 2026-06-04.

## Tunable variables (read from skill args, else default)

| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates at this. |
| `PLAN_FILE` | `PLAN.md` | Where the evolving plan lives (repo root). |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only transcript of the argument (every round's critique + what changed). The artifact. |

If the user invoked the skill with an argument like `rounds=3`, use that for `MAX_ROUNDS`. Echo the resolved values back before starting.

## Flow

### Step 0 — Kickoff (human gate #1)

The invocation itself is the kickoff. Confirm scope in one line: what is being planned. If the user gave no task, ask for it (one question). Then proceed — do NOT ask for approval round-by-round; that comes at the end.

### Step 1 — Claude plans

Do real planning: read the relevant code, think through the approach, surface decisions and tradeoffs. Then write the plan to `PLAN_FILE` in this structure:

```markdown
# Plan: <task>
_Round 0 — initial draft by Claude_

## Goal
<one paragraph>

## Approach
<numbered steps, concrete>

## Key decisions & tradeoffs
<the contestable choices — name them explicitly so Codex has something to bite>

## Risks / open questions
<what you're unsure about>

## Out of scope
<bounds>
```

Initialize `LOG_FILE`:
```markdown
# Plan Review Log: <task>
Started <stamp the user's local time if known, else "session start">. MAX_ROUNDS=<n>.
```

Show the user the plan inline and say you're sending it to Codex for adversarial review.

### Step 2 — The loop

Maintain `ROUND` (start 1) and `THREAD_ID` (empty until round 1 returns).
Create one private, per-run artifact directory before Round 1. It prevents
parallel reviews from sharing a verdict file and gives every launch a durable
diagnostic trail. Do not use predictable files directly under `/tmp`.

```bash
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")
chmod 700 "$RUN_DIR"
trap 'rm -rf "$RUN_DIR"' EXIT
PROMPT_FILE="$RUN_DIR/review-prompt.md"
VERDICT_FILE="$RUN_DIR/verdict.md"
EVENTS_FILE="$RUN_DIR/events.jsonl"
STDERR_FILE="$RUN_DIR/stderr.log"
```

**The review prompt** sent to Codex each round (adjust the task line):

> You are an adversarial reviewer for an implementation plan. Be skeptical and specific — your job is to find what breaks, not to be agreeable. Read the plan at `PLAN.md` (and any repo files you need; you are read-only). Identify concrete flaws: security holes, race conditions, missing edge cases, schema conflicts, wrong assumptions, observability gaps, simpler alternatives. For each, give a one-line fix. Do NOT modify any files. End your reply with EXACTLY one line: `VERDICT: APPROVED` if the plan is sound enough to implement, or `VERDICT: REVISE` if it still has material problems.

**Access inheritance:** if the user authorized full access or Codex config has `approval_policy="never"` with `sandbox_mode="danger-full-access"`, set both access variables to `--dangerously-bypass-approvals-and-sandbox`. Otherwise retain the read-only defaults below. Full-access reviewers must still follow the prompt's no-edit instruction.

**Round 1** (creates the session — capture `thread_id`):

```bash
if rg -q '^approval_policy\s*=\s*"never"' ~/.codex/config.toml && rg -q '^sandbox_mode\s*=\s*"danger-full-access"' ~/.codex/config.toml; then CODEX_EXEC_ACCESS=--dangerously-bypass-approvals-and-sandbox; CODEX_RESUME_ACCESS=--dangerously-bypass-approvals-and-sandbox; else CODEX_EXEC_ACCESS='-s read-only'; CODEX_RESUME_ACCESS='-c sandbox_mode="read-only"'; fi
cat >"$PROMPT_FILE" <<'EOF'
You are an adversarial reviewer for an implementation plan. Be skeptical and specific — your job is to find what breaks, not to be agreeable. Read PLAN.md and any repository files you need. Do not modify files. Identify concrete flaws and give a one-line fix for each. End with exactly one line: VERDICT: APPROVED or VERDICT: REVISE.
EOF
if ! timeout 600 codex exec $CODEX_EXEC_ACCESS --json -o "$VERDICT_FILE" \
  "$(<"$PROMPT_FILE")" < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review launch failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
THREAD_ID=$(jq -r 'select(.type == "thread.started") | .thread_id' "$EVENTS_FILE" | head -n1)
[[ -n "$THREAD_ID" && "$THREAD_ID" != null && -s "$VERDICT_FILE" ]] || { printf 'Codex did not return a thread ID and verdict.\n' >&2; exit 1; }
```
The critique text lands in `$VERDICT_FILE` (Codex's last message). Read that file.

> Note: stderr carries cosmetic MCP/auth noise on some setups — `2>/dev/null` is intentional. Confirm success by the presence of the verdict file + a `thread.started` line. If neither appears, the run failed (auth/model) — stop and tell the user.
>
> **`< /dev/null` is mandatory:** `codex exec` reads stdin *in addition to* the prompt arg, so under a non-interactive driver (Claude Code's Bash tool, CI, any non-TTY pipeline) it blocks forever waiting on stdin EOF — a silent ~0% CPU hang. The redirect gives it immediate EOF. Required on the resume call below too.
>
> **Timeout guard:** run every `codex exec` / `codex exec resume` with a 10-minute ceiling so any future stall fails loud instead of hanging silently. Via Claude Code's Bash tool, pass `timeout: 600000` on the tool call (the default 2-minute tool timeout is too short for real reviews and would kill them mid-run). In a plain shell, prefix the command with `timeout 600` (Linux / Git Bash) or `gtimeout 600` (macOS via coreutils — stock macOS has no `timeout`). If the ceiling trips, treat it as a failed run: stop and tell the user rather than retrying blind. Applies to the resume call below too.

**Rounds 2..MAX** (resume the SAME session — Codex remembers its earlier critiques, won't re-litigate settled points):

```bash
# NOTE: resume rejects -s. Force read-only via -c sandbox_mode, or Codex
# inherits config.toml (possibly danger-full-access) and could write files.
if ! timeout 600 codex exec resume "$THREAD_ID" $CODEX_RESUME_ACCESS --json \
  -o "$VERDICT_FILE" \
  "I revised the plan. Re-review PLAN.md. Same rules. End with VERDICT: APPROVED or VERDICT: REVISE." \
  < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review resume failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
[[ -s "$VERDICT_FILE" ]] || { printf 'Codex resume returned no verdict.\n' >&2; exit 1; }
```

Both `codex exec` and `codex exec resume` support `--json` (stream → parse `thread_id` first round) and `-o/--output-last-message` (verdict capture).

**Each round, after Codex returns:**
1. Confirm the resume command exited successfully and `$VERDICT_FILE` is nonempty; otherwise stop and report the private diagnostic paths. Read `$VERDICT_FILE`. Append to `LOG_FILE`: `## Round <n> — Codex` + the full critique.
2. Grep the last line for the verdict token.
   - `VERDICT: APPROVED` → break the loop, go to Step 3 (converged).
   - `VERDICT: REVISE` → Claude reads the critique, decides **what's actually worth acting on** (Claude has final say — Codex advises, it does not command). Revise `PLAN_FILE`. Append to `LOG_FILE`: `### Claude's response` + what you changed and what you rejected and why. Increment `ROUND`.
3. If `ROUND > MAX_ROUNDS` → break to Step 3 (deadlock).

### Step 3 — Resolution (human gate #2)

**If APPROVED:** Present to the user — the final `PLAN_FILE`, a 3-bullet summary of what the argument improved, and the round count. Ask: *"Plan survived N rounds of Codex. Implement it now — Codex builds it (`/codex-build`), Claude builds it, or stop here?"* Only on a yes is code written. **No code is written during the loop.** If the user picks Codex, invoke the `codex-build` skill with `SPEC_FILE=PLAN.md` and the same `LOG_FILE` — roles flip (Codex writes, Claude reviews the diff) and the build rounds append to the same log.

**If MAX_ROUNDS hit without APPROVED (deadlock):** Do NOT pretend it converged. Surface the unresolved disagreements explicitly: list each point Codex still flags and Claude's counter-position. Hand it to the human to break the tie. This is a legitimate, useful outcome — a flagged disagreement beats a false "approved."

## Hard rules

- In a full-access context, every Codex child receives `--dangerously-bypass-approvals-and-sandbox`; otherwise retain the read-only flags. The reviewer prompt still forbids edits.
- The loop ALWAYS terminates at `MAX_ROUNDS`. No unbounded recursion.
- Claude is the final arbiter on every REVISE — incorporate good critiques, reject bad ones *with a reason logged*. Don't cave to Codex on everything (that defeats the cross-model check) and don't ignore it (that defeats the point).
- Code only after human gate #2.
- `LOG_FILE` is the deliverable — it tells the whole story of the argument. Keep it complete.

## What NOT to do

- Don't use this to review existing code — that's `/codex:review`.
- Don't pin a `-codex` model variant on ChatGPT-account auth — it 400s.
- Don't skip the log — the argument transcript is the most valuable artifact.
- Don't let Codex edit files. Read-only, always.
