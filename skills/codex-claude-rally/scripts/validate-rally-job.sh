#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Rally job validation failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail 'usage: validate-rally-job.sh <job-directory>'
job_dir=$1
manifest="$job_dir/manifest.json"
[[ -f "$manifest" ]] || fail 'manifest.json is missing.'

jq -e '
  .schema_version == 1 and
  (.job_id | test("^[a-z0-9][a-z0-9-]{0,62}$")) and
  (.mode == "read-only" or .mode == "write") and
  (.state | IN("CREATED", "RUNNING", "WAITING_FOR_CODEX", "VERIFYING", "WAITING_FOR_HUMAN", "ACCEPTED", "REJECTED", "STOPPED")) and
  (.round | type == "number" and . >= 1) and
  (.full_access_authorized | type == "boolean")
' "$manifest" >/dev/null || fail 'manifest schema is invalid.'

repository_path=$(jq -r '.repository_path' "$manifest")
base_commit=$(jq -r '.base_commit' "$manifest")
git -C "$repository_path" rev-parse --verify "$base_commit^{commit}" >/dev/null || fail 'base commit is unavailable.'
current_commit=$(git -C "$repository_path" rev-parse HEAD)
[[ "$current_commit" == "$base_commit" ]] || fail 'repository HEAD no longer matches the recorded base commit; require human review.'
printf 'Rally job is valid: %s\n' "$(jq -r '.job_id' "$manifest")"
