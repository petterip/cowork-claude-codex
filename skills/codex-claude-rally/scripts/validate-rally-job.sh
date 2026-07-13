#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  printf 'Rally job validation failed: %s\n' "$1" >&2
  exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
request_validator="$script_dir/validate-rally-request.sh"

[[ $# -eq 1 ]] || fail 'usage: validate-rally-job.sh <job-directory>'
job_dir=$1
[[ -d "$job_dir" && ! -L "$job_dir" ]] || fail 'job directory must be a real directory, not a symlink.'
job_dir=$(cd "$job_dir" && pwd -P)
manifest="$job_dir/manifest.json"
[[ -f "$manifest" && ! -L "$manifest" ]] || fail 'manifest.json is missing or a symlink.'

jq -e '
  .schema_version == 1 and
  (.job_id | test("^[a-z0-9][a-z0-9-]{0,62}$")) and
  (.mode == "read-only" or .mode == "write") and
  (.proof_command == null or ((.proof_command | type) == "string" and (.proof_command | length) > 0)) and
  (.mode != "write" or (.proof_command | type) == "string") and
  (.state | IN("CREATED", "RUNNING", "WAITING_FOR_CODEX", "VERIFYING", "WAITING_FOR_HUMAN", "ACCEPTED", "REJECTED", "STOPPED")) and
  (.round | type == "number" and . >= 1) and
  (.full_access_authorized | type == "boolean") and
  (.artifact_digests | type == "object" and (.requests | type == "object") and (.responses | type == "object") and (.reviews | type == "object")) and
  (.allowed_paths | type == "array" and all(.[]; (type == "string") and (length > 0) and (startswith("/") | not) and (. != ".") and (contains("..") | not)))
' "$manifest" >/dev/null || fail 'manifest schema is invalid.'

repository_path=$(jq -r '.repository_path' "$manifest")
base_commit=$(jq -r '.base_commit' "$manifest")
[[ -d "$repository_path" && ! -L "$repository_path" ]] || fail 'repository path must be a real directory, not a symlink.'
repository_root=$(git -C "$repository_path" rev-parse --show-toplevel 2>/dev/null) || fail 'repository path is not a Git repository.'
repository_root=$(cd "$repository_root" && pwd -P)
[[ "$repository_root" == "$repository_path" ]] || fail 'repository path is not the Git repository root.'
git -C "$repository_path" rev-parse --verify "$base_commit^{commit}" >/dev/null || fail 'base commit is unavailable.'
state=$(jq -r '.state' "$manifest")
mode=$(jq -r '.mode' "$manifest")
round=$(printf '%03d' "$(jq -r '.round' "$manifest")")
recorded_request_digest=$(jq -r --arg round "$round" '.artifact_digests.requests[$round] // empty' "$manifest")
if [[ "$state" != CREATED && "$state" != STOPPED || -n "$recorded_request_digest" ]]; then
  request="$job_dir/requests/$round.md"
  [[ -f "$request" && ! -L "$request" ]] || fail "immutable request is missing: requests/$round.md"
  "$request_validator" "$request" || fail "immutable request is incomplete: requests/$round.md"
  request_digest=$(sha256sum "$request" | awk '{print $1}')
  [[ "$recorded_request_digest" == "$request_digest" ]] || fail 'request digest changed after launch.'
fi
if [[ "$mode" == write && "$state" != CREATED ]]; then
  worker_cwd=$(jq -r '.worker_cwd' "$manifest")
  [[ "$worker_cwd" != null && -d "$worker_cwd" ]] || fail 'write job has no recorded worker worktree.'
  worker_root=$(git -C "$worker_cwd" rev-parse --show-toplevel 2>/dev/null) || fail 'recorded worker path is not a Git worktree.'
  [[ "$worker_root" == "$worker_cwd" && "$worker_cwd" != "$repository_path" ]] || fail 'write job worker must be an isolated worktree root.'
  git -C "$repository_path" worktree list --porcelain | grep -Fxq "worktree $worker_cwd" || fail 'recorded worker is no longer registered by the source repository.'
  worker_head=$(git -C "$worker_cwd" rev-parse HEAD)
  git -C "$worker_cwd" merge-base --is-ancestor "$base_commit" "$worker_head" || fail 'worker history does not descend from the recorded base commit.'
  changed_paths=$( { git -C "$worker_cwd" diff --name-only "$base_commit"; git -C "$worker_cwd" ls-files --others --exclude-standard; } | sort -u)
  while IFS= read -r changed_path; do
    [[ -z "$changed_path" ]] && continue
    jq -e --arg path "$changed_path" '.allowed_paths | any(. as $allowed | $path == $allowed or ($path | startswith($allowed + "/")))' "$manifest" >/dev/null || fail "worker changed path outside allowed scope: $changed_path"
  done <<< "$changed_paths"
fi
printf 'Rally job is valid: %s\n' "$(jq -r '.job_id' "$manifest")"
