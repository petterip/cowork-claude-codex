#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Rally job creation failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail 'usage: create-rally-job.sh <job-id> <read-only|write>'
job_id=$1
mode=$2
[[ "$job_id" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || fail 'job ID must be lowercase kebab-case.'
[[ "$mode" == read-only || "$mode" == write ]] || fail 'mode must be read-only or write.'

repository_path=$(git rev-parse --show-toplevel) || fail 'run from a Git repository.'
base_commit=$(git rev-parse HEAD)
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
job_dir="$state_root/cowork-claude-codex/jobs/$job_id"
[[ ! -e "$job_dir" ]] || fail "job already exists: $job_dir"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
access_mode=$("$script_dir/detect-full-access.sh")

mkdir -p "$job_dir/requests" "$job_dir/responses" "$job_dir/reviews"
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg job_id "$job_id" \
  --arg mode "$mode" \
  --arg repository_path "$repository_path" \
  --arg base_commit "$base_commit" \
  --arg access_mode "$access_mode" \
  --arg created_at "$created_at" \
  '{schema_version: 1, job_id: $job_id, mode: $mode, repository_path: $repository_path,
    base_commit: $base_commit, state: "CREATED", owner: "codex", round: 1,
    claude_worker_id: null, claude_session_id: null, worker_cwd: null,
    codex_thread_id: null, full_access_authorized: ($access_mode == "full"),
    allowed_paths: [], proof_command: null, created_at: $created_at}' \
  > "$job_dir/manifest.json"
printf '# Rally job: %s\n\nState: CREATED\nOwner: Codex\nRound: 001\n' "$job_id" > "$job_dir/state.md"
jq -nc --arg at "$created_at" --arg job_id "$job_id" \
  '{at: $at, actor: "codex", state: "CREATED", artifact: "manifest.json", exit_status: 0, job_id: $job_id}' \
  > "$job_dir/events.ndjson"
printf '%s\n' \
  '# Claude work request' \
  '' \
  '## Task' \
  '<bounded outcome>' \
  '' \
  '## Mode and allowed paths' \
  '<read-only or write; exact relative paths>' \
  '' \
  '## Source of truth' \
  '<files, plan, issue, or URL references>' \
  '' \
  '## Proof command' \
  '<exact command or none>' \
  '' \
  '## Non-goals' \
  '<explicit bounds>' \
  > "$job_dir/requests/001.md"

printf '%s\n' "$job_dir"
