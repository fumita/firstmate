#!/usr/bin/env bash
# Live drift guard for the Devin CLI adapter's vendor-controlled surface:
# process name, hook events, rendered busy row, composer, interrupt (including
# the idle revert picker), and exit.
# Opt-in because it submits real prompts (no echo provider exists for devin).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVIN_BIN=$(command -v devin 2>/dev/null || true)
REAL_TMUX=$(command -v tmux 2>/dev/null || true)
MODEL=${FM_DEVIN_LIVE_MODEL:-gpt-5-6-luna-low}
LAB=
SOCKET="fm-devin-signals-$$"
TARGET=devin-signals:devin
VERSION=unknown

cleanup() {
  [ -n "$REAL_TMUX" ] && "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -z "$LAB" ] || rm -rf -- "$LAB"
}

fail() {
  printf 'not ok - devin (%s): %s\n' "$VERSION" "$1" >&2
  cleanup
  exit 1
}

pass() {
  printf 'ok - devin (%s): %s\n' "$VERSION" "$1"
}

fm_live_gate opt-in FM_DEVIN_SIGNALS_LIVE devin tmux jq
[ -n "$DEVIN_BIN" ] || fail "devin is not installed"
VERSION=$("$DEVIN_BIN" --version 2>/dev/null | head -1) || VERSION=unknown

# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-devin-signals.XXXXXX") || fail "could not create the isolated devin lab"
trap cleanup EXIT
WORKSPACE="$LAB/workspace"
EVENTS="$LAB/events.log"
mkdir -p "$WORKSPACE/.devin"
git -C "$WORKSPACE" init -q || fail "could not initialize the isolated workspace"
git -C "$WORKSPACE" -c user.email=guard@local -c user.name=guard commit -q --allow-empty -m init \
  || fail "could not seed the isolated workspace"
: > "$EVENTS"
# The same three events bin/fm-spawn.sh writes; any unsupported event would
# make devin ignore the whole file, which this guard would catch as silence.
jq -n --arg log "$EVENTS" '{hooks: ({} | .UserPromptSubmit = [{hooks: [{type: "command", command: ("echo UserPromptSubmit >> " + $log)}]}]
  | .Stop = [{hooks: [{type: "command", command: ("echo Stop >> " + $log)}]}]
  | .SessionEnd = [{hooks: [{type: "command", command: ("echo SessionEnd >> " + $log)}]}])}' \
  > "$WORKSPACE/.devin/config.local.json" || fail "could not write the hook table"

"$DEVIN_BIN" models list --format json </dev/null 2>/dev/null \
  | jq -e --arg m "$MODEL" '[.families[] | .family_uid, .slug, (.aliases[]?), (.variants[]?.model_uid)] | index($m)' >/dev/null \
  || fail "the account's model listing does not offer $MODEL; set FM_DEVIN_LIVE_MODEL"

tmx() { "$REAL_TMUX" -L "$SOCKET" "$@"; }
capture() { tmx capture-pane -p -t "$TARGET" 2>/dev/null || true; }
capture_styled() { tmx capture-pane -p -e -t "$TARGET" 2>/dev/null || true; }
cursor_row() { tmx display -p -t "$TARGET" '#{cursor_y}' 2>/dev/null; }
wait_for() {  # <seconds> <grep -E pattern>
  local n=$(($1 * 2))
  while [ "$n" -gt 0 ]; do
    capture | grep -qE -- "$2" && return 0
    sleep 0.5
    n=$((n - 1))
  done
  return 1
}
events() { tr '\n' ' ' < "$EVENTS"; }
composer_verdict() {
  fm_composer_classify_screen $'styled=1\ncursor=1' "$(capture_styled)" "$(cursor_row)"
}
# The control plane's exact interrupt sequence, read from its own tables.
control_interrupt() {
  local key repeat clear delay i=0
  key=$(fm_control_interrupt_key devin); repeat=$(fm_control_interrupt_repeat devin)
  clear=$(fm_control_interrupt_clear_key devin); delay=$(fm_control_interrupt_clear_delay devin)
  while [ "$i" -lt "$repeat" ]; do
    tmx send-keys -t "$TARGET" "$key"
    i=$((i + 1))
    [ "$i" -ge "$repeat" ] || sleep 0.2
  done
  [ -z "$clear" ] || { sleep "$delay"; tmx send-keys -t "$TARGET" "$clear"; }
}

tmx new-session -d -s devin-signals -n control -c "$WORKSPACE" -x 160 -y 40 \
  || fail "could not start the isolated tmux server"
tmx new-window -d -t devin-signals: -n devin -c "$WORKSPACE" \
  "exec env -u CLAUDECODE -u WAYLAND_DISPLAY '$DEVIN_BIN' --permission-mode dangerous --respect-workspace-trust false --model '$MODEL' -- 'Run the shell command: sleep 4 . Then reply with the sum of 12345 and 67890 and nothing else.'" \
  || fail "could not launch devin"

wait_for 60 'esc (twice|again) to interrupt' || fail "the launch prompt never showed the busy row"
capture | fm_busy_lines_match devin || fail "fm_busy_lines_match devin rejected the real busy row"
pass "the launch prompt auto-submits and the busy row matches devin's delivery signature"

pid=$(tmx display -p -t "$TARGET" '#{pane_pid}')
got=$("$ROOT/bin/fm-harness.sh" ancestry "$pid")
[ "$got" = "comm devin" ] || fail "ancestry of the live devin process read '$got'"
pass "ancestry reads the live process as comm devin"

wait_for 120 '80235|80,235' || fail "the worker never answered its launch prompt"
wait_for 30 'Ask Devin to build features' || fail "the idle placeholder never rendered"
sleep 1
case " $(events)" in *" UserPromptSubmit Stop "*) ;; *) fail "hooks fired '$(events)', expected UserPromptSubmit then Stop" ;; esac
[ "$(composer_verdict)" = empty ] || fail "the idle composer classified '$(composer_verdict)', not empty"
pass "UserPromptSubmit and Stop hooks bracket the turn and the idle composer reads empty"

# A worker can sit idle on a steer for minutes; with WAYLAND_DISPLAY set devin
# dropped the first prompt after about a minute idle with a connection reset.
sleep "${FM_DEVIN_LIVE_IDLE_SECS:-90}"

: > "$EVENTS"
tmx send-keys -t "$TARGET" -l 'Run the shell command: sleep 90 . Then reply done.'
sleep 1
tmx send-keys -t "$TARGET" Enter
# Wait for the tool row, not the echoed prompt, so the interrupt lands mid-turn.
wait_for 60 '\$ sleep 90|Connection reset by peer' || fail "the long turn never started"
capture | grep -q 'Connection reset by peer' && fail "the prompt after an idle composer failed with a connection reset"
wait_for 60 '\$ sleep 90' || fail "the long turn never started: $(capture | grep -v '^[[:space:]]*$' | tail -8 | tr '\n' '|')"
wait_for 30 'esc (twice|again) to interrupt' \
  || fail "the long turn never showed the busy row: $(capture | grep -v '^[[:space:]]*$' | tail -8 | tr '\n' '|')"
control_interrupt
wait_for 10 'Canceled\. What should Devin do\?' || fail "the control interrupt did not cancel the turn"
sleep 1
capture | grep -q 'Revert to step' && fail "the interrupt left the revert picker open"
[ "$(composer_verdict)" = empty ] || fail "after interrupt the composer classified '$(composer_verdict)'"
case " $(events)" in *" Stop "*) fail "an interrupt fired Stop, so the busy-record limit changed: '$(events)'" ;; esac
pass "the control interrupt cancels a running turn, fires no Stop hook, and leaves an empty composer"

control_interrupt
sleep 1
capture | grep -q 'Revert to step' && fail "an idle control interrupt left the revert picker open"
[ "$(composer_verdict)" = empty ] || fail "after an idle interrupt the composer classified '$(composer_verdict)'"
pass "an idle control interrupt closes the revert picker it can open"

tmx send-keys -t "$TARGET" -l "$(fm_control_exit_command devin)"
sleep 0.5
tmx send-keys -t "$TARGET" Enter
for _ in $(seq 1 40); do
  tmx list-windows -t devin-signals -F '#{window_name}' 2>/dev/null | grep -qx devin || break
  sleep 0.5
done
tmx list-windows -t devin-signals -F '#{window_name}' 2>/dev/null | grep -qx devin \
  && fail "devin did not exit on $(fm_control_exit_command devin)"
sleep 1
case " $(events)" in *" SessionEnd "*) ;; *) fail "exit fired '$(events)', expected SessionEnd" ;; esac
pass "the exit command stops devin and fires SessionEnd"
