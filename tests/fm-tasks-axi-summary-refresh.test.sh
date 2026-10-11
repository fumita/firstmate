#!/usr/bin/env bash
# Prove bin/fm-tasks-axi.sh republishes state/home-summary.json after successful
# backlog mutations without changing read-only calls or failed mutations.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WRAPPER="$ROOT/bin/fm-tasks-axi.sh"
REFRESH="$ROOT/bin/fm-home-summary-refresh.sh"
HOLD="$ROOT/bin/fm-captain-hold.sh"
TMP_ROOT=$(fm_test_tmproot fm-tasks-axi-summary-refresh)

unset TASKS_AXI_FILE TASKS_AXI_BACKEND FM_HOME FM_ROOT_OVERRIDE \
  FM_DATA_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE

command -v tasks-axi >/dev/null 2>&1 || { echo "skip: tasks-axi not found"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

empty_backlog() {
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$1"
}

make_home() {  # <name>
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/data" "$dir/state" "$dir/config" "$dir/bin"
  fm_test_tasks_toml "$dir/.tasks.toml"
  printf '%s\n' "$dir"
}

run_wrapper() {  # <home> <args...>
  local home=$1
  shift
  (
    cd "$home" && FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
      FM_TEST_SEAM=1 "$WRAPPER" "$@"
  )
}

run_hold() {  # <home> <args...>
  local home=$1
  shift
  FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_DATA_OVERRIDE="$home/data" \
    FM_STATE_OVERRIDE="$home/state" FM_CONFIG_OVERRIDE="$home/config" \
    FM_TEST_SEAM=1 "$HOLD" "$@"
}

wait_for_ledger_valid() {  # <home> <max-seconds>
  local home=$1 max=$2 i=0
  while [ "$i" -lt "$max" ]; do
    if jq -e '.valid == true and (.decisions_open | length) >= 1' \
      "$home/state/home-summary.json" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

test_stale_ledger_republishes_after_backlog_hold() {
  local home epoch_before
  home=$(make_home stale-ledger)
  printf '# fixture\n' > "$home/AGENTS.md"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$home" "$REFRESH" --best-effort >/dev/null \
    || fail "initial publication without backlog failed"
  jq -e '.invalidity.kind == "missing_backlog"' "$home/state/home-summary.json" >/dev/null \
    || fail "ledger did not record missing_backlog before backlog existed"
  empty_backlog "$home/data/backlog.md"
  run_wrapper "$home" add cap-hold-1 "Captain pick" --kind captain --repo firstmate >/dev/null \
    || fail "backlog add through the wrapper failed"
  run_hold "$home" hold cap-hold-1 --title "Captain pick" --reason "choose A or B" >/dev/null \
    || fail "captain hold failed"
  wait_for_ledger_valid "$home" 30 \
    || fail "ledger never became valid with an open captain hold: $(jq -c . "$home/state/home-summary.json" 2>/dev/null || true)"
  jq -e --arg id cap-hold-1 '
    .decisions_open[] | select(.id == $id) | .reason == "choose A or B"
  ' "$home/state/home-summary.json" >/dev/null \
    || fail "republished ledger did not include the new captain hold"
  pass "backlog mutation through the wrapper republished a stale ledger with the captain hold"
}

test_read_only_list_does_not_republish() {
  local home epoch_before epoch_after
  home=$(make_home read-only)
  empty_backlog "$home/data/backlog.md"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$home" "$REFRESH" --best-effort >/dev/null \
    || fail "baseline publication failed"
  epoch_before=$(jq -r '.generated_epoch' "$home/state/home-summary.json")
  run_wrapper "$home" list >/dev/null || fail "list failed"
  sleep 2
  epoch_after=$(jq -r '.generated_epoch' "$home/state/home-summary.json")
  assert_equals "$epoch_before" "$epoch_after" "read-only list changed generated_epoch"
  pass "read-only list did not republish the home summary"
}

test_failed_mutation_leaves_output_and_status() {
  local home out rc epoch_before epoch_after
  home=$(make_home failed-mutation)
  empty_backlog "$home/data/backlog.md"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$home" "$REFRESH" --best-effort >/dev/null
  epoch_before=$(jq -r '.generated_epoch' "$home/state/home-summary.json")
  out=$(run_wrapper "$home" start missing-task-id 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "start of a missing task should fail"
  sleep 2
  epoch_after=$(jq -r '.generated_epoch' "$home/state/home-summary.json")
  assert_equals "$epoch_before" "$epoch_after" "failed mutation republished the ledger"
  assert_contains "$out" "missing-task-id" "failed mutation stderr/stdout was unexpected"
  pass "failed backlog mutation left exit status, output, and ledger epoch unchanged"
}

test_slow_refresh_does_not_block_wrapper() {
  local home fake_refresh marker start end elapsed
  home=$(make_home slow-refresh)
  empty_backlog "$home/data/backlog.md"
  marker="$home/state/refresh-invocations"
  fake_refresh="$TMP_ROOT/fake-refresh.sh"
  cat > "$fake_refresh" <<SH
#!/usr/bin/env bash
printf '1\n' >> "$marker"
sleep 5
exec "$REFRESH" "\$@"
SH
  chmod +x "$fake_refresh"
  start=$(date +%s)
  FM_TEST_HOME_SUMMARY_REFRESH_BIN="$fake_refresh" \
    run_wrapper "$home" add slow-1 "queued work" >/dev/null || fail "add failed"
  end=$(date +%s)
  elapsed=$((end - start))
  [ "$elapsed" -lt 4 ] || fail "wrapper waited on home-summary refresh (${elapsed}s)"
  sleep 6
  [ -s "$marker" ] || fail "detached refresh never ran"
  pass "successful mutation returned before a slow detached refresh finished"
}

test_stale_ledger_republishes_after_backlog_hold
test_read_only_list_does_not_republish
test_failed_mutation_leaves_output_and_status
test_slow_refresh_does_not_block_wrapper
