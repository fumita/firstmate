# Devin CLI

Devin's `devin` TUI, verified end to end on 2026-09-18 with devin 3000.10.31 on Linux through the Herdr backend.
Verified as a CREWMATE and SCOUT adapter only; `../../../../../bin/fm-spawn.sh` refuses a secondmate launch on it because `../../../../../docs/supervision-protocols/` carries no devin wake protocol.
`../../../../../docs/verification/devin.md` owns how every fact below was established and what is still unproven.

## Operating facts

| Fact | Value |
|---|---|
| Binary | Absolute `devin` from `PATH`, refused if absent; `~/.local/bin/devin` links to a versioned static binary, and both the TUI and its `devin acp` tool host run as `comm=devin`. |
| Launch | `env -u WAYLAND_DISPLAY devin --permission-mode dangerous --respect-workspace-trust false --model <id> -- "<brief>"`; the prompt after `--` auto-submits. With `WAYLAND_DISPLAY` set on WSLg, an idle devin touched the Wayland clipboard about a minute in and then dropped the next prompt with `Io error: Connection reset by peer`, so the spawn clears it and keeps X11 `DISPLAY`. |
| Models | `devin models list --format json`; `--model` accepts a family id, slug, alias, or variant id, and the spawn refuses one a reachable listing omits. |
| Effort | No flag: variant ids carry the level (`claude-opus-5-high`), so the shared effort axis stays in task metadata under the record-and-omit contract. |
| Busy | Firstmate-owned hooks in the worktree's `.devin/config.local.json` write the `devin-hook` record: `UserPromptSubmit` opens, `Stop` and `SessionEnd` close. |
| Turn end | `Stop` also touches the turn-ended notification. |
| Exit | `/exit`, one Enter; the completion popup's Enter runs it and `SessionEnd` fires. |
| Interrupt | Double `Escape`: one press only rearms the row to `(esc again to interrupt)`, and the pair prints `Canceled. What should Devin do?` above an empty composer. On an IDLE composer the same pair (gap under about 0.25 seconds) opens the `Revert to step` picker, where Enter would revert the conversation, so control follows with one more `Escape` after one second: it closes the picker, and a lone idle `Escape` changes nothing. Never use `Ctrl+C`: on an idle composer it arms `Press Ctrl+C again to exit.` |
| Skill | No verified slash-skill form; use natural language. |
| Resume | `devin -c` and `devin -r <session-id>` exist but carry no verified pane-resume contract; use deterministic relaunch. |
| Autonomy | `--permission-mode dangerous` auto-approves every tool. |
| Trust | An untrusted directory parks on `Do you trust the authors of this directory?`; `--respect-workspace-trust false` skips it for that launch without writing devin's trust store. |
| Marker | None; tools inherit no devin identity (`DEVIN_PROJECT_DIR` reaches hooks only) and keep an inherited `CLAUDECODE`, so detection is anchored `devin` ancestry. |
| Composer | Bare `❭` row between a titled rule `──── (bypass permissions on) ─` and a solid rule; placeholders `Ask Devin to build features, fix bugs, or work on your code` and, mid-turn, `Guide Devin while it works` in truecolor luminance 124. |
| Delivery footer | `(esc twice to interrupt)` or `(esc again to interrupt)` on the spinner row while a turn runs. |

## Busy hooks and their limits

devin validates its hook table as a whole: a file naming any unsupported event (`StopFailure`, `Notification`, `SubagentStop`, `PreCompact`) silently disables every hook in it, so the spawn writes exactly the three verified events.
The file is devin's own uncommitted project layer and merges with the captain's `~/.config/devin/config.json`, including Herdr's own devin integration hooks.
A `--config` file is never used: it replaces the user config and re-runs first-time setup against a different organization.
The spawn keeps the file out of git through the worktree's exclude file, refuses a project that tracks `.devin/config.local.json`, retires it on relaunch, and removes it at cleanup only when untracked.
A double-Escape interrupt fires no hook, so like claude the record stays busy until the next submitted turn.

## Primary integration

Unsupported and unverified.
devin has Claude-shaped hooks, but no wake protocol or turn-end guard exists for it and only the crewmate side was verified.
`references/common/primary-hooks.md`'s unsupported-boundary rule applies: never invent a wake protocol from a similar TUI.
devin is deliberately absent from the session-lock name vocabulary, like the other crewmate-only adapters.

## Credential and quota

The verified worker ran on the account stored by `devin auth login` in `~/.local/share/devin/credentials.toml`, and `devin auth status` reports it.
Treat any sign-in prompt as a credential blocker under `../../../../../AGENTS.md` section 9 rather than typing into the pane.
`quota-axi` has no devin provider, so a devin dispatch candidate carries quota as disclosed uncertainty.
