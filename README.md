# cowork-claude-codex

Skills for deliberate collaboration between Claude Code and OpenAI Codex.

Claude can grill a plan, ask Codex to attack it in a read-only sandbox, and
optionally have Codex implement the approved plan while Claude verifies the
diff. Codex can also launch a persistent Claude Code background worker and
exchange work through durable artifacts.

## Included skills

### Claude Code

- `grill-me-codex` — interview the user, then have Codex adversarially review
  the plan.
- `grill-with-docs-codex` — the documentation-aware variant.
- `codex-review` — review an existing plan with Codex before implementation.
- `codex-build` — Codex implements a frozen plan; Claude reviews and verifies.

Install these into Claude Code:

```bash
cp -R skills/grill-me-codex skills/grill-with-docs-codex \
  skills/codex-review skills/codex-build ~/.claude/skills/
```

### Codex

- `codex-claude-rally` — launch and resume persistent Claude workers with
  `claude --bg`, exchange durable work artifacts, and verify the result.
- `claude-handoff` — start a fresh Claude background worker from a Codex
  handoff summary.

Install these into Codex:

```bash
cp -R skills/codex-claude-rally skills/claude-handoff ~/.codex/skills/
```

## Collaboration contract

`codex-claude-rally` uses `.model-rally/<job-id>/` in the target repository:

- `request.md` — bounded task and allowed paths.
- `response.md` — Claude's durable result.
- `from-codex.md` — Codex's independent verification or follow-up request.

Claude workers are started with `claude --bg`, not `claude -p`. The worker ID
and Claude session ID are available via `claude agents --all --json`; use the
session ID for bounded follow-up rounds.

## Subscription-only gate

Before every Codex-initiated Claude launch or resume, the rally skill runs
`scripts/assert-subscription-auth.sh`. It blocks API keys, gateway tokens,
Bedrock, Vertex, Foundry, API-key helpers, and non-subscription authentication.

The user must also disable Claude usage credits in their account and then set:

```bash
export CLAUDE_RALLY_SUBSCRIPTION_ONLY=1
```

The account-level usage-credit setting cannot be inspected from the CLI, so the
explicit variable is a required human confirmation. The gate never clears or
changes credentials automatically.

## Safety boundaries

- Codex is read-only during plan review.
- Do not let Claude and Codex edit the same paths concurrently.
- Review the full diff and independently run proof commands before accepting a
  worker's result.
- Do not commit, push, deploy, or change credentials from a worker.
- Stop after two unsuccessful follow-up rounds and resolve the remaining work
  directly or ask the user.

## Attribution and license

The Claude-side plan-review skills are adapted from
[chaseai-yt/grill-me-codex](https://github.com/chaseai-yt/grill-me-codex),
which is MIT licensed. The grill components retain their Matt Pocock notices in
`THIRD-PARTY-NOTICES.md`. The original MIT license is included in `LICENSE`.

The Codex rally, subscription gate, and Claude handoff additions are released
under the same MIT terms.
