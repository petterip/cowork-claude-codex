---
description: Check Cowork and its optional official Codex integration
allowed-tools: Bash(claude plugin:*), Bash(*verify-environment.sh)
---

Run `$CLAUDE_PLUGIN_ROOT/workflows/codex-claude-rally/scripts/verify-environment.sh`
and report its exact result. Run `claude plugin list` and report whether
`codex@openai-codex` is enabled.

The official plugin is optional. When absent, state that Cowork's local Codex
CLI fallback remains available. Never install or change authentication without
the user's request.
