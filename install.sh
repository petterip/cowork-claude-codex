#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Installation failed: %s\n' "$1" >&2
  exit 1
}

agent=${1:---agent}
target=${2:-both}
[[ "$agent" == --agent ]] || fail 'usage: ./install.sh --agent <claude|codex|both>'
[[ "$target" == claude || "$target" == codex || "$target" == both ]] || fail 'agent must be claude, codex, or both.'

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

install_skill() {
  local source=$1
  local destination_root=$2
  local name
  local destination

  name=$(basename "$source")
  destination="$destination_root/$name"
  mkdir -p "$destination_root"
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ "$(readlink -f "$destination")" == "$source" ]] || fail "$destination already exists; do not overwrite it automatically."
    printf 'Already linked: %s\n' "$destination"
    return
  fi
  ln -s "$source" "$destination"
  printf 'Linked: %s → %s\n' "$destination" "$source"
}

if [[ "$target" == claude || "$target" == both ]]; then
  for name in grill-me-codex grill-with-docs-codex codex-review codex-build; do
    install_skill "$repo_root/skills/$name" "$HOME/.claude/skills"
  done
fi

if [[ "$target" == codex || "$target" == both ]]; then
  for name in codex-claude-rally claude-handoff; do
    install_skill "$repo_root/skills/$name" "$HOME/.codex/skills"
  done
fi
