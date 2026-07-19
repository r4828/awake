#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-manual-monitor-test.XXXXXX)"
MONITOR_LOG="$TEST_ROOT/monitor.log"

cleanup_test() {
    rm -rf "$TEST_ROOT"
}
trap cleanup_test EXIT

AWAKE_LIB="$TEST_ROOT/awake-lib.sh"
sed '/^# --- Main ---/,$d' "$REPO_DIR/awake" > "$AWAKE_LIB"
# shellcheck source=/dev/null
source "$AWAKE_LIB"

LEASES_DIR="$TEST_ROOT/leases"
RULES_DIR="$TEST_ROOT/rules"
MODE_FILE="$TEST_ROOT/default-mode"
PID_FILE="$TEST_ROOT/awake.pid"
DAEMON_LOCK_DIR="$TEST_ROOT/daemon-lock"
DAEMON_OWNER_FILE="$DAEMON_LOCK_DIR/pid"
mkdir -p "$LEASES_DIR" "$RULES_DIR"
printf 'presenting\n' > "$MODE_FILE"

reconcile_effective_state() { return 0; }
active_daemon_pid() { return 1; }
cmd_daemon_start() { printf '%s\n' "$*" >> "$MONITOR_LOG"; }

AWAKE_LEASE_MONITOR_ENABLED=1
activate_nosleep
grep -Fxq -- '--bg --lease-monitor' "$MONITOR_LOG"

: > "$MONITOR_LOG"
active_daemon_pid() { printf '12345\n'; }
ensure_active_lease_monitor
[ ! -s "$MONITOR_LOG" ]

: > "$MONITOR_LOG"
active_daemon_pid() { return 1; }
lease_remove "manual-toggle"
ensure_active_lease_monitor
[ ! -s "$MONITOR_LOG" ]

daemon_cleanup() { :; }
cleanup() { cleanup_test; }
recover_power_state_on_launch() { :; }
acquire_daemon_lock() { return 0; }
log() { :; }

battery_checks=0
enforce_battery_guard() {
    battery_checks=$((battery_checks + 1))
    return 1
}
lease_count() { printf '0\n'; }
cmd_daemon --lease-monitor
[ "$battery_checks" -eq 0 ]

LEASE_PROBE_FILE="$TEST_ROOT/lease-probe"
printf '0\n' > "$LEASE_PROBE_FILE"
lease_count() {
    local checks
    checks="$(cat "$LEASE_PROBE_FILE")"
    checks=$((checks + 1))
    printf '%s\n' "$checks" > "$LEASE_PROBE_FILE"
    if [ "$checks" -eq 1 ]; then
        printf '1\n'
    else
        printf '0\n'
    fi
}
reconcile_effective_state() { :; }
sleep() { :; }
cmd_daemon --lease-monitor
[ "$battery_checks" -eq 1 ]

echo "manual battery monitor tests passed"
