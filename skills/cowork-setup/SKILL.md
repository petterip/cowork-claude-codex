---
name: cowork-setup
description: Verify that Codex-to-Claude Cowork prerequisites, authentication, full-access inheritance, and artifact storage are ready. Use before the first Cowork job or when delegation fails.
---

# Setup

Run `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/scripts/verify-environment.sh` and report its exact
result. Do not change credentials. A failed required check blocks delegation;
restricted full-access status is informational unless the user already
authorized full access.
