# fm-home-summary-refresh-lib.sh - fire-and-forget home-summary republication helpers.
#
# Usage: . bin/fm-home-summary-refresh-lib.sh
#
# fm_home_summary_refresh_on_backlog_write_detached republishes state/home-summary.json
# for the caller's FM_HOME without waiting. Concurrent triggers serialize on the home's
# refresh lock inside bin/fm-home-summary-refresh.sh.
fm_home_summary_refresh_on_backlog_write_detached() {
  local script_dir refresh_script
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  refresh_script="$script_dir/fm-home-summary-refresh.sh"
  if [ "${FM_TEST_SEAM:-}" = 1 ] && [ -n "${FM_TEST_HOME_SUMMARY_REFRESH_BIN:-}" ]; then
    refresh_script=$FM_TEST_HOME_SUMMARY_REFRESH_BIN
  fi
  FM_HOME_SUMMARY_IF_IDLE=1 \
    FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$(cd "$script_dir/.." && pwd)}}" \
    "$refresh_script" --best-effort </dev/null >/dev/null 2>&1 &
  FM_HOME_SUMMARY_REFRESH_LAST_PID=$!
}
