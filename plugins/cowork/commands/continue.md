---
description: Continue the current Claude Code work in Codex
argument-hint: '[focus]'
allowed-tools: Bash(*cowork-route.sh:*), Bash(codex exec:*)
---

Run `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh transfer "$ARGUMENTS"`. A zero
exit means the official plugin created a resumable Codex thread.

On exit 2, compact the current work into a handoff containing the goal, current
state, decisions, referenced artifacts, remaining work, proof, and `$ARGUMENTS`.
Start a fresh Codex session with that handoff, inherit full access when already
authorized, capture its explicit thread ID, and return the exact
`codex resume <thread-id>` command. Do not edit project files during transfer.
