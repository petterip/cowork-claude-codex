# WSL mobile-control operations review

Reviewed 2026-07-11 against `codex-mobile-wsl-full-access` at `735e799`.

## Scope and evidence

This review covers the public skill package, both shell scripts, its packaging metadata, and all nine commits in its history. I ran:

```text
bash skills/codex-mobile-wsl-full-access/scripts/test_verify_host.sh
shellcheck skills/codex-mobile-wsl-full-access/scripts/{verify_host,test_verify_host}.sh
codex remote-control --help
codex app-server daemon --help
```

The current contract test and ShellCheck pass. The checked host reported all six verification labels as `PASS`. There are no uncommitted changes, branches, or release tags beyond `main`.

The package is small, readable, and appropriately avoids embedding machine-specific setup. The main concern is that its success signals are process heuristics, rather than a single supported readiness probe, so a green report can describe two unrelated processes.

## Required before relying on it as an end-to-end gate

### 1. Correlate remote-control readiness with the managed daemon

`verify_host.sh` calls `codex app-server daemon version` and independently runs:

```bash
pgrep -f 'codex app-server --remote-control'
```

Either check can pass while the other describes a different process. `pgrep -f` matches the whole command line, so it is especially vulnerable to stale processes, wrapper processes, or an unrelated command containing that text. Conversely, a valid future CLI implementation may change its internal process arguments and make this produce a false failure.

The installed CLI documents daemon lifecycle commands and `codex remote-control start`, but it does not document process-name matching as a status API. Prefer a supported status/readiness command if a later CLI exposes one. Until then, have the verifier obtain the daemon's machine-readable result once, confirm it is running, and validate that remote control was enabled through the daemon's supported lifecycle command. If no stable machine-readable remote-control state exists, label this result `UNKNOWN`, not `PASS`.

Why this matters: the skill's completion report promises that remote control is running. That is the boundary that makes the mobile workflow usable, so it needs stronger evidence than a global process scan.

### 2. Bound every external diagnostic command

Both `docker ps` and `docker info` are run without a timeout, in both the verifier and the end-to-end instructions. A wedged Docker Desktop bridge, an unreachable context, or a blocked socket can leave an agent waiting indefinitely.

Use a short, overridable deadline, for example `timeout "${CODEX_WSL_CHECK_TIMEOUT_SECONDS:-10}" docker ps`, and report `TIMEOUT` separately from `FAIL`. Apply the same bounded command in the skill's end-to-end verification so the human and the script are testing the same contract.

Why this matters: operational diagnostics must fail promptly and preserve enough information to choose the next repair step.

## High-value improvements

### 3. Make configuration verification semantic, not line-oriented

The current regular expressions only accept top-level, double-quoted exact lines. They neither prove the file parses as TOML nor detect conflicting duplicate settings. Valid TOML formatting variations can therefore fail, while a malformed file containing the two matching lines can pass.

Use the Codex CLI's config validation/start path where possible, or a small TOML-aware reader available in the supported runtime. Check the effective top-level values and emit one concise diagnosis: missing file, parse error, missing key, or unexpected value. Do not print the configuration file itself.

This also makes the skill portable across harmless formatting changes and avoids agents "fixing" config that was already effective.

### 4. Separate capability discovery from health verification

`Codex CLI: PASS` is currently only `command -v codex`; `Managed app-server daemon: PASS` suppresses all stderr; and every failure collapses into an identical `FAIL`. An operator cannot distinguish an absent executable, an incompatible version, a bad config, or a stopped daemon.

Keep the stable `LABEL: PASS|FAIL|UNKNOWN` summary for parsers, but add a non-sensitive reason code on failure, such as `code=not-found`, `code=not-running`, `code=command-error`, or `code=timeout`. Capture command output only in a temporary local diagnostic file with restrictive permissions when an operator explicitly requests it; never put raw diagnostics in the normal report.

Also add a minimum CLI capability check: inspect `codex remote-control --help` (or a version/capabilities output) before instructing an older CLI to run the experimental command. The current local CLI shows remote control as experimental, which is a useful compatibility warning.

### 5. Test failure branches with command doubles

`test_verify_host.sh` runs the real verifier and only asserts that six labels occur. It does not prove the labels are correct for: non-WSL runtime, missing CLI, Docker permission denial, invalid TOML, a stopped daemon, or a false-positive process match. It also cannot run meaningfully in ordinary Linux CI because the actual runtime state drives its output.

Refactor the verifier to allow injected command paths or `PATH`-based doubles, then add hermetic fixture tests for each outcome and for timeout handling. Keep one optional `--live` smoke test for a real WSL host. This makes regressions detectable without needing a paired device, Docker Desktop, or a running daemon.

## Medium-priority maintainability and release improvements

### 6. Restore a portable validation workflow or document its replacement

Commit `99cc331` deleted the only GitHub Actions validation workflow because it was blocked. The repo now has no automated public check despite a useful local contract test. Add a minimal workflow that runs formatting/metadata checks and hermetic tests only; it should not invoke the live verifier. If GitHub Actions is intentionally unavailable, document the exact local release command and make it the single release gate.

### 7. Put the lifecycle contract in a concise troubleshooting matrix

The skill has good linear setup steps, but it does not map verifier states to the safe next action. Add a small table such as:

| Signal | Meaning | Next action |
| --- | --- | --- |
| CLI missing | Host cannot manage remote control | Install/update the CLI |
| Daemon stopped | No service is accepting mobile work | Start remote control, then re-check |
| Docker unavailable | Workload capability is absent | Diagnose Docker Desktop/socket, then re-check |
| Policy mismatch | New tasks will not inherit the desired policy | Correct config and begin a new task |

This preserves the "do not ask the user to run commands the agent can run" goal while reducing recovery guesswork. Keep the final completion report as short as it is now.

### 8. Clarify idempotency and ownership of each repair action

The instructions say to run `codex remote-control start` after a process failure, but they do not state whether the command is safe when a managed daemon is already present or whether it changes only the current process. The local CLI help says it starts the daemon with remote control enabled; the skill should say that the agent first performs the health check, invokes the supported command only for the failed state, and rechecks afterward.

Similarly, Docker group membership changes commonly take effect only in a fresh login session. State that postcondition explicitly and have the verifier report it as pending rather than repeatedly attempting a repair that cannot take effect in the existing process.

### 9. Add versioned release and compatibility metadata

The skill is publishable (`skills/.../SKILL.md` and `agents/openai.yaml` are correctly laid out), but it has no release tags, compatibility statement, or changelog. Add a short `README.md` with supported host assumptions (Windows + WSL2, a supported Codex CLI with remote-control commands, Docker only when requested), install/use instructions, and a minimal compatibility table. Tag tested releases.

This is particularly helpful because the underlying remote-control CLI is marked experimental and its status surface may evolve.

## Suggested implementation order

1. Replace the process-name remote-control assertion with a supported/explicit readiness state and add timeouts.
2. Add hermetic test doubles and restore an automated validation path that does not require WSL.
3. Make config checks TOML-aware and provide bounded reason codes.
4. Add the recovery matrix, post-login Docker note, and release/compatibility metadata.

No changes were made to the WSL repository during this review.
