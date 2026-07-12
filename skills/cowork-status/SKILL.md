---
name: cowork-status
description: Show active and recent Cowork jobs and Claude workers for the current repository. Use when the user asks what cross-model work is running, finished, blocked, or resumable.
---

# Status

Read Rally manifests under
`${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs` and query
`claude agents --cwd "$PWD" --all --json`. Present one compact table with job,
direction, state, owner, round, worker, and next action. Do not mutate jobs.
Include only manifests whose `repository_path` equals
`git rev-parse --show-toplevel`, unless the user explicitly requests all repos.
