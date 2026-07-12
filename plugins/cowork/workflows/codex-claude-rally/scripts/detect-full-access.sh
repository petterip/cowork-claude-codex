#!/usr/bin/env bash
set -euo pipefail

config_file="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [[ "${COWORK_FULL_ACCESS_AUTHORIZED-}" == "1" ]] || { [[ -f "$config_file" ]] && rg -q '^approval_policy\s*=\s*"never"' "$config_file" && rg -q '^sandbox_mode\s*=\s*"danger-full-access"' "$config_file"; }; then
  printf 'full\n'
else
  printf 'restricted\n'
fi
