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

remove_legacy_claude_skill() {
  local name=$1
  local destination="$HOME/.claude/skills/$name"
  [[ -L "$destination" ]] || return 0
  [[ "$(readlink -f "$destination")" == "$repo_root/skills/$name" ]] || return 0
  rm "$destination"
  printf 'Removed legacy Claude skill link: %s\n' "$destination"
}

remove_owned_codex_skill() {
  local name=$1
  local codex_home=${CODEX_HOME:-$HOME/.codex}
  local destination="$codex_home/skills/$name"
  [[ -L "$destination" ]] || return 0
  [[ "$(readlink -f "$destination")" == "$repo_root/skills/$name" ]] || return 0
  rm "$destination"
  printf 'Removed superseded Codex skill link: %s\n' "$destination"
}

install_claude_plugin() {
  command -v claude >/dev/null 2>&1 || fail 'Claude Code CLI is required to install the Cowork plugin.'
  claude plugin marketplace add "$repo_root"
  if claude plugin list 2>/dev/null | grep -Fq 'cowork@cowork-claude-codex'; then
    claude plugin update cowork@cowork-claude-codex
  else
    claude plugin install cowork@cowork-claude-codex
  fi
  for name in grill-me-codex grill-with-docs-codex codex-review codex-build; do
    remove_legacy_claude_skill "$name"
  done
  printf '%s\n' 'Restart Claude Code to use the updated /cowork:* commands.'
}

if [[ "$target" == claude || "$target" == both ]]; then
  install_claude_plugin
fi

if [[ "$target" == codex || "$target" == both ]]; then
  codex_home=${CODEX_HOME:-$HOME/.codex}
  support_root="$codex_home/cowork"
  mkdir -p "$codex_home"
  if [[ -e "$support_root" || -L "$support_root" ]]; then
    [[ "$(readlink -f "$support_root")" == "$repo_root" ]] || fail "$support_root already exists and is not this Cowork repository."
  else
    ln -s "$repo_root" "$support_root"
    printf 'Linked Cowork support files: %s → %s\n' "$support_root" "$repo_root"
  fi
  for name in codex-claude-rally claude-handoff; do
    remove_owned_codex_skill "$name"
  done
  for name in cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup; do
    install_skill "$repo_root/skills/$name" "$codex_home/skills"
  done
fi
