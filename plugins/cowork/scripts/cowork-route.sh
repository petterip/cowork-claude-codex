#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork routing failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 1 ]] || fail 'usage: cowork-route.sh <review|adversarial-review|transfer|status> [arguments]'
action=$1
arguments=${2:-}

resolve_official_runtime() {
  local root candidate
  if [[ -n "${COWORK_CODEX_PLUGIN_ROOT-}" ]]; then
    root=$COWORK_CODEX_PLUGIN_ROOT
  else
    command -v claude >/dev/null 2>&1 || return 1
    claude plugin list 2>/dev/null | grep -Fq 'codex@openai-codex' || return 1
    root=''
    while IFS= read -r candidate; do root=$candidate; done < <(
      find "$HOME/.claude/plugins/cache/openai-codex/codex" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V
    )
  fi
  [[ -n "$root" && -f "$root/scripts/codex-companion.mjs" ]] || return 1
  printf '%s\n' "$root/scripts/codex-companion.mjs"
}

runtime=$(resolve_official_runtime || true)
case "$action" in
  review|adversarial-review)
    if [[ -n "$runtime" ]]; then
      exec node "$runtime" "$action" "$arguments"
    fi
    [[ "$action" == review ]] || fail 'adversarial review requires codex@openai-codex.'
    read -r -a words <<<"$arguments"
    review_args=()
    focus=()
    index=0
    while (( index < ${#words[@]} )); do
      case "${words[$index]}" in
        --wait|--background) ((index += 1)) ;;
        --base)
          (( index + 1 < ${#words[@]} )) || fail '--base requires a ref.'
          review_args+=(--base "${words[$((index + 1))]}")
          ((index += 2))
          ;;
        *) focus+=("${words[$index]}"); ((index += 1)) ;;
      esac
    done
    [[ ${#review_args[@]} -gt 0 ]] || review_args=(--uncommitted)
    if [[ ${#focus[@]} -gt 0 ]]; then
      exec codex review "${review_args[@]}" "${focus[*]}"
    fi
    exec codex review "${review_args[@]}"
    ;;
  transfer|status)
    [[ -n "$runtime" ]] || exit 2
    exec node "$runtime" "$action" "$arguments"
    ;;
  *) fail "unsupported action: $action" ;;
esac
