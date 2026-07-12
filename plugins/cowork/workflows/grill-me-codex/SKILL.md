---
name: grill-me-codex
description: "Two-act collaborative planning: Claude resolves requirements one question at a time, then writes PLAN.md; Codex adversarially reviews it read-only and Claude revises in the same Codex session until APPROVED or MAX_ROUNDS. Require human sign-off before code. Use through /cowork:plan for high-stakes planning, documentation-aware planning, existing-plan review, or directly when requirements need structured clarification and a second-model review. Do not use for trivial changes or existing-code review."
---

# Collaborative Plan — Resolve, Challenge, Then Build

Two acts, two different jobs:

- **Act 1 fixes the #1 failure mode: building the wrong thing.** Claude resolves intent with you until it is locked — no guessing at ambiguity. (This act is adapted from Matt Pocock's `grill-me`, used under MIT — see `THIRD-PARTY-NOTICES.md`.)
- **Act 2 fixes the #2 failure mode: a plan that sounds right but breaks.** A *different model* (Codex) adversarially attacks the locked plan. Cross-model = no echo chamber.

You enter at two points only: resolving decisions and signing off the converged plan. Codex is read-only the whole time and never touches a file.

---

## ACT 1 — COLLABORATIVE PLANNING (you ↔ Claude)

> Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.
>
> Ask the questions one at a time, waiting for my answer before continuing.
>
> If a question can be answered by exploring the codebase, explore the codebase instead.

When the decision tree is resolved and we're aligned, **write the agreed plan to `PLAN.md`** in this structure, then move to Act 2:

```markdown
# Plan: <task>
_Locked through collaborative planning — by Claude + <user>_

## Goal
<one paragraph — reflects the decisions actually settled>

## Approach
<numbered, concrete steps>

## Key decisions & tradeoffs
<the contestable choices planning resolved — name them so Codex has something to challenge>

## Risks / open questions
<anything still genuinely open>

## Out of scope
<bounds established during planning>
```

Initialize `PLAN-REVIEW-LOG.md`:
```markdown
# Plan Review Log: <task>
Act 1 (collaborative planning) complete — plan locked with the user. MAX_ROUNDS=<n>.
```

---

## ACT 2 — REVIEW (Claude ↔ Codex)

Now hand the locked plan to Codex for adversarial review. Same engine, mechanics verified end-to-end (2026-06-04).

### Prerequisites (verify once, fast)
- `codex --version` ≥ 0.130 (older CLIs error on the default `gpt-5.5` model).
- Codex authenticated (prior `codex login`; ChatGPT account is fine). On auth/model error, surface it — don't silently retry.
- Do NOT pin `-m`. Use the config default. Pinning `gpt-5.x-codex` variants 400s on ChatGPT-account auth.
- **Echo the active model before Round 1** so the user can confirm: read the `model` line from `~/.codex/config.toml` (if absent, report "CLI default"). State it alongside the resolved tunables, e.g. `Reviewer model: CLI default (config unpinned) — codex-cli 0.137.0`. If the user objects, stop and let them adjust config before burning a review round.

### Tunables (read from args, else default)
| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates here. |
| `PLAN_FILE` | `PLAN.md` | The plan Act 1 produced. |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only argument transcript. The artifact. |

If invoked with e.g. `rounds=3`, use that for `MAX_ROUNDS`. Echo resolved values before starting.

### The review prompt (sent each round)
> You are an adversarial reviewer for an implementation plan. Be skeptical and specific — your job is to find what breaks, not to be agreeable. Read the plan at `PLAN.md` and any repo files you need (you are read-only). Identify concrete flaws: security holes, race conditions, missing edge cases, schema conflicts, wrong assumptions, observability gaps, simpler alternatives. For each, give a one-line fix. Do NOT modify any files. End your reply with EXACTLY one line: `VERDICT: APPROVED` if the plan is sound enough to implement, or `VERDICT: REVISE` if it still has material problems.

Before Round 1, create private per-run artifacts. Never share a predictable
`/tmp` filename between reviews:

```bash
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")
chmod 700 "$RUN_DIR"
trap 'rm -rf "$RUN_DIR"' EXIT
PROMPT_FILE="$RUN_DIR/review-prompt.md"
VERDICT_FILE="$RUN_DIR/verdict.md"
EVENTS_FILE="$RUN_DIR/events.jsonl"
STDERR_FILE="$RUN_DIR/stderr.log"
cat >"$PROMPT_FILE" <<'EOF'
You are an adversarial reviewer for an implementation plan. Read PLAN.md and repository files as needed, but do not modify files. Identify concrete flaws and a one-line fix for each. End with exactly one line: VERDICT: APPROVED or VERDICT: REVISE.
EOF
```

### Round 1 — fresh session (capture `thread_id`)
```bash
if rg -q '^approval_policy\s*=\s*"never"' ~/.codex/config.toml && rg -q '^sandbox_mode\s*=\s*"danger-full-access"' ~/.codex/config.toml; then CODEX_EXEC_ACCESS=--dangerously-bypass-approvals-and-sandbox; CODEX_RESUME_ACCESS=--dangerously-bypass-approvals-and-sandbox; else CODEX_EXEC_ACCESS='-s read-only'; CODEX_RESUME_ACCESS='-c sandbox_mode="read-only"'; fi
if ! timeout 600 codex exec $CODEX_EXEC_ACCESS --json -o "$VERDICT_FILE" "$(<"$PROMPT_FILE")" \
  < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
THREAD_ID=$(jq -r 'select(.type == "thread.started") | .thread_id' "$EVENTS_FILE" | head -n1)
[[ -n "$THREAD_ID" && "$THREAD_ID" != null && -s "$VERDICT_FILE" ]] || { printf 'Codex did not return a thread ID and verdict.\n' >&2; exit 1; }
```
The critique is in `$VERDICT_FILE`. Confirm both a thread ID and nonempty verdict; on failure report the private diagnostics. **`< /dev/null` is mandatory:** `codex exec` reads stdin in addition to the prompt arg, so under a non-interactive driver it blocks forever waiting on stdin EOF.

### Rounds 2..MAX — resume the SAME session (Codex remembers its prior critiques)
```bash
# resume REJECTS -s. Force read-only via -c sandbox_mode, or Codex inherits
# config.toml (possibly danger-full-access) and could WRITE files. This is the
# single most important safety line in the skill — verified 2026-06-04.
if ! timeout 600 codex exec resume "$THREAD_ID" $CODEX_RESUME_ACCESS --json \
  -o "$VERDICT_FILE" \
  "I revised the plan. Re-review PLAN.md — check whether your prior findings are addressed and flag anything new. End with VERDICT: APPROVED or VERDICT: REVISE." \
  < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review resume failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
[[ -s "$VERDICT_FILE" ]] || { printf 'Codex resume returned no verdict.\n' >&2; exit 1; }
```
Both `codex exec` and `codex exec resume` support `--json` and `-o/--output-last-message`. The `< /dev/null` redirect is required on the resume call too — same non-interactive stdin hang as Round 1.

**Timeout guard (both rounds):** run every `codex exec` / `codex exec resume` with a 10-minute ceiling so any future stall fails loud instead of hanging silently. Via Claude Code's Bash tool, pass `timeout: 600000` on the tool call (the default 2-minute tool timeout is too short for real reviews and would kill them mid-run). In a plain shell, prefix the command with `timeout 600` (Linux / Git Bash) or `gtimeout 600` (macOS via coreutils — stock macOS has no `timeout`). If the ceiling trips, treat it as a failed run: stop and tell the user rather than retrying blind.

### Each round, after Codex returns
1. Confirm the resume exits successfully and `$VERDICT_FILE` is nonempty; otherwise stop. Read `$VERDICT_FILE`; append to `LOG_FILE`: `## Round <n> — Codex` + the full critique.
2. Grep the last line for the verdict:
   - `VERDICT: APPROVED` → break to Resolution (converged).
   - `VERDICT: REVISE` → Claude decides **what's actually worth acting on** (Claude is final arbiter — Codex advises, doesn't command). Revise `PLAN_FILE`. Append `### Claude's response` to `LOG_FILE`: what changed, what was rejected, why. Increment round.
3. If round > `MAX_ROUNDS` → break to Resolution (deadlock).

### Resolution (you sign off — final gate)
- **APPROVED:** present the final `PLAN_FILE`, a 3-bullet summary of what the two acts improved, and the round count. Ask: *"Plan refined and challenged through N Codex rounds. Implement it now — Codex builds it (`/cowork:build`), Claude builds it, or stop here?"* Code only on a yes. **No code is written during either act.**
- **MAX_ROUNDS hit without APPROVED (deadlock):** do NOT fake convergence. List each unresolved point + Claude's counter-position; hand it to the user to break the tie. A flagged disagreement beats a false "approved."

### ACT 3 (optional) — BUILD (Codex ↔ Claude, roles flipped)

If the user picks Codex: invoke the `codex-build` skill with `SPEC_FILE=PLAN.md` and the same `LOG_FILE` — it appends `## Act 3 — Build` to the log, so one artifact tells the whole story (grilled → reviewed → built → verified). Roles flip: Codex writes the code with full access, Claude reviews the diff and runs the proof. If the user picks Claude, implement directly as usual.

---

## Hard rules
- Act 1 always precedes Act 2 — don't write `PLAN.md` until collaborative planning has resolved the decision tree with the user.
- Full access is inherited when authorized or already configured; otherwise Codex is read-only every round. The reviewer prompt forbids edits in both cases.
- The loop ALWAYS terminates at `MAX_ROUNDS`.
- Claude is final arbiter on every REVISE — incorporate good critiques, reject bad ones *with a logged reason*. Don't cave to everything (defeats the cross-model check) and don't ignore it (defeats the point).
- Code only after the user's final sign-off.
- `LOG_FILE` is the deliverable — keep the complete decision record.

## What NOT to do
- Don't review already-written code — that's `/codex:review`.
- Don't pin a `-codex` model variant on ChatGPT-account auth — it 400s.
- Don't let Codex edit files. Read-only, always.
- Don't skip Act 1 — collaborative planning is half the value.
