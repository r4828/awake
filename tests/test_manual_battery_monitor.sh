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
LEASE_MONITOR_READY_FILE="$TEST_ROOT/lease-monitor-ready"
LEASE_MONITOR_HEARTBEAT_FILE="$TEST_ROOT/lease-monitor-heartbeat"
mkdir -p "$LEASES_DIR" "$RULES_DIR"
printf 'presenting\n' > "$MODE_FILE"

lease_count() { printf '1\n'; }
lease_monitor_is_healthy() { return 1; }
cmd_lease_monitor_start() { printf 'start\n' >> "$MONITOR_LOG"; }
ensure_active_lease_monitor
grep -Fxq 'start' "$MONITOR_LOG"

: > "$MONITOR_LOG"
lease_monitor_is_healthy() { return 0; }
ensure_active_lease_monitor
[ ! -s "$MONITOR_LOG" ]

: > "$MONITOR_LOG"
lease_count() { printf '0\n'; }
ensure_active_lease_monitor
[ ! -s "$MONITOR_LOG" ]

lease_count() { printf '1\n'; }
lease_monitor_is_healthy() { return 1; }
cmd_lease_monitor_start() { return 1; }
if ensure_active_lease_monitor; then
    echo "monitor startup unexpectedly succeeded" >&2
    exit 1
fi

cleanup() { cleanup_test; }
log() { :; }
restore_normal_sleep_settings() { :; }
enforce_battery_guard() { printf 'guard\n' >> "$MONITOR_LOG"; return 1; }
POLL_INTERVAL=1

: > "$MONITOR_LOG"
lease_count() { printf '0\n'; }
(cmd_lease_monitor)
[ ! -e "$LEASE_MONITOR_READY_FILE" ]
[ ! -e "$LEASE_MONITOR_HEARTBEAT_FILE" ]
[ ! -s "$MONITOR_LOG" ]

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
: > "$MONITOR_LOG"
(cmd_lease_monitor)
grep -Fxq 'guard' "$MONITOR_LOG"
[ ! -e "$LEASE_MONITOR_READY_FILE" ]
[ ! -e "$LEASE_MONITOR_HEARTBEAT_FILE" ]

sudo() { return 0; }
reconcile_effective_state() { return 1; }
restore_sleep_after_monitor_failure() { printf 'restored\n' >> "$MONITOR_LOG"; }
: > "$MONITOR_LOG"
if cmd_run_command true; then
    echo "run command unexpectedly started without a monitor" >&2
    exit 1
fi
[ ! -d "$LEASES_DIR/run-command" ]
grep -Fxq 'restored' "$MONITOR_LOG"

lease_create_or_update "run-command" "command" "presenting" "Stale command" 85 "" "test" "999999"
cleanup_invalid_leases
[ ! -d "$LEASES_DIR/run-command" ]

echo "manual battery monitor tests passed"
