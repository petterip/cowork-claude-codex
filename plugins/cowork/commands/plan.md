---
description: Resolve what to build and produce a cross-model-reviewed implementation plan
argument-hint: '[--docs] [existing plan path] [task]'
---

Choose one canonical workflow:

1. Existing plan path or explicit plan-review request: read and run
   `$CLAUDE_PLUGIN_ROOT/workflows/codex-review/SKILL.md`.
2. `--docs`, `CONTEXT.md`, or relevant ADRs: read and run
   `$CLAUDE_PLUGIN_ROOT/workflows/grill-with-docs-codex/SKILL.md`.
3. Otherwise: read and run
   `$CLAUDE_PLUGIN_ROOT/workflows/grill-me-codex/SKILL.md`.

Pass `$ARGUMENTS` through. Call the activity collaborative planning. Ask only
decision-changing questions, write no production code before human approval,
and preserve the bounded cross-model review.
