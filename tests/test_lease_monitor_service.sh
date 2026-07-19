#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-lease-monitor-service-test.XXXXXX)"

cleanup() {
    [ -n "${MONITOR_PID:-}" ] && kill "$MONITOR_PID" 2>/dev/null || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

AWAKE_LIB="$TEST_ROOT/awake-lib.sh"
sed '/^# --- Main ---/,$d' "$REPO_DIR/awake" > "$AWAKE_LIB"
# shellcheck source=/dev/null
source "$AWAKE_LIB"

LEASE_MONITOR_PATH="$TEST_ROOT/LaunchAgents/com.awake.lease-monitor.plist"
LEASE_MONITOR_READY_FILE="$TEST_ROOT/lease-monitor-ready"
LEASE_MONITOR_HEARTBEAT_FILE="$TEST_ROOT/lease-monitor-heartbeat"
LOCAL_BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$LOCAL_BIN_DIR"
printf '#!/bin/bash\n' > "$LOCAL_BIN_DIR/awake"
printf '# _lease-monitor\n' >> "$LOCAL_BIN_DIR/awake"
chmod +x "$LOCAL_BIN_DIR/awake"

# The command line deliberately matches the production monitor predicate.
bash -c 'exec -a "awake _lease-monitor" sleep 30' &
MONITOR_PID=$!
printf '%s\n' "$MONITOR_PID" > "$LEASE_MONITOR_READY_FILE"
printf '%s 0\n' "$(now_epoch)" > "$LEASE_MONITOR_HEARTBEAT_FILE"
lease_monitor_is_healthy

LEASES_DIR="$TEST_ROOT/leases"
RULES_DIR="$TEST_ROOT/rules"
mkdir -p "$LEASES_DIR" "$RULES_DIR"
lease_create_or_update "manual-toggle" "manual" "presenting" "Monitor generation test" 100 "" "test"
[ "$(lease_generation)" = "1" ]
if lease_monitor_is_healthy "1"; then
    echo "monitor accepted a heartbeat from an older lease generation" >&2
    exit 1
fi
printf '%s 1\n' "$(now_epoch)" > "$LEASE_MONITOR_HEARTBEAT_FILE"
lease_monitor_is_healthy "1"

printf '%s 0\n' "$(( $(now_epoch) - 46 ))" > "$LEASE_MONITOR_HEARTBEAT_FILE"
if lease_monitor_is_healthy; then
    echo "stale heartbeat was accepted" >&2
    exit 1
fi

printf '%s 0\n' "$(now_epoch)" > "$LEASE_MONITOR_HEARTBEAT_FILE"
printf '999999\n' > "$LEASE_MONITOR_READY_FILE"
if lease_monitor_is_healthy; then
    echo "dead monitor pid was accepted" >&2
    exit 1
fi

printf '%s\n' "$MONITOR_PID" > "$LEASE_MONITOR_READY_FILE"
write_lease_monitor_agent
grep -Fq '<string>com.awake.lease-monitor</string>' "$LEASE_MONITOR_PATH"
grep -Fq '<string>_lease-monitor</string>' "$LEASE_MONITOR_PATH"
grep -Fq '<key>SuccessfulExit</key>' "$LEASE_MONITOR_PATH"

has_passwordless_pmset() { return 0; }
lease_monitor_loaded() { return 0; }
launchctl() {
    case "${1:-}" in
        kickstart)
            printf '%s\n' "$MONITOR_PID" > "$LEASE_MONITOR_READY_FILE"
            printf '%s 0\n' "$(now_epoch)" > "$LEASE_MONITOR_HEARTBEAT_FILE"
            ;;
    esac
}
cmd_lease_monitor_start

launchctl() { :; }
rm -f "$LEASE_MONITOR_READY_FILE" "$LEASE_MONITOR_HEARTBEAT_FILE"
sleep() { :; }
if cmd_lease_monitor_start; then
    echo "monitor startup accepted a missing readiness heartbeat" >&2
    exit 1
fi

lease_count() { printf '1\n'; }
if (lease_monitor_signal_exit); then
    echo "monitor TERM handler exited successfully while a lease was active" >&2
    exit 1
fi
lease_count() { printf '0\n'; }
(lease_monitor_signal_exit)

echo "lease monitor service tests passed"
