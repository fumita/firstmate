#!/usr/bin/env bash
# Behavior tests for the verified Devin CLI crewmate/scout adapter.
#
# The facts pinned here are the ones a Devin release could silently change and
# the ones a wrong guess would make dangerous:
#   1. devin publishes no harness-identity marker to its tools (DEVIN_PROJECT_DIR
#      reaches hooks only) and keeps an inherited CLAUDECODE, so detection is
#      ancestry alone on the anchored process name `devin`, which a structural
#      devin ancestor proves over the retained marker.
#   2. The launch carries the brief after `--` with --permission-mode dangerous,
#      --respect-workspace-trust false, and --model; effort lives in devin's
#      model ids, so the shared effort axis is recorded but never passed, and a
#      requested model a reachable `devin models list` omits refuses loudly.
#   3. Busy state is the devin-hook record written by hooks the spawn places in
#      the worktree's .devin/config.local.json: exactly the three verified
#      events (an unsupported event makes devin ignore the whole file), kept
#      out of git's view, refused on a project that tracks that path, and
#      executable end to end through the real busy writer.
#   4. Interrupt is a DOUBLE Escape, then one more Escape after a one-second
#      delay that closes the `Revert to step` picker the double Escape opens on
#      an idle composer; exit is /exit, and devin is a crewmate/scout adapter
#      only.
#   5. devin's composer sits between a titled rule and a solid rule; a styled
#      read proves it empty or pending with or without a cursor row, and its
#      `esc twice/again to interrupt` row is devin's own delivery signature.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# bin/fm-harness.sh checks verified ENV markers before ancestry. Drop the
# ambient markers so the asserted verdict does not depend on which harness
# launched the suite.
unset CLAUDECODE PI_CODING_AGENT FM_PI_HARNESS GROK_AGENT CURSOR_AGENT CURSOR_INVOKED_AS \
  ATLASSIAN_AGENT_TYPE ROVODEV_CLI GEMINI_CLI AGENT FM_OMP_HARNESS

# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

HARNESS="$ROOT/bin/fm-harness.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-devin-harness)

make_fake_ps() {  # <dir> -> fakebin whose ps reports FAKE_PS_COMM / FAKE_PS_ARGS
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' "${FAKE_PS_COMM:?}"; exit 0 ;;
  *"args="*) printf '%s\n' "${FAKE_PS_ARGS:?}"; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  printf '%s\n' "$fakebin"
}

test_devin_ancestry_detects_the_tui_and_its_tool_host() {
  local fakebin out
  fakebin=$(make_fake_ps "$TMP_ROOT/anc-native")
  out=$(FAKE_PS_COMM=devin FAKE_PS_ARGS='devin --permission-mode dangerous -- hi' \
    PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] || fail "the devin TUI must be detected by ancestry, got '$out'"
  # Tool subprocesses run under `devin acp`, whose comm is the versioned
  # install path's basename.
  out=$(FAKE_PS_COMM=/home/u/.local/share/devin/cli/_versions/3000.10.31/bin/devin \
    FAKE_PS_ARGS='/home/u/.local/share/devin/cli/_versions/3000.10.31/bin/devin acp' \
    PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] || fail "devin's acp tool host must be detected by ancestry, got '$out'"
  pass "fm-harness.sh: ancestry detects the devin TUI and its acp tool host"
}

test_devin_ancestry_rejects_unrelated_mentions() {
  local fakebin out
  fakebin=$(make_fake_ps "$TMP_ROOT/anc-negatives")
  out=$(FAKE_PS_COMM=devinfo FAKE_PS_ARGS='devinfo --all' PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" != devin ] || fail "an unrelated devinfo command must not detect devin, got '$out'"
  out=$(FAKE_PS_COMM=bash FAKE_PS_ARGS='bash -c "devin --help"' PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" != devin ] || fail "a shell argument naming devin must not detect devin, got '$out'"
  pass "fm-harness.sh: ancestry rejects unrelated devin mentions"
}

test_devin_outranks_inherited_claudecode_and_claims_no_marker() {
  local fakebin out
  # devin keeps an inherited CLAUDECODE in its tools' environment, so a
  # structural devin ancestor must win over it.
  fakebin=$(make_fake_ps "$TMP_ROOT/anc-claude")
  out=$(CLAUDECODE=1 FAKE_PS_COMM=devin FAKE_PS_ARGS='devin -- hi' PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] || fail "a structural devin ancestor must outrank an inherited CLAUDECODE, got '$out'"
  # Drive the signals apart: without the ancestor the marker still names claude,
  # and devin's hook-only variable is never an identity.
  out=$(CLAUDECODE=1 FAKE_PS_COMM=bash FAKE_PS_ARGS=bash PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = claude ] || fail "CLAUDECODE without a devin ancestor must still name claude, got '$out'"
  out=$(DEVIN_PROJECT_DIR=/tmp/x FAKE_PS_COMM=bash FAKE_PS_ARGS=bash PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" != devin ] || fail "DEVIN_PROJECT_DIR must never claim the devin identity, got '$out'"
  pass "fm-harness.sh: devin ancestry outranks a retained CLAUDECODE and no variable claims it"
}

test_devin_control_mechanics_are_the_verified_ones() {
  fm_control_harness_supported devin || fail "devin must be a supported control harness"
  [ "$(fm_control_harness_family devin)" = devin ] || fail "devin must map to its own family"
  fm_control_harness_supports_kind devin ship || fail "devin must run ships"
  fm_control_harness_supports_kind devin scout || fail "devin must run scouts"
  ! fm_control_harness_supports_kind devin secondmate || fail "devin must refuse secondmates"
  [ "$(fm_control_interrupt_key devin)" = Escape ] || fail "devin must interrupt on Escape"
  [ "$(fm_control_interrupt_repeat devin)" = 2 ] || fail "devin must interrupt on a double press"
  # The closing Escape shuts the revert picker a double Escape opens on an idle
  # composer, so it must land outside the double-press window.
  [ "$(fm_control_interrupt_clear_key devin)" = Escape ] || fail "devin must close with a trailing Escape"
  [ "$(fm_control_interrupt_clear_delay devin)" = 1 ] || fail "devin's closing Escape must wait out the window"
  [ "$(fm_control_interrupt_clear_delay muse)" = 0 ] || fail "other adapters must clear at once"
  [ "$(fm_control_interrupt_ack_source devin)" = none ] || fail "devin must have no ack source"
  [ "$(fm_control_exit_command devin)" = /exit ] || fail "devin must exit on /exit"
  [ "$(fm_control_harness_wiring_paths devin /wt /state t1)" = /wt/.devin/config.local.json ] \
    || fail "devin's retired wiring must be its worktree hooks file"
  pass "fm-control-lib: devin is Escape twice, a delayed closing Escape, /exit, crewmate/scout only"
}

test_devin_busy_record_is_trusted_only_for_devin() {
  local statedir gen got
  statedir="$TMP_ROOT/busy"; mkdir -p "$statedir"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$statedir" dv1) || fail "arm failed"
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" dv1 idle --gen "$gen" --source devin-hook --event stop \
    || fail "a devin-hook event must apply"
  got=$(fm_busy_classify tmux fake:win devin dv1 "$statedir")
  [ "$got" = "idle devin-hook" ] || fail "a devin-hook idle record must classify idle, got '$got'"
  got=$(fm_busy_classify tmux fake:win claude dv1 "$statedir")
  [ "$got" = "unknown source-mismatch" ] || fail "claude must never trust a devin-hook record, got '$got'"
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" dv1 idle --gen "$gen" --source claude-hook --event stop \
    || fail "apply failed"
  got=$(fm_busy_classify tmux fake:win devin dv1 "$statedir")
  [ "$got" = "unknown source-mismatch" ] || fail "devin must never trust a claude-hook record, got '$got'"
  pass "fm-busy-lib: the devin-hook source classifies devin and only devin"
}

test_devin_prefixed_raw_commands_are_not_devin() {
  local statedir gen got raw
  for raw in devin-beta devinfo; do
    if fm_control_harness_family "$raw" >/dev/null; then
      fail "raw harness '$raw' must not get devin control mechanics"
    fi
  done
  statedir="$TMP_ROOT/prefix-busy"; mkdir -p "$statedir"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$statedir" dvprefix) || fail "arm failed"
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" dvprefix idle --gen "$gen" --source devin-hook --event stop \
    || fail "a devin-hook event must apply"
  for raw in devin-beta devinfo; do
    got=$(fm_busy_classify tmux fake:win "$raw" dvprefix "$statedir")
    [ "$got" = "unknown source-mismatch" ] \
      || fail "raw harness '$raw' must not trust devin-hook, got '$got'"
  done
  pass "fm-control-lib/fm-busy-lib: devin-prefixed raw commands do not inherit devin"
}

test_devin_delivery_signature_is_harness_scoped() {
  printf '⠀⠚ Thinking · 4s (esc twice to interrupt)\n' | fm_busy_lines_match devin \
    || fail "devin's busy row must match its own signature"
  printf '⠤⠄ Running tools · 12s (esc again to interrupt)\n' | fm_busy_lines_match devin \
    || fail "devin's armed-interrupt row must match its own signature"
  printf '⠤⠄ Running tools · 12s (esc again to interrupt)\n' | fm_busy_lines_match \
    || fail "the harness-less union must acknowledge a devin busy row"
  printf 'Thinking… (4s · esc to interrupt)\n' | fm_busy_lines_match devin \
    && fail "devin must never borrow claude's token" || true
  printf '⠀⠚ Thinking · 4s (esc twice to interrupt)\n' | fm_busy_lines_match claude \
    && fail "claude must never borrow devin's token" || true
  printf '❭ Ask Devin to build features, fix bugs, or work on your code\n' | fm_busy_lines_match devin \
    && fail "devin's idle composer must not read busy" || true
  pass "fm-composer-lib: devin delivery signatures never cross harnesses"
}

# The composer region of a real devin 3000.10.31 pane (tmux capture-pane -e),
# preceded by transcript rows; the titled rule above the composer is what makes
# the solid rule below it a pair rather than a lone separator.
devin_screen() {  # idle|typed
  local rule body
  rule=$(printf '─%.0s' $(seq 1 74))
  if [ "$1" = typed ]; then
    body=$'\e[39m❭ typed words'
  elif [ "$1" = idle_plain ]; then
    body='❭ Ask Devin to build features, fix bugs, or work on your code'
  else
    body=$'\e[39m❭ \e[38;2;124;124;124mAsk Devin to build features, fix bugs, or work on your code\e[39m'
  fi
  printf '%s\n' '' $'\e[38;2;255;255;255m\e[48;2;42;42;42m❭\e[39m reply with the word ok only' '' ' ok' ''
  printf '\e[38;2;68;68;68m%s\e[39m \e[38;2;220;220;170m(bypass permissions on)\e[39m \e[38;2;68;68;68m─\n' "$rule"
  printf '%s\n' "$body"
  printf '\e[38;2;68;68;68m%s──────────────────────────\n' "$rule"
  printf '\e[39mGPT-5.6 Luna Low Thinking                         \e[38;2;124;124;124mContext: 13k / 1.0M tokens (1%%)\n'
  printf '%s\n' '' ''
}

test_devin_composer_reads_empty_and_pending() {
  local idle typed live_idle got plain_idle
  idle=$(devin_screen idle)
  typed=$(devin_screen typed)
  live_idle=$(devin_screen idle_plain)
  got=$(fm_composer_classify_screen $'styled=1\ncursor=1' "$idle" 6)
  [ "$got" = empty ] || fail "an idle devin composer under the cursor must read empty, got '$got'"
  got=$(fm_composer_classify_screen $'styled=1\ncursor=1' "$live_idle" 6)
  [ "$got" = empty ] || fail "a live uncolored idle devin composer under the cursor must read empty, got '$got'"
  got=$(fm_composer_classify_screen $'styled=1\ncursor=1' "$typed" 6)
  [ "$got" = pending ] || fail "typed devin input under the cursor must read pending, got '$got'"
  got=$(fm_composer_classify_screen styled=1 "$idle")
  [ "$got" = empty ] || fail "a cursorless styled read of an idle devin composer must read empty, got '$got'"
  got=$(fm_composer_classify_screen styled=1 "$typed")
  [ "$got" = pending ] || fail "a cursorless styled read of typed devin input must read pending, got '$got'"
  got=$(fm_composer_classify_screen $'styled=1\nidentity=1' "$idle" '' $'devin\tidle')
  [ "$got" = empty ] || fail "an identity-capable read of an idle devin composer must read empty, got '$got'"
  # Divergence: without the titled rule the solid rule below the glyph row is a
  # lone separator, which stays unknown - so the titled rule is load-bearing.
  plain_idle=$(printf '%s\n' "$idle" | sed 's/(bypass permissions on)/bypass-permissions-on/')
  got=$(fm_composer_classify_screen styled=1 "$plain_idle")
  [ "$got" = unknown ] || fail "an untitled rule must not open the pair, got '$got'"
  # An unstyled read cannot tell devin's placeholder from typed text.
  got=$(fm_composer_classify_screen styled=0 "$(printf '%s\n' "$idle" | fm_composer_strip_ansi)")
  [ "$got" = unknown ] || fail "an unstyled devin placeholder must stay unknown, got '$got'"
  pass "fm-composer-lib: devin's composer reads empty or pending on styled reads"
}

test_devin_tmux_names_the_native_binary_an_agent() {
  local got
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-backend.sh"
  fm_backend_source tmux || fail "fm_backend_source tmux failed"
  got=$(fm_agent_process_classify_name devin)
  [ "$got" = agent ] || fail "tmux liveness must read the devin binary as an agent, got '$got'"
  got=$(fm_agent_process_classify_name /home/u/.local/share/devin/cli/_versions/3000.10.31/bin/devin)
  [ "$got" = agent ] || fail "tmux liveness must read devin's install path as an agent, got '$got'"
  got=$(fm_agent_process_classify_name devinfo)
  [ "$got" = other ] || fail "tmux liveness must not read devinfo as an agent, got '$got'"
  pass "bin/fm-agent-process-lib.sh: devin is an agent, fragments are not"
}

make_devin_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "$FM_FAKE_PANE_PATH"; exit 0 ;;
  *"#{cursor_y}"*) printf '1\n'; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  send-keys)
    prev=
    for arg in "$@"; do
      if [ "$prev" = -l ]; then
        case "$arg" in *--permission-mode*) printf '%s\n' "$arg" >> "$FM_FAKE_LAUNCH_LOG" ;; esac
        break
      fi
      prev=$arg
    done
    exit 0
    ;;
  capture-pane) printf '❭ \n'; exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  cat > "$fakebin/devin" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = models ]; then
  if [ "${FM_FAKE_DEVIN_MODELS_FAIL:-0}" = 1 ]; then exit 3; fi
  cat <<'JSON'
{"families":[{"family_label":"Claude Opus 5","family_uid":"claude-opus-5","slug":"claude-opus-5","aliases":["opus"],
"variants":[{"model_uid":"claude-opus-5-high"},{"model_uid":"claude-opus-5-low"}]},
{"family_label":"GPT-5.6 Luna","family_uid":"gpt-5.6-luna","slug":"gpt-5.6-luna","aliases":[],
"variants":[{"model_uid":"gpt-5-6-luna-low"}]}]}
JSON
  exit 0
fi
echo "fake devin must never execute" >&2
exit 9
SH
  chmod +x "$fakebin/devin"
  fm_fake_exit0 "$fakebin" treehouse gh-axi gh
  printf '%s\n' "$fakebin"
}

make_devin_spawn_case() {  # <name> <id> -> "<case>|<home>|<proj>|<wt>|<fakebin>"
  local name=$1 id=$2 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_devin_fakebin "$case_dir/fake")
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
  cat > "$home/data/$id/brief.md" <<'EOF'
# Task
## Captain's intent
Exercise Devin dispatch.

## Firstmate spec
Verify launch and busy wiring.
EOF
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  : > "$case_dir/launch.log"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin"
}

read_devin_spawn_record() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR <<EOF
$1
EOF
}

# jq parses the model listing inside the spawn, so carry the directory the
# invoking environment resolves it from, the fm-kimi-harness shape.
JQ_BIN=$(command -v jq) || fail "test needs jq"
BASE_PATH=${FM_TEST_BASE_PATH:-$(dirname "$JQ_BIN"):/usr/bin:/bin:/usr/sbin:/sbin}

run_devin_spawn() {
  local case_dir=$1 home=$2 proj=$3 wt=$4 fakebin=$5 id=$6
  shift 6
  HOME="$home" FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_FAKE_LAUNCH_LOG="$case_dir/launch.log" \
    FM_FAKE_DEVIN_MODELS_FAIL="${FM_FAKE_DEVIN_MODELS_FAIL:-0}" \
    FM_DEVIN_MODELS_TIMEOUT=5 \
    PATH="$fakebin:$BASE_PATH" \
    "$SPAWN" "$id" "$proj" --harness devin --mode no-mistakes --yolo off "$@" 2>&1
}

hook_command() {  # <hooks-file> <event>
  jq -r --arg e "$2" '.hooks[$e][0].hooks[0].command' "$1"
}

test_devin_launch_carries_brief_model_autonomy_and_trust_skip() {
  local id rec out rc launch meta
  id="devin-launch-d1-$$"
  rec=$(make_devin_spawn_case launch "$id")
  read_devin_spawn_record "$rec"
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model claude-opus-5-high --effort xhigh)
  rc=$?
  expect_code 0 "$rc" "devin spawn with a listed model should succeed: $out"
  launch=$(cat "$CASE_DIR/launch.log")
  assert_contains "$launch" "$FAKEBIN_DIR/devin" "devin launch did not pin the resolved absolute binary"
  assert_contains "$launch" "--permission-mode dangerous" "devin launch omitted unattended autonomy"
  assert_contains "$launch" "--respect-workspace-trust false" "devin launch did not skip the per-directory trust gate"
  assert_contains "$launch" "--model 'claude-opus-5-high' -- " "devin launch did not carry the model before the prompt separator"
  assert_contains "$launch" "encode launch-brief" "devin launch did not carry the encoded brief"
  assert_contains "$launch" "env -u CLAUDECODE" "devin launch did not clear the inherited launcher marker"
  assert_contains "$launch" "-u WAYLAND_DISPLAY" "devin launch kept the Wayland display its idle clipboard access breaks on"
  assert_not_contains "$launch" "--effort" "devin launch passed an effort flag devin does not have"
  assert_not_contains "$launch" "__DEVINBIN__" "devin launch left its binary placeholder unsubstituted"
  meta="$HOME_DIR/state/$id.meta"
  assert_grep 'harness=devin' "$meta" "devin meta did not record its harness"
  assert_grep 'model=claude-opus-5-high' "$meta" "devin meta did not record its model"
  assert_grep 'effort=xhigh' "$meta" "devin meta did not retain the effort axis"
  pass "fm-spawn: devin launch carries brief, model, autonomy, and trust skip, omitting effort"
}

test_devin_hooks_are_the_three_verified_events_and_work() {
  local id rec out rc hooks statedir got
  id="devin-hooks-d2-$$"
  rec=$(make_devin_spawn_case hooks "$id")
  read_devin_spawn_record "$rec"
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" --model opus)
  rc=$?
  expect_code 0 "$rc" "devin spawn should succeed: $out"
  hooks="$WT_DIR/.devin/config.local.json"
  statedir="$HOME_DIR/state"
  assert_present "$hooks" "devin spawn did not write its hooks file"
  got=$(jq -r '.hooks | keys | sort | join(",")' "$hooks") || fail "devin hooks file is not valid JSON"
  [ "$got" = "SessionEnd,Stop,UserPromptSubmit" ] \
    || fail "devin hooks must name exactly its three verified events, got '$got'"
  [ -z "$(git -C "$WT_DIR" status --porcelain)" ] || fail "devin hooks file is visible to git"
  got=$(fm_busy_classify tmux fake:win devin "$id" "$statedir")
  [ "$got" = "busy fm-spawn" ] || fail "the launch brief must seed a busy record, got '$got'"
  sh -c "$(hook_command "$hooks" Stop)" </dev/null || fail "the Stop hook command failed"
  got=$(fm_busy_classify tmux fake:win devin "$id" "$statedir")
  [ "$got" = "idle devin-hook" ] || fail "the Stop hook must record idle, got '$got'"
  assert_present "$statedir/$id.turn-ended" "the Stop hook must touch the turn-ended notification"
  sh -c "$(hook_command "$hooks" UserPromptSubmit)" </dev/null || fail "the submit hook command failed"
  got=$(fm_busy_classify tmux fake:win devin "$id" "$statedir")
  [ "$got" = "busy devin-hook" ] || fail "the UserPromptSubmit hook must record busy, got '$got'"
  sh -c "$(hook_command "$hooks" SessionEnd)" </dev/null || fail "the SessionEnd hook command failed"
  got=$(fm_busy_classify tmux fake:win devin "$id" "$statedir")
  [ "$got" = "idle devin-hook" ] || fail "the SessionEnd hook must record idle, got '$got'"
  # A retired incarnation's hook must be refused without failing devin's hook.
  "$ROOT/bin/fm-busy-event.sh" arm "$statedir" "$id" >/dev/null || fail "re-arm failed"
  sh -c "$(hook_command "$hooks" UserPromptSubmit)" </dev/null || fail "a stale hook must still exit 0"
  got=$(fm_busy_classify tmux fake:win devin "$id" "$statedir")
  [ "$got" = "busy fm-spawn" ] || fail "a stale-gen hook must not change the record, got '$got'"
  pass "fm-spawn: devin hooks are the three verified events and drive the busy record"
}

test_devin_refuses_a_project_that_tracks_the_hooks_path() {
  local id rec out rc
  id="devin-tracked-d3-$$"
  rec=$(make_devin_spawn_case tracked "$id")
  read_devin_spawn_record "$rec"
  # Track the file on the project's default branch (and its origin), which is
  # what the spawn bases the task branch on.
  mkdir -p "$PROJ_DIR/.devin"
  printf '{"agent":{"model":"opus"}}\n' > "$PROJ_DIR/.devin/config.local.json"
  git -C "$PROJ_DIR" add .devin/config.local.json
  git -C "$PROJ_DIR" -c user.email=t@t -c user.name=t commit -qm 'track devin config'
  git -C "$PROJ_DIR" push -q origin HEAD 2>/dev/null || true
  git -C "$WT_DIR" reset -q --hard "$(git -C "$PROJ_DIR" rev-parse HEAD)"
  rc=0
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id") || rc=$?
  [ "$rc" -ne 0 ] || fail "a project tracking .devin/config.local.json must refuse the devin spawn: $out"
  assert_contains "$out" "tracks .devin/config.local.json" "tracked-path refusal lacked its concrete reason"
  [ "$(cat "$WT_DIR/.devin/config.local.json")" = '{"agent":{"model":"opus"}}' ] \
    || fail "the refused spawn overwrote the project's tracked file"
  pass "fm-spawn: devin refuses rather than overwriting a tracked .devin/config.local.json"
}

test_devin_unlisted_model_refuses_and_unreachable_listing_launches() {
  local id rec out rc
  id="devin-badmodel-d4-$$"
  rec=$(make_devin_spawn_case badmodel "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model claude-opus-5-medium) || rc=$?
  [ "$rc" -ne 0 ] || fail "an unlisted devin model must refuse the spawn"
  assert_contains "$out" "is not listed by 'devin models list'" "unlisted-model refusal lacked its reason"
  [ -s "$CASE_DIR/launch.log" ] && fail "an unlisted model still produced a launch command" || true

  id="devin-nolist-d5-$$"
  rec=$(make_devin_spawn_case nolist "$id")
  read_devin_spawn_record "$rec"
  out=$(FM_FAKE_DEVIN_MODELS_FAIL=1 run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" \
    "$FAKEBIN_DIR" "$id" --model claude-opus-5-medium)
  rc=$?
  expect_code 0 "$rc" "an unreachable listing must launch unvalidated: $out"
  assert_contains "$out" "launching with --model 'claude-opus-5-medium' unvalidated" \
    "an unreachable listing must say the model is unvalidated"
  pass "fm-spawn: devin refuses an unlisted model and launches past an unreachable listing"
}

test_devin_secondmate_and_missing_binary_are_refused() {
  local id rec out rc
  id="devin-secondmate-d6-$$"
  rec=$(make_devin_spawn_case secondmate-refuse "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(HOME="$HOME_DIR" FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_SPAWN_NO_GUARD=1 PATH="$FAKEBIN_DIR:$BASE_PATH" \
    "$SPAWN" "$id" --secondmate devin 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "a devin secondmate spawn should be refused"
  assert_contains "$out" "devin is a verified crewmate/scout adapter only" \
    "devin secondmate refusal lacked its concrete reason"

  id="devin-missing-d7-$$"
  rec=$(make_devin_spawn_case missing "$id")
  read_devin_spawn_record "$rec"
  rm "$FAKEBIN_DIR/devin"
  rc=0
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id") || rc=$?
  [ "$rc" -ne 0 ] || fail "a missing devin executable should refuse the spawn"
  assert_contains "$out" "devin executable not found on PATH" "missing devin diagnostic lacked its reason"
  pass "fm-spawn: devin refuses secondmates and a missing executable"
}

test_devin_ancestry_detects_the_tui_and_its_tool_host
test_devin_ancestry_rejects_unrelated_mentions
test_devin_outranks_inherited_claudecode_and_claims_no_marker
test_devin_control_mechanics_are_the_verified_ones
test_devin_busy_record_is_trusted_only_for_devin
test_devin_prefixed_raw_commands_are_not_devin
test_devin_delivery_signature_is_harness_scoped
test_devin_composer_reads_empty_and_pending
test_devin_tmux_names_the_native_binary_an_agent
test_devin_launch_carries_brief_model_autonomy_and_trust_skip
test_devin_hooks_are_the_three_verified_events_and_work
test_devin_refuses_a_project_that_tracks_the_hooks_path
test_devin_unlisted_model_refuses_and_unreachable_listing_launches
test_devin_secondmate_and_missing_binary_are_refused
