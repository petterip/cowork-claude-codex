---
name: cowork-plan
description: Plan work in Codex and use Claude as the independent second model. Use when requirements need clarification, an implementation plan needs challenge, or documentation-aware planning is requested before code.
---

# Plan

Resolve the goal and write a bounded implementation plan. For material work,
read `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/SKILL.md` and delegate a read-only challenge review
to Claude. Incorporate sound findings, record rejected findings with reasons,
and require human approval before implementation.

When glossary or ADR files exist, align terminology and record only durable,
hard-to-reverse decisions. Ask only questions that cannot be answered from the
repository and materially change the plan.
