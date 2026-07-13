#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  printf 'Rally job creation failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 2 ]] || fail 'usage: create-rally-job.sh <job-id> <read-only|write> --repo <absolute-git-root> [--allowed-path <relative-path>]... [--proof-command <command>]'
job_id=$1
mode=$2
shift 2
[[ "$job_id" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || fail 'job ID must be lowercase kebab-case.'
[[ "$mode" == read-only || "$mode" == write ]] || fail 'mode must be read-only or write.'

allowed_paths=()
proof_command=''
repository_arg=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 && -z "$repository_arg" ]] || fail '--repo requires one absolute Git repository root and may be supplied once.'
      [[ "$2" == /* && "$2" != *$'\n'* ]] || fail '--repo must be an absolute path.'
      repository_arg=$2
      shift 2
      ;;
    --allowed-path)
      [[ $# -ge 2 ]] || fail '--allowed-path requires a relative path.'
      [[ "$2" != /* && "$2" != '.' && "$2" != *'..'* && "$2" != *$'\n'* ]] || fail 'allowed paths must be normalized, non-root relative paths.'
      allowed_paths+=("$2")
      shift 2
      ;;
    --proof-command)
      [[ $# -ge 2 && -z "$proof_command" ]] || fail '--proof-command requires one command and may be supplied once.'
      [[ -n "$2" ]] || fail 'proof command must not be empty; use "none" when no proof is applicable.'
      proof_command=$2
      shift 2
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repository_arg" ]] || fail '--repo is required; pass the target repository root explicitly.'
if [[ "$mode" == write && ${#allowed_paths[@]} -eq 0 ]]; then
  fail 'write jobs require at least one --allowed-path.'
fi
if [[ "$mode" == write && -z "$proof_command" ]]; then
  fail 'write jobs require --proof-command; use "none" only when no proof is applicable.'
fi

[[ -d "$repository_arg" && ! -L "$repository_arg" ]] || fail '--repo must name a real directory, not a symlink.'
repository_arg=$(cd "$repository_arg" && pwd -P)
repository_path=$(git -C "$repository_arg" rev-parse --show-toplevel 2>/dev/null) || fail '--repo is not a Git repository.'
repository_path=$(cd "$repository_path" && pwd -P)
[[ "$repository_arg" == "$repository_path" ]] || fail '--repo must be the Git repository root, not a subdirectory.'
base_commit=$(git -C "$repository_path" rev-parse HEAD)
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
job_dir="$state_root/cowork-claude-codex/jobs/$job_id"
[[ ! -e "$job_dir" ]] || fail "job already exists: $job_dir"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
access_mode=$("$script_dir/detect-full-access.sh")

mkdir -p "$job_dir/requests" "$job_dir/responses" "$job_dir/reviews"
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ ${#allowed_paths[@]} -eq 0 ]]; then
  allowed_paths_json='[]'
else
  allowed_paths_json=$(printf '%s\n' "${allowed_paths[@]}" | jq -R . | jq -sc .)
fi
jq -n \
  --arg job_id "$job_id" \
  --arg mode "$mode" \
  --arg repository_path "$repository_path" \
  --arg base_commit "$base_commit" \
  --arg access_mode "$access_mode" \
  --argjson allowed_paths "$allowed_paths_json" \
  --arg proof_command "$proof_command" \
  --arg created_at "$created_at" \
  '{schema_version: 1, job_id: $job_id, mode: $mode, repository_path: $repository_path,
    base_commit: $base_commit, state: "CREATED", owner: "codex", round: 1,
    claude_worker_id: null, claude_session_id: null, worker_cwd: null,
    codex_thread_id: null, full_access_authorized: ($access_mode == "full"),
    allowed_paths: $allowed_paths, proof_command: (if $proof_command == "" then null else $proof_command end), artifact_digests: {requests: {}, responses: {}, reviews: {}}, created_at: $created_at, updated_at: $created_at}' \
  > "$job_dir/manifest.json"
printf '# Rally job: %s\n\nState: CREATED\nOwner: Codex\nRound: 001\n' "$job_id" > "$job_dir/state.md"
jq -nc --arg at "$created_at" --arg job_id "$job_id" \
  '{at: $at, actor: "codex", state: "CREATED", artifact: "manifest.json", exit_status: 0, job_id: $job_id}' \
  > "$job_dir/events.ndjson"
{
  printf '%s\n' '# Claude work request' '' '## Task' '<bounded outcome>' ''
  printf '## Mode and allowed paths\nMode: %s\n' "$mode"
  if [[ ${#allowed_paths[@]} -eq 0 ]]; then
    printf '%s\n' 'Allowed paths: none declared'
  else
    printf '%s\n' 'Allowed paths:'
    printf -- '- %s\n' "${allowed_paths[@]}"
  fi
  printf '%s\n' '' '## Source of truth' '<files, plan, issue, or URL references>' ''
  printf '## Proof command\n%s\n' "${proof_command:-none}"
  printf '%s\n' '' '## Non-goals' '<explicit bounds>'
} > "$job_dir/requests/001.md"

printf '%s\n' "$job_dir"
printf 'Rally repository: %s\nRally base commit: %s\n' "$repository_path" "$base_commit" >&2
