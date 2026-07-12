#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
router="$repo_root/plugins/cowork/scripts/cowork-route.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
official="$tmp/official"
log="$tmp/calls.log"
mkdir -p "$fake_bin" "$official/scripts"
touch "$official/scripts/codex-companion.mjs"

cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
printf 'node:%s\n' "$*" >>"$COWORK_TEST_LOG"
EOF
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex:%s\n' "$*" >>"$COWORK_TEST_LOG"
printf 'codex-argc:%s\n' "$#" >>"$COWORK_TEST_LOG"
EOF
chmod +x "$fake_bin/node" "$fake_bin/codex"

PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--wait'
grep -Fq 'node:' "$log"
grep -Fq ' review --wait' "$log"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review 'focus'
grep -Fq 'codex:review --uncommitted focus' "$log"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review '--base main focus'
grep -Fq 'codex:review --base main focus' "$log"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review
grep -Fq 'codex-argc:2' "$log"

printf '%s\n' 'Cowork router contract: PASS'
