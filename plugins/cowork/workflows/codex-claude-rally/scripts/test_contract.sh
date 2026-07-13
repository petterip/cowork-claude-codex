#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verifier="$skill_dir/scripts/verify-environment.sh"
rallyctl="$skill_dir/scripts/rallyctl.sh"

fail() {
  printf 'Rally contract test failed: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
}

expect_failure "$skill_dir/scripts/create-rally-job.sh" missing-repo read-only

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
fake_home="$tmp/home"
fake_state="$tmp/state"
mkdir -p "$fake_bin" "$fake_home/.claude" "$fake_state"

for script in "$skill_dir"/scripts/*.sh; do bash -n "$script"; done
expect_failure env PATH="/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" "$verifier"

cat > "$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == 'auth status --json' ]]; then
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}'
  exit 0
fi
exit 1
EOF
chmod +x "$fake_bin/codex" "$fake_bin/claude"
printf '%s\n' 'approval_policy = "never"' 'sandbox_mode = "danger-full-access"' > "$fake_home/.codex-config"
mkdir -p "$fake_home/.codex"
mv "$fake_home/.codex-config" "$fake_home/.codex/config.toml"

output=$(PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" "$verifier")
for check in 'Codex CLI: PASS' 'Claude Code CLI: PASS' 'Subscription authentication: PASS' 'Full-access inheritance: PASS' 'External artifact root: PASS'; do
  grep -Fq "$check" <<<"$output"
done

repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name test
printf '%s\n' base > "$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit -qm base
expect_failure "$skill_dir/scripts/create-rally-job.sh" missing-proof write --repo "$repo" --allowed-path src

write_request() {
  local request=$1
  printf '%s\n' \
    '# Claude work request' '' '## Task' 'Review the bounded target.' '' \
    '## Mode and allowed paths' 'Read-only or exact declared write scope.' '' \
    '## Source of truth' 'The declared repository files.' '' \
    '## Proof command' 'none' '' '## Non-goals' 'Do not exceed the declared scope.' \
    > "$request"
}

job_dir=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" test-job write --repo "$repo" --allowed-path src --proof-command 'true')
[[ "$(jq -r '.repository_path' "$job_dir/manifest.json")" == "$repo" ]] || fail 'explicit repository path was not recorded.'
grep -Fq 'Mode: write' "$job_dir/requests/001.md" || fail 'request mode was not prefilled.'
grep -Fq -- '- src' "$job_dir/requests/001.md" || fail 'request allowed paths were not prefilled.'
grep -Fxq 'true' "$job_dir/requests/001.md" || fail 'request proof command was not prefilled.'
"$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
expect_failure "$rallyctl" transition "$job_dir" CREATED RUNNING codex
worker="$tmp/worker"
git -C "$repo" worktree add -q --detach "$worker"
"$rallyctl" bind-worker "$job_dir" "$worker"
expect_failure "$rallyctl" transition "$job_dir" CREATED RUNNING codex
write_request "$job_dir/requests/001.md"
"$rallyctl" transition "$job_dir" CREATED RUNNING codex
printf '%s\n' tampered > "$job_dir/requests/001.md"
expect_failure "$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
write_request "$job_dir/requests/001.md"
mkdir -p "$worker/src"
printf '%s\n' ok > "$worker/src/allowed.txt"
"$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
printf '%s\n' no > "$worker/outside.txt"
expect_failure "$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
rm "$worker/outside.txt"
expect_failure "$rallyctl" transition "$job_dir" CREATED VERIFYING codex
printf '%s\n' response > "$job_dir/responses/001.md"
"$rallyctl" transition "$job_dir" RUNNING WAITING_FOR_CODEX claude
printf '%s\n' tampered > "$job_dir/responses/001.md"
expect_failure "$rallyctl" transition "$job_dir" WAITING_FOR_CODEX VERIFYING codex
printf '%s\n' response > "$job_dir/responses/001.md"
"$rallyctl" transition "$job_dir" WAITING_FOR_CODEX VERIFYING codex
printf '%s\n' review > "$job_dir/reviews/001.md"
"$rallyctl" transition "$job_dir" VERIFYING ACCEPTED codex
expect_failure "$rallyctl" transition "$job_dir" ACCEPTED RUNNING codex

readonly_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" readonly-job read-only --repo "$repo")
grep -Fq 'Mode: read-only' "$readonly_job/requests/001.md" || fail 'read-only request mode was not prefilled.'
grep -Fq 'Allowed paths: none declared' "$readonly_job/requests/001.md" || fail 'empty allowed paths were not prefilled.'
grep -Fxq 'none' "$readonly_job/requests/001.md" || fail 'default proof command was not prefilled.'
"$skill_dir/scripts/validate-rally-job.sh" "$readonly_job"
expect_failure "$rallyctl" transition "$readonly_job" CREATED RUNNING codex
write_request "$readonly_job/requests/001.md"
"$rallyctl" transition "$readonly_job" CREATED RUNNING codex
"$rallyctl" record-worker "$readonly_job" worker-1 null "$repo"
"$rallyctl" record-worker "$readonly_job" worker-1 session-1 "$repo"
"$rallyctl" record-worker "$readonly_job" worker-1 session-1 "$repo"
[[ "$(jq -r '.claude_worker_id' "$readonly_job/manifest.json")" == worker-1 ]] || fail 'worker ID was not recorded.'
[[ "$(jq -r '.claude_session_id' "$readonly_job/manifest.json")" == session-1 ]] || fail 'worker session ID was not completed.'
expect_failure "$rallyctl" record-worker "$readonly_job" worker-2 session-2 "$repo"

stopped_template_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" stopped-template-job read-only --repo "$repo")
"$rallyctl" transition "$stopped_template_job" CREATED STOPPED codex
"$skill_dir/scripts/validate-rally-job.sh" "$stopped_template_job"

followup_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" followup-job read-only --repo "$repo")
write_request "$followup_job/requests/001.md"
"$rallyctl" transition "$followup_job" CREATED RUNNING codex
printf '%s\n' response > "$followup_job/responses/001.md"
"$rallyctl" transition "$followup_job" RUNNING WAITING_FOR_CODEX claude
"$rallyctl" transition "$followup_job" WAITING_FOR_CODEX VERIFYING codex
write_request "$followup_job/requests/002.md"
"$rallyctl" transition "$followup_job" VERIFYING RUNNING codex
[[ "$(jq -r '.round' "$followup_job/manifest.json")" == 2 ]] || fail 'follow-up did not increment the round.'
"$skill_dir/scripts/validate-rally-job.sh" "$followup_job"

grep -Fq 'full_access_authorized' "$skill_dir/SKILL.md"
grep -Fq 'WAITING_FOR_HUMAN' "$skill_dir/references/job-protocol.md"
grep -Fq 'STOPPED' "$skill_dir/references/job-protocol.md"
if rg -n '^claude -p' "$skill_dir" >/dev/null; then
  printf '%s\n' 'Skill contains a claude -p command.' >&2
  exit 1
fi
if rg -n 'REVIEW_PROMPT|/tmp/codex-(build|verdict)' "$skill_dir/../codex-build" "$skill_dir/../codex-review" "$skill_dir/../grill-me-codex" "$skill_dir/../grill-with-docs-codex" >/dev/null; then
  printf '%s\n' 'Claude-to-Codex skill contains an undefined prompt or predictable result path.' >&2
  exit 1
fi

printf '%s\n' 'Rally skill contract: PASS'
