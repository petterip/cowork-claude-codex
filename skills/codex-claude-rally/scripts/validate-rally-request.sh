#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Rally request validation failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail 'usage: validate-rally-request.sh <request-file>'
request=$1
[[ -f "$request" && ! -L "$request" ]] || fail 'request must be a regular file, not a symlink.'

headings=(
  '## Task'
  '## Mode and allowed paths'
  '## Source of truth'
  '## Proof command'
  '## Non-goals'
)
for heading in "${headings[@]}"; do
  grep -Fxq "$heading" "$request" || fail "missing heading: $heading"
  awk -v heading="$heading" '
    $0 == heading { inside = 1; next }
    inside && /^## / { exit }
    inside && $0 !~ /^[[:space:]]*$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$request" || fail "section has no content: $heading"
done

placeholders=(
  '<bounded outcome>'
  '<read-only or write; exact relative paths>'
  '<files, plan, issue, or URL references>'
  '<exact command or none>'
  '<explicit bounds>'
)
for placeholder in "${placeholders[@]}"; do
  if grep -Fq "$placeholder" "$request"; then
    fail "unresolved template placeholder: $placeholder"
  fi
done
