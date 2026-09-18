# Verification: the devin (Devin CLI) crewmate/scout adapter

Active empirical facts for firstmate's devin adapter.
The skill tree rooted at [`.agents/skills/harness-adapters/SKILL.md`](../../.agents/skills/harness-adapters/SKILL.md) owns the operating facts through [`references/harness/devin.md`](../../.agents/skills/harness-adapters/references/harness/devin.md); this record owns how they were established and what is still unproven.

## Subject

| Field | Value |
|---|---|
| Version | `devin 3000.10.31 (b98cc431)` |
| Verified | 2026-09-18 |
| Binary | `~/.local/bin/devin`, a link to `~/.local/share/devin/cli/_versions/3000.10.31/bin/devin`, an ELF 64-bit static-pie executable |
| Platform | Linux x64 under WSL2 (kernel 6.18.33.2-microsoft-standard-WSL2) with WSLg (`WAYLAND_DISPLAY=wayland-0`, `DISPLAY=:0`) |
| Backend | Herdr 0.9.1, in isolated non-`default` lab sessions (`fm-lab-fm-devin-adapter-*` via `bin/fm-herdr-lab.sh`), plus private `tmux -L` servers for probes; the live `default` session passed the helper's fleet-state tripwire after every lab |
| Account | Signed in through `devin auth login` (credentials in `~/.local/share/devin/credentials.toml`) |

Every probe ran in a scratch git repository or the lab home's scratch project, never a captain project.

## Detection: ancestry only, no marker

`ps -o pid,ppid,comm,args` during a live turn showed the TUI as `comm=devin` and its tool host as `comm=devin` with args `.../bin/devin acp`, with the tool's `bash -c` as a child of the tool host:

```
809642  809641 devin  devin --permission-mode dangerous --respect-workspace-trust false --model gpt-5-6-luna-low -- Run: ...
810378  809642 devin  /home/fumita/.local/share/devin/cli/_versions/3000.10.31/bin/devin acp
823560  810378 bash   bash -c sleep 8 && ps -o pid,ppid,comm,args ...
```

A tool subprocess's environment carried no devin identity variable, only the launcher's inherited `CLAUDECODE=1` and `AI_AGENT`; hooks additionally receive `DEVIN_PROJECT_DIR`.
`bin/fm-harness.sh` therefore matches the anchored name `devin` in the ancestry walk, the launch clears `CLAUDECODE` and the other foreign markers, and `bin/fm-harness.sh ancestry <pane-pid>` returned `comm devin` on the live process.
Herdr recognizes the pane natively: `herdr agent get` reported `"agent":"devin"` with `"source":"herdr:devin"` and `working`/`idle` status, through Herdr's own devin integration hooks in `~/.config/devin/config.json`.

## Launch, trust, autonomy, and models

`devin --help` documents `-- <PROMPT>` as starting an interactive session, `--permission-mode dangerous` as auto-approving all tools, and `--respect-workspace-trust [true|false]`.
Without that flag a fresh directory outside the trusted list parked on:

```
 ✱ Do you trust the authors of this directory?
 ❭ 1 Yes, trust
 · 2 No, exit
```

With `--respect-workspace-trust false` the same directory launched straight into the prompt, and `~/.local/share/devin/cli/trusted_workspaces.json` was unchanged.
`devin models list --format json` returns families with `family_uid`, `slug`, `aliases`, and `variants[].model_uid`; effort is part of the variant id (`claude-opus-5-low` through `-max`, `gpt-5-6-luna-none` through `-max`).
`devin -p x --model bogus-model-xyz` exited with `Error: Unknown model: 'bogus-model-xyz'` and the family list, so `bin/fm-spawn.sh` refuses an id a reachable listing omits.

## Busy state: three hook events in `.devin/config.local.json`

Hooks written to a project's `.devin/config.local.json` fired in print mode and interactively, merged with the user config's own hooks:

```
16:29:07 SessionStart {"hook_event_name":"SessionStart","source":"startup","session_id":"towering-sponge"}
16:29:07 UserPromptSubmit {"hook_event_name":"UserPromptSubmit","prompt":"...","session_id":"towering-sponge","prompt_id":"80254556-..."}
16:29:10 PreToolUse {"hook_event_name":"PreToolUse","tool_name":"exec",...}
16:29:46 UserPromptSubmit {"hook_event_name":"UserPromptSubmit","prompt":"reply with the single word pong",...}
16:29:48 Stop {"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"pong",...}
16:29:58 SessionEnd {"hook_event_name":"SessionEnd","reason":"prompt_input_exit",...}
```

The double-Escape interrupt between those turns fired no hook.
Adding any one of `StopFailure`, `Notification`, `SubagentStop`, or `PreCompact` to the table silenced every hook in the file, including the three that fired a run earlier, so the spawn writes exactly `UserPromptSubmit`, `Stop`, and `SessionEnd`.
`devin --config <file>` was rejected as the wiring point: that file replaced the user config, re-ran first-time setup, and wrote a different `org_id` into it.

## Composer and delivery footer

A styled tmux capture of the idle pane:

```
────────────────────────────────────────── (bypass permissions on) ─
❭ Ask Devin to build features, fix bugs, or work on your code        (38;2;124;124;124)
────────────────────────────────────────────────────────────────────
GPT-5.6 Luna Low Thinking                        Context: 13k / 1.0M tokens (1%)
```

Mid-turn the placeholder reads `Guide Devin while it works` and the spinner row reads `⠀⠚ Thinking · 4s (esc twice to interrupt)` or `Running tools · 17s (...)`.
The solid rule below the glyph row alone looked like a lone Pi separator to the cursorless selector, so `bin/fm-composer-lib.sh` lets a titled rule open the separator pair; the styled read then classifies the idle composer `empty` and typed input `pending` with and without a cursor row, while an unstyled read stays `unknown`.

## Interrupt, the revert picker, and Ctrl+C

A single Escape mid-turn only changed the row to `(esc again to interrupt)`; two presses 0.2 to 0.4 seconds apart printed `Canceled due to user interrupt` and `Canceled. What should Devin do?` above an empty composer.
On an idle composer two Escapes opened `Revert to step:` with a step list and `↵ revert`; measured gaps of 0.1 and 0.2 seconds opened it and 0.3 to 3.0 seconds did not, and one more Escape closed it.
A lone Escape on an idle composer left the screen byte-identical.
The first Herdr lab run hit exactly this: the interrupt left the busy record busy, `fm-control exit` re-sent the double Escape into the idle composer, and the opened picker made exit refuse on `pending`.
`bin/fm-control-lib.sh` therefore sends one more Escape one second after the pair.
A single Ctrl+C on an idle composer printed `Press Ctrl+C again to exit.`, so a repeated Ctrl+C would stop the worker rather than a turn, and Ctrl+C is never an interrupt key for devin.
The connection reset that probe showed afterwards also followed more than a minute of idle, and is attributed to the Wayland issue below rather than to Ctrl+C.

## Idle prompts and `WAYLAND_DISPLAY`

With WSLg's `WAYLAND_DISPLAY=wayland-0` in the environment, a prompt submitted after 47 or 90 seconds of idle failed with `Io error: Connection reset by peer (os error 104)` and was dropped, and devin's TUI log showed an `arboard` Wayland clipboard initialization failure shortly before.
With only `WAYLAND_DISPLAY` removed (`DISPLAY=:0` kept) a prompt after 100 seconds of idle ran normally, as did one after 135 seconds with both removed, and neither log carried a clipboard entry.
The spawn therefore clears `WAYLAND_DISPLAY` for devin, and the live guard idles 90 seconds before its second prompt.

## Supervised task through the new path

A trivial scout ran end to end through `bin/fm-spawn.sh <id> <scratch-project> --scout --harness devin --model gpt-5-6-luna-low --backend herdr` in a lab session, with firstmate's own lifecycle scripts driving every step:

```
spawned dvlive3 harness=devin kind=scout window=fm-lab-fm-devin-adapter-1619788-7972:w1:p2 worktree=...
busy: ... state=busy source=fm-spawn event=launch-brief
busy: ... state=busy source=devin-hook event=user-prompt-submit
busy: ... state=idle source=devin-hook event=stop
done: repository contains 1 tracked file
```

The worktree's `git status --porcelain` stayed empty with the hooks file in place, and `state/<id>.turn-ended` was touched at the `Stop`.
After a 90-second idle composer, a `bin/fm-send.sh` steer rang the doorbell, the worker read and acknowledged its inbox record into `handled/`, answered `PONG`, and the record went busy then idle through `devin-hook`.
`bin/fm-control.sh <id> interrupt` on a running `sleep 90` turn reported `interrupt-delivered ... verified=agent-alive cancel=unconfirmed` and the pane showed `Canceled. What should Devin do?`; the busy record stayed at `user-prompt-submit`, as expected.
A second interrupt on the now idle composer left no `Revert to step` picker, and `bin/fm-control.sh <id> exit` then reported `stopped` and retired the busy record.
After `bin/fm-captain-hold.sh complete <id> --none`, `bin/fm-teardown.sh <id>` returned the worktree to its pool and completed, and the lab helper's teardown verified the `default` session's fleet state unchanged.

## What is still unproven

No primary or secondmate behavior was built or tested, and none is claimed.
The unauthenticated failure mode was not observed.
No slash-skill invocation form was verified, so skill invocation stays natural language.
`devin -c` and `devin -r` resume were not exercised; recovery uses deterministic relaunch from the brief on disk.
Whether the Wayland clipboard failure also occurs outside WSLg is unknown; clearing `WAYLAND_DISPLAY` is harmless where it does not.
The busy record stays busy after an interrupt until the next submitted turn, the same limit claude carries.

## Refreshing this record

Run the portable suite and the prompt-submitting live guard after any devin upgrade:

```
bin/fm-test-run.sh tests/fm-devin-harness.test.sh
FM_DEVIN_SIGNALS_LIVE=1 bin/fm-test-run.sh tests/fm-devin-signals-live-e2e.test.sh
```

The live guard's 2026-09-18 run on `devin 3000.10.31 (b98cc431)` passed all six checks: launch and busy row, ancestry, hook bracketing with an empty idle composer, control interrupt after a 90-second idle, idle interrupt with no picker left open, and exit with `SessionEnd`.
- The guard was rerun on 2026-09-18 after the exact-name matching and titled-rule placeholder fixes, and again passed all six checks on `devin 3000.10.31 (b98cc431)`.
- A second supervised Herdr-lab scout on that same code passed spawn, the launch-brief turn, a durable steer after a 30-second idle composer, an interrupt of a running turn, an idle interrupt that left no `Revert to step` picker, exit, and cleanup, and the lab helper again verified the `default` session unchanged.
