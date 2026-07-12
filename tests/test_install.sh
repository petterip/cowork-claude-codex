#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent codex >/dev/null

[[ "$(readlink -f "$tmp/custom-codex/cowork")" == "$repo_root" ]]
for command in plan build review continue status setup; do
  link="$tmp/custom-codex/skills/cowork-$command"
  [[ -L "$link" ]]
  [[ "$(readlink -f "$link")" == "$repo_root/skills/cowork-$command" ]]
done
[[ ! -e "$tmp/home/.codex" ]]

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent codex >/dev/null

mkdir -p "$tmp/collision/cowork"
if HOME="$tmp/home" CODEX_HOME="$tmp/collision" \
  "$repo_root/install.sh" --agent codex >/dev/null 2>&1; then
  printf '%s\n' 'Installer overwrote a foreign Cowork support directory.' >&2
  exit 1
fi

printf '%s\n' 'Cowork installer contract: PASS'
