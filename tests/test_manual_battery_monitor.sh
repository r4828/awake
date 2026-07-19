#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-runtime-guard-test.XXXXXX)"
TEST_LOG="$TEST_ROOT/runtime.log"

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
AGENT_AUTO_FILE="$TEST_ROOT/agent-auto"
mkdir -p "$LEASES_DIR" "$RULES_DIR"
printf 'presenting\n' > "$MODE_FILE"

ensure_runtime_ready() { return 0; }
cleanup_invalid_leases() { :; }
sync_rule_leases() { :; }
agent_auto_enabled() { return 1; }
reconcile_effective_state() { printf 'reconciled\n' >> "$TEST_LOG"; }
RUNTIME_GRACE_START=0
runtime_reconcile_once
grep -Fxq 'reconciled' "$TEST_LOG"

# A failed runtime seam must fail closed and remove the command lease.
sudo() { return 0; }
reconcile_effective_state() { return 1; }
restore_sleep_after_runtime_failure() { printf 'restored\n' >> "$TEST_LOG"; }
if cmd_run_command true; then
    echo "run command unexpectedly started without a healthy runtime" >&2
    exit 1
fi
[ ! -d "$LEASES_DIR/run-command" ]
grep -Fxq 'restored' "$TEST_LOG"

lease_create_or_update "run-command" "command" "presenting" "Stale command" 85 "" "test" "999999"
cleanup_invalid_leases() {
    local dir="$LEASES_DIR/run-command"
    [ -d "$dir" ] && lease_remove "run-command"
}
cleanup_invalid_leases
[ ! -d "$LEASES_DIR/run-command" ]

echo "runtime guard tests passed"
