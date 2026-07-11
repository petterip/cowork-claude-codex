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

Install with symlinks so this repository stays the single source of truth:

```bash
./install.sh --agent claude
```

### Codex

- `codex-claude-rally` — launch and resume persistent Claude workers with
  `claude --bg`, exchange durable work artifacts, and verify the result.
- `claude-handoff` — start a fresh Claude background worker from a Codex
  handoff summary.

Install with symlinks:

```bash
./install.sh --agent codex
```

## Collaboration contract

`codex-claude-rally` uses an external, versioned job directory. This remains
shared even when Claude Code isolates a write worker in a worktree:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs/<job-id>/
```

Each job has a machine-readable manifest/state machine, immutable numbered
requests, responses, and reviews, plus an append-only event log. The job
protocol defaults to external artifacts, records the base commit and worker
worktree, and requires independent Codex verification before acceptance.

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

Run the privacy-safe environment check before a rally:

```bash
CLAUDE_RALLY_SUBSCRIPTION_ONLY=1 \
  skills/codex-claude-rally/scripts/verify-environment.sh
```

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
