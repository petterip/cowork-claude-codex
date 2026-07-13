---
name: cowork-review
description: Ask Claude to independently review the current Codex work. Use for code, diff, design, security, or regression review when a second model should challenge completed or in-progress changes without editing them.
---

# Review

Read `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/SKILL.md` and create a read-only Claude review job.
Resolve the reviewed repository root from the user's task workspace and pass it
explicitly with `--repo`; never create the job from the Cowork skill directory
without that target. Give the exact base/diff scope and review focus. In
read-only mode, allowed paths are review targets and declared source-of-truth
files remain readable. Claude must not edit. Codex reads the immutable response,
verifies every finding against source, and owns all subsequent fixes.
