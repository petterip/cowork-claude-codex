---
name: claude-handoff
description: Hand the current conversation off to a fresh Claude Code background agent that picks up the work immediately.
---

Write a handoff summary of the current conversation so a fresh agent can continue the work. Before launching, run `$HOME/.codex/skills/codex-claude-rally/scripts/assert-subscription-auth.sh`. If it fails, do not launch Claude or change credentials; report the blocker.

Resolve access before launch: `ACCESS_ARGS=(); if [[ "$("$HOME/.codex/skills/codex-claude-rally/scripts/detect-full-access.sh")" == full ]]; then ACCESS_ARGS=(--dangerously-skip-permissions); fi`. Launch a background agent seeded with the summary: `claude --bg "${ACCESS_ARGS[@]}" --name "<descriptive name>" "<handoff summary>"`. Full access is mandatory when the user authorized it or Codex already uses danger-full-access; otherwise preserve Claude's default permission mode. It starts in the current working directory and returns immediately; manage it with `claude agents`.

Always pass `-n`/`--name` with a descriptive name. Include a "suggested skills" section in the summary, reference existing PRDs, plans, ADRs, issues, commits, and diffs instead of duplicating them, and redact secrets or personally identifiable information.

If the user passed arguments, use them to tailor the next session's focus.
