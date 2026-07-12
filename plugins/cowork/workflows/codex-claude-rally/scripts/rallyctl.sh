#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  printf 'Rally control failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 1 ]] || fail 'usage: rallyctl.sh <bind-worker|record-worker|transition> ...'
command=$1
shift

canonical_dir() {
  [[ -d "$1" ]] || fail "directory does not exist: $1"
  (cd "$1" && pwd -P)
}

manifest_for() {
  local job_dir=$1
  [[ -f "$job_dir/manifest.json" ]] || fail 'manifest.json is missing.'
  printf '%s\n' "$job_dir/manifest.json"
}

with_lock() {
  local job_dir=$1
  shift
  mkdir -p "$job_dir"
  exec 9>"$job_dir/.lock"
  flock -x 9
  "$@"
}

write_manifest() {
  local manifest=$1
  local content=$2
  local tmp
  tmp=$(mktemp "${manifest}.tmp.XXXXXX")
  printf '%s\n' "$content" > "$tmp"
  mv -f "$tmp" "$manifest"
}

bind_worker() {
  [[ $# -eq 2 ]] || fail 'usage: rallyctl.sh bind-worker <job-directory> <worker-worktree>'
  local job_dir worker manifest repository_path worker_repo
  job_dir=$(canonical_dir "$1")
  worker=$(canonical_dir "$2")
  manifest=$(manifest_for "$job_dir")
  repository_path=$(jq -r '.repository_path' "$manifest")
  worker_repo=$(git -C "$worker" rev-parse --show-toplevel 2>/dev/null) || fail 'worker directory is not a Git worktree.'
  [[ "$worker_repo" == "$worker" ]] || fail 'worker path must be its Git worktree root.'
  [[ "$worker" != "$repository_path" ]] || fail 'write jobs require an isolated worker worktree.'
  git -C "$repository_path" worktree list --porcelain | grep -Fxq "worktree $worker" || fail 'worker is not registered by the source repository.'
  with_lock "$job_dir" bind_worker_locked "$job_dir" "$worker"
}

bind_worker_locked() {
  local job_dir=$1 worker=$2 manifest content
  manifest=$(manifest_for "$job_dir")
  [[ "$(jq -r '.mode' "$manifest")" == write ]] || fail 'only write jobs require a worker worktree.'
  [[ "$(jq -r '.state' "$manifest")" == CREATED ]] || fail 'worker worktree may only be bound while the job is CREATED.'
  [[ "$(jq -r '.worker_cwd' "$manifest")" == null ]] || fail 'worker worktree is already bound.'
  content=$(jq --arg worker "$worker" '.worker_cwd = $worker' "$manifest")
  write_manifest "$manifest" "$content"
}

record_worker() {
  [[ $# -eq 4 ]] || fail 'usage: rallyctl.sh record-worker <job-directory> <worker-id> <session-id|null> <worker-cwd>'
  local job_dir worker_id session_id worker_cwd
  job_dir=$(canonical_dir "$1")
  worker_id=$2
  session_id=$3
  worker_cwd=$(canonical_dir "$4")
  with_lock "$job_dir" record_worker_locked "$job_dir" "$worker_id" "$session_id" "$worker_cwd"
}

record_worker_locked() {
  local job_dir=$1 worker_id=$2 session_id=$3 worker_cwd=$4 manifest content mode bound_worker
  manifest=$(manifest_for "$job_dir")
  [[ "$(jq -r '.state' "$manifest")" == RUNNING ]] || fail 'worker metadata may only be recorded while RUNNING.'
  [[ "$(jq -r '.claude_worker_id' "$manifest")" == null ]] || fail 'worker metadata is already recorded.'
  mode=$(jq -r '.mode' "$manifest")
  bound_worker=$(jq -r '.worker_cwd' "$manifest")
  if [[ "$mode" == write ]]; then
    [[ "$bound_worker" == "$worker_cwd" ]] || fail 'write job worker metadata must match its bound isolated worktree.'
  fi
  content=$(jq --arg worker_id "$worker_id" --arg session_id "$session_id" --arg worker_cwd "$worker_cwd" \
    '.claude_worker_id = $worker_id | .claude_session_id = (if $session_id == "null" then null else $session_id end) | .worker_cwd = $worker_cwd' "$manifest")
  write_manifest "$manifest" "$content"
}

transition() {
  [[ $# -eq 4 ]] || fail 'usage: rallyctl.sh transition <job-directory> <expected-state> <next-state> <actor>'
  local job_dir
  job_dir=$(canonical_dir "$1")
  with_lock "$job_dir" transition_locked "$job_dir" "$2" "$3" "$4"
}

transition_locked() {
  local job_dir=$1 expected=$2 next=$3 actor=$4 manifest state mode worker now content tmp event_tmp round request response review request_digest response_digest review_digest next_round followup_count
  manifest=$(manifest_for "$job_dir")
  state=$(jq -r '.state' "$manifest")
  [[ "$state" == "$expected" ]] || fail "expected state $expected, found $state."
  case "$state:$next" in
    CREATED:RUNNING|RUNNING:WAITING_FOR_CODEX|WAITING_FOR_CODEX:VERIFYING|VERIFYING:ACCEPTED|VERIFYING:REJECTED|VERIFYING:WAITING_FOR_HUMAN|VERIFYING:RUNNING|RUNNING:WAITING_FOR_HUMAN|CREATED:STOPPED|RUNNING:STOPPED|WAITING_FOR_CODEX:STOPPED|VERIFYING:STOPPED) ;;
    *) fail "illegal transition: $state -> $next." ;;
  esac
  mode=$(jq -r '.mode' "$manifest")
  worker=$(jq -r '.worker_cwd' "$manifest")
  round=$(printf '%03d' "$(jq -r '.round' "$manifest")")
  if [[ "$state:$next" == CREATED:RUNNING && "$mode" == write && "$worker" == null ]]; then
    fail 'write jobs need a bound worker worktree before RUNNING.'
  fi
  request="$job_dir/requests/$round.md"
  response="$job_dir/responses/$round.md"
  review="$job_dir/reviews/$round.md"
  if [[ "$state:$next" == CREATED:RUNNING ]]; then
    [[ -f "$request" && ! -L "$request" ]] || fail "missing immutable request: requests/$round.md"
    request_digest=$(sha256sum "$request" | awk '{print $1}')
  fi
  if [[ "$state:$next" == RUNNING:WAITING_FOR_CODEX ]]; then
    [[ -f "$response" && ! -L "$response" ]] || fail "missing immutable response: responses/$round.md"
    response_digest=$(sha256sum "$response" | awk '{print $1}')
  fi
  if [[ "$state:$next" == WAITING_FOR_CODEX:VERIFYING ]]; then
    [[ -f "$response" && ! -L "$response" ]] || fail "missing immutable response: responses/$round.md"
    response_digest=$(sha256sum "$response" | awk '{print $1}')
    [[ "$(jq -r --arg round "$round" '.artifact_digests.responses[$round] // empty' "$manifest")" == "$response_digest" ]] || fail 'response digest changed after publication.'
  fi
  if [[ "$state:$next" == VERIFYING:RUNNING ]]; then
    followup_count=$(jq -r '.followup_count // 0' "$manifest")
    (( followup_count < 2 )) || fail 'follow-up round limit reached; require human review.'
    next_round=$(printf '%03d' "$((10#$round + 1))")
    [[ -f "$job_dir/requests/$next_round.md" && ! -L "$job_dir/requests/$next_round.md" ]] || fail "missing immutable follow-up request: requests/$next_round.md"
    request_digest=$(sha256sum "$job_dir/requests/$next_round.md" | awk '{print $1}')
  fi
  if [[ "$state:$next" == VERIFYING:ACCEPTED || "$state:$next" == VERIFYING:REJECTED ]]; then
    [[ -f "$review" && ! -L "$review" ]] || fail "missing independent review: reviews/$round.md"
    review_digest=$(sha256sum "$review" | awk '{print $1}')
  fi
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  content=$(jq --arg state "$next" --arg actor "$actor" --arg now "$now" \
    --arg round "$round" --arg request_digest "${request_digest-}" --arg response_digest "${response_digest-}" --arg review_digest "${review_digest-}" \
    '.state = $state | .owner = $actor | .updated_at = $now |
      if $request_digest != "" then .artifact_digests.requests[$round] = $request_digest else . end |
      if $response_digest != "" then .artifact_digests.responses[$round] = $response_digest else . end |
      if $review_digest != "" then .artifact_digests.reviews[$round] = $review_digest else . end |
      if $from_state == "VERIFYING" and $next == "RUNNING" then
        .round = (.round + 1) | .followup_count = ((.followup_count // 0) + 1) |
        .artifact_digests.requests[$next_round] = $request_digest
      else . end' \
    --arg from_state "$state" --arg next "$next" --arg next_round "${next_round-}" "$manifest")
  write_manifest "$manifest" "$content"
  tmp=$(mktemp "$job_dir/state.md.tmp.XXXXXX")
  printf '# Rally job: %s\n\nState: %s\nOwner: %s\nRound: %03d\n' \
    "$(jq -r '.job_id' "$manifest")" "$next" "$actor" "$(jq -r '.round' "$manifest")" > "$tmp"
  mv -f "$tmp" "$job_dir/state.md"
  event_tmp=$(mktemp "$job_dir/events.ndjson.tmp.XXXXXX")
  jq -nc --arg at "$now" --arg actor "$actor" --arg state "$next" \
    --arg job_id "$(jq -r '.job_id' "$manifest")" \
    '{at: $at, actor: $actor, state: $state, artifact: "manifest.json", exit_status: 0, job_id: $job_id}' > "$event_tmp"
  cat "$event_tmp" >> "$job_dir/events.ndjson"
  rm -f "$event_tmp"
}

case "$command" in
  bind-worker) bind_worker "$@" ;;
  record-worker) record_worker "$@" ;;
  transition) transition "$@" ;;
  *) fail "unknown command: $command" ;;
esac
