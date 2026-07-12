#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
marketplace="$repo_root/.claude-plugin/marketplace.json"
plugin_root="$repo_root/plugins/cowork"

[[ -f "$marketplace" ]]
[[ -f "$plugin_root/.claude-plugin/plugin.json" ]]
jq -e '.name == "cowork-claude-codex" and .plugins[0].name == "cowork" and .plugins[0].source == "./plugins/cowork"' "$marketplace" >/dev/null
jq -e '.owner.name == "Petteri Ponsimaa" and .metadata.version == "1.0.0" and .plugins[0].version == "1.0.0" and .plugins[0].author.name == "Petteri Ponsimaa"' "$marketplace" >/dev/null
jq -e '.name == "cowork" and .version == "1.0.0" and .author.name == "Petteri Ponsimaa"' "$plugin_root/.claude-plugin/plugin.json" >/dev/null

wrong_identity="Petteri Piir"'onen'
if rg --hidden -n -g '!.git/**' "$wrong_identity" "$repo_root"; then
  printf '%s\n' 'Incorrect author identity remains in the repository.' >&2
  exit 1
fi

for command in plan build review continue status setup; do
  [[ -f "$plugin_root/commands/$command.md" ]]
done

for legacy in plan-with-docs review-plan handoff; do
  [[ ! -e "$plugin_root/commands/$legacy.md" ]]
done

if find "$plugin_root/commands" -type f -name '*grill*' | grep -q .; then
  printf '%s\n' 'Legacy grill command remains public.' >&2
  exit 1
fi

grep -Fq 'cowork-route.sh review' "$plugin_root/commands/review.md"
grep -Fq '/codex:rescue' "$plugin_root/commands/build.md"
grep -Fq 'cowork-route.sh transfer' "$plugin_root/commands/continue.md"
grep -Fq 'claude plugin list' "$plugin_root/commands/setup.md"
grep -Fq 'fallback' "$plugin_root/commands/setup.md"

for skill in plan build review continue status setup; do
  [[ -f "$repo_root/skills/cowork-$skill/SKILL.md" ]]
done

if rg -n '/cowork:(plan-with-docs|review-plan|handoff)' "$repo_root/README.md" "$repo_root/skills" "$plugin_root/commands"; then
  printf '%s\n' 'Shipped guidance references a removed public command.' >&2
  exit 1
fi

for source in codex-build codex-review grill-me-codex grill-with-docs-codex codex-claude-rally; do
  diff -qr -B "$repo_root/skills/$source" "$plugin_root/workflows/$source" >/dev/null
done

printf '%s\n' 'Cowork Claude plugin contract: PASS'
