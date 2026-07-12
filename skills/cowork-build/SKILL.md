---
name: cowork-build
description: Build a frozen, human-approved plan by delegating implementation from Codex to Claude and independently verifying the result. Use for bounded multi-file implementation where Claude should write and Codex should review.
---

# Build

Require a frozen plan, clean source checkout, exact allowed paths, and a proof
command. Read `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/SKILL.md` and create a write job in an
isolated Claude worktree. Codex must inspect the complete scoped diff and run
proof independently before asking the user whether to apply or commit it.
