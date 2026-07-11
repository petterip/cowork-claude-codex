#!/usr/bin/env bash
set -euo pipefail

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
  AWS_BEARER_TOKEN_BEDROCK \
  CLAUDE_CODE_API_KEY_HELPER_TTL_MS \
  CLAUDE_CODE_USE_BEDROCK \
  CLAUDE_CODE_USE_VERTEX \
  CLAUDE_CODE_USE_FOUNDRY \
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

[[ "${CLAUDE_RALLY_SUBSCRIPTION_ONLY-}" == "1" ]] || fail \
  'set CLAUDE_RALLY_SUBSCRIPTION_ONLY=1 only after disabling Claude usage credits in your account.'

auth_status=$(claude auth status --json) || fail 'Claude authentication status is unavailable.'
printf '%s' "$auth_status" | jq -e '
  .loggedIn == true and
  .authMethod == "claude.ai" and
  .apiProvider == "firstParty" and
  (.subscriptionType | test("^(pro|max|team|enterprise)"; "i"))
' >/dev/null || fail 'sign in with an eligible Claude subscription; API and cloud-provider authentication are not allowed.'

printf 'Claude subscription-only preflight passed.\n'
