---
description: Ask Codex to independently review the current Claude Code work
argument-hint: '[--base <ref>] [focus]'
allowed-tools: Bash(*cowork-route.sh:*)
---

Review the current code or diff, not an implementation plan.

Run `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh review "$ARGUMENTS"`. When the
arguments contain review focus text beyond routing flags, or explicitly
challenge a design, assumption, or risk, use action `adversarial-review`
instead because the official normal review accepts no custom focus. The router
uses the official plugin runtime when available and the local `codex review`
fallback otherwise.

Return findings without modifying files. The author model decides and applies
fixes only after presenting the review.
