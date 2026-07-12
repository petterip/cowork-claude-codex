---
description: Show active and recent cross-model work for this repository
argument-hint: '[job-id]'
allowed-tools: Bash(*cowork-route.sh:*), Bash(claude agents:*), Bash(find:*)
---

Show one compact table combining:

- official Codex jobs via
  `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh status "$ARGUMENTS"` when the
  router exits zero;
- Claude background workers from `claude agents --cwd "$PWD" --all --json`;
- Cowork Rally manifests under
  `${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs`.

For manifests, include only entries whose `repository_path` equals
`git rev-parse --show-toplevel`, unless `$ARGUMENTS` explicitly requests all
repositories. Filter to `$ARGUMENTS` when it names a job. Do not mutate,
resume, or cancel anything.
