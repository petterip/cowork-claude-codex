#!/usr/bin/env bash
set -euo pipefail

status() {
  printf '%s: %s\n' "$1" "$2"
}

if command -v codex >/dev/null 2>&1; then status 'Codex CLI' PASS; else status 'Codex CLI' FAIL; fi
if command -v claude >/dev/null 2>&1; then status 'Claude Code CLI' PASS; else status 'Claude Code CLI' FAIL; fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if "$script_dir/assert-subscription-auth.sh" >/dev/null 2>&1; then
  status 'Subscription-only authentication' PASS
else
  status 'Subscription-only authentication' FAIL
fi

if [[ "$("$script_dir/detect-full-access.sh")" == full ]]; then
  status 'Full-access inheritance' PASS
else
  status 'Full-access inheritance' FAIL
fi

state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
artifact_root="$state_root/cowork-claude-codex/jobs"
if mkdir -p "$artifact_root" && probe=$(mktemp "$artifact_root/.probe.XXXXXX") && rm -f "$probe"; then
  status 'External artifact root' PASS
else
  status 'External artifact root' FAIL
fi
