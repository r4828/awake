#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-runtime-service-test.XXXXXX)"

cleanup_test() {
    [ -n "${RUNTIME_PID:-}" ] && kill "$RUNTIME_PID" 2>/dev/null || true
    rm -rf "$TEST_ROOT"
}
trap cleanup_test EXIT

AWAKE_LIB="$TEST_ROOT/awake-lib.sh"
sed '/^# --- Main ---/,$d' "$REPO_DIR/awake" > "$AWAKE_LIB"
# shellcheck source=/dev/null
source "$AWAKE_LIB"

RUNTIME_PATH="$TEST_ROOT/LaunchAgents/com.awake.runtime.plist"
RUNTIME_READY_FILE="$TEST_ROOT/runtime-ready"
RUNTIME_HEARTBEAT_FILE="$TEST_ROOT/runtime-heartbeat"
PID_FILE="$TEST_ROOT/awake.pid"
LOCAL_BIN_DIR="$TEST_ROOT/bin"
POLL_INTERVAL=15
mkdir -p "$LOCAL_BIN_DIR"
printf '#!/bin/bash\nwhile true; do sleep 30; done # _runtime\n' > "$LOCAL_BIN_DIR/awake"
chmod +x "$LOCAL_BIN_DIR/awake"

# The command line deliberately matches the production runtime predicate.
"$LOCAL_BIN_DIR/awake" _runtime &
RUNTIME_PID=$!
printf '%s\n' "$RUNTIME_PID" > "$RUNTIME_READY_FILE"
printf '%s\n' "$(now_epoch)" > "$RUNTIME_HEARTBEAT_FILE"
runtime_is_healthy
ensure_runtime_ready

printf '%s\n' "$(( $(now_epoch) - 46 ))" > "$RUNTIME_HEARTBEAT_FILE"
if runtime_is_healthy; then
    echo "stale runtime heartbeat was accepted" >&2
    exit 1
fi
if ensure_runtime_ready; then
    echo "missing runtime unexpectedly passed the fast readiness check" >&2
    exit 1
fi

printf '%s\n' "$(now_epoch)" > "$RUNTIME_HEARTBEAT_FILE"
printf '999999\n' > "$RUNTIME_READY_FILE"
if runtime_is_healthy; then
    echo "dead runtime pid was accepted" >&2
    exit 1
fi

printf '%s\n' "$RUNTIME_PID" > "$RUNTIME_READY_FILE"
write_runtime_agent
grep -Fq '<string>com.awake.runtime</string>' "$RUNTIME_PATH"
grep -Fq '<string>_runtime</string>' "$RUNTIME_PATH"
grep -Fq '<key>RunAtLoad</key>' "$RUNTIME_PATH"
grep -Fq '<key>KeepAlive</key>' "$RUNTIME_PATH"
if grep -Fq '_lease-monitor' "$RUNTIME_PATH"; then
    echo "runtime plist still contains the legacy monitor entry point" >&2
    exit 1
fi

# The normal action path must never invoke launchctl or rewrite the plist.
PLIST_HASH="$(shasum -a 256 "$RUNTIME_PATH" | awk '{print $1}')"
launchctl() {
    echo "launchctl must not run from ensure_runtime_ready" >&2
    return 99
}
ensure_runtime_ready
[ "$PLIST_HASH" = "$(shasum -a 256 "$RUNTIME_PATH" | awk '{print $1}')" ]

echo "persistent runtime service tests passed"
