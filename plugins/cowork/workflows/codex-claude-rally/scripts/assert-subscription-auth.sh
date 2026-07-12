#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  printf 'Claude launch blocked: %s\n' "$1" >&2
  exit 1
}

for variable in \
  ANTHROPIC_API_KEY \
  ANTHROPIC_AUTH_TOKEN \
  ANTHROPIC_BASE_URL \
  ANTHROPIC_BEDROCK_BASE_URL \
  ANTHROPIC_VERTEX_BASE_URL \
  ANTHROPIC_AWS_ACCESS_KEY_ID \
  ANTHROPIC_AWS_SECRET_ACCESS_KEY \
  ANTHROPIC_AWS_SESSION_TOKEN \
  AWS_BEARER_TOKEN_BEDROCK \
  MANTLE_API_KEY \
  CLAUDE_CODE_API_KEY_HELPER_TTL_MS \
  CLAUDE_CODE_USE_BEDROCK \
  CLAUDE_CODE_USE_VERTEX \
  CLAUDE_CODE_USE_FOUNDRY \
  CLAUDE_CODE_USE_MANTLE \
  CLAUDE_CODE_SKIP_BEDROCK_AUTH \
  CLAUDE_CODE_SKIP_VERTEX_AUTH; do
  if [[ -n "${!variable-}" ]]; then
    fail "${variable} selects API, gateway, or cloud-provider authentication."
  fi
done

for settings_file in \
  "$HOME/.claude/settings.json" \
  "$HOME/.claude.json" \
  "$PWD/.claude/settings.json" \
  "$PWD/.claude/settings.local.json"; do
  if [[ -f "$settings_file" ]] && jq -e '.. | objects | select(has("apiKeyHelper"))' "$settings_file" >/dev/null; then
    fail "${settings_file} configures apiKeyHelper."
  fi
done

auth_status=$(claude auth status --json) || fail 'Claude authentication status is unavailable.'
printf '%s' "$auth_status" | jq -e '
  .loggedIn == true and
  .authMethod == "claude.ai" and
  .apiProvider == "firstParty" and
  (.subscriptionType | test("^(pro|max|team|enterprise)"; "i"))
' >/dev/null || fail 'sign in with an eligible Claude subscription; API and cloud-provider authentication are not allowed.'

printf 'Claude subscription authentication preflight passed.\n'
