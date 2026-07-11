#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verifier="$skill_dir/scripts/verify-environment.sh"

for script in "$skill_dir"/scripts/*.sh; do bash -n "$script"; done
output=$(CLAUDE_RALLY_SUBSCRIPTION_ONLY=1 "$verifier")
for check in 'Codex CLI:' 'Claude Code CLI:' 'Subscription-only authentication:' 'Full-access inheritance:' 'External artifact root:'; do
  grep -Fq "$check" <<<"$output"
done

grep -Fq 'full_access_authorized' "$skill_dir/SKILL.md"
grep -Fq 'WAITING_FOR_HUMAN' "$skill_dir/references/job-protocol.md"
grep -Fq 'STOPPED' "$skill_dir/references/job-protocol.md"
if rg -n '^claude -p' "$skill_dir" >/dev/null; then
  printf '%s\n' 'Skill contains a claude -p command.' >&2
  exit 1
fi

printf '%s\n' 'Rally skill contract: PASS'
