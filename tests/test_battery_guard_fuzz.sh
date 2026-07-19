#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-battery-fuzz.XXXXXX)"
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
PMSET_STATE_DIR="$TEST_ROOT/pmset"
PMSET_LOG="$TEST_ROOT/pmset.log"
BATT_FILE="$TEST_ROOT/pmset-batt.txt"
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$STUB_BIN" "$STATE_ROOT" "$PMSET_STATE_DIR" "$TEST_HOME/.config/awake"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-n" ]; then
    shift
fi
printf 'sudo %s\n' "$*" >> "${AWAKE_TEST_PMSET_LOG:?}"
exec "$@"
EOF

cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF

cat > "$STUB_BIN/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/caffeinate" <<'EOF'
#!/bin/bash
sleep 30
EOF

cat > "$STUB_BIN/osascript" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/pmset" <<'EOF'
#!/bin/bash
set -euo pipefail
state_dir="${AWAKE_TEST_PMSET_STATE_DIR:?}"

read_key() {
    local key="$1"
    cat "$state_dir/$key" 2>/dev/null || echo 0
}

if [ "${1:-}" = "-g" ] && [ "${2:-}" = "batt" ]; then
    cat "${AWAKE_TEST_BATT_FILE:?}"
    exit 0
fi

if [ "${1:-}" = "-g" ] && [ "${2:-}" = "custom" ]; then
    echo "Battery Power:"
    echo " sleep 10"
    echo " displaysleep 5"
    echo " standby 1"
    echo " hibernatemode 3"
    echo "AC Power:"
    echo " sleep 10"
    echo " displaysleep 5"
    echo " standby 1"
    echo " hibernatemode 3"
    exit 0
fi

if [ "${1:-}" = "-g" ]; then
    echo "System-wide power settings:"
    echo "Currently in use:"
    echo " disablesleep $(read_key disablesleep)"
    exit 0
fi

if [ "${1:-}" = "displaysleepnow" ]; then
    echo 1 > "$state_dir/display-slept"
    exit 0
fi

if [ "${1:-}" = "sleepnow" ]; then
    echo 1 > "$state_dir/pmset-slept"
    exit 0
fi

scope="${1:-}"
shift || true
while [ "$#" -gt 0 ]; do
    key="$1"
    value="${2:-}"
    shift 2 || true
    if [ "$key" = "disablesleep" ]; then
        echo "$value" > "$state_dir/disablesleep"
    fi
    case "$scope" in
        -a)
            echo "$value" > "$state_dir/battery.$key"
            echo "$value" > "$state_dir/ac.$key"
            ;;
        -b)
            echo "$value" > "$state_dir/battery.$key"
            ;;
        -c)
            echo "$value" > "$state_dir/ac.$key"
            ;;
    esac
done
EOF

chmod +x "$STUB_BIN"/*

export HOME="$TEST_HOME"
export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export AWAKE_TEST_PMSET_LOG="$PMSET_LOG"
export AWAKE_TEST_PMSET_STATE_DIR="$PMSET_STATE_DIR"
export AWAKE_TEST_BATT_FILE="$BATT_FILE"

AWAKE_LIB="$TEST_ROOT/awake-lib.sh"
sed '/^# --- Main ---/,$d' "$REPO_DIR/awake" > "$AWAKE_LIB"
# shellcheck source=/dev/null
source "$AWAKE_LIB"

log() { :; }
notify() { :; }
active_daemon_pid() { return 1; }

setup_state() {
    local dir="$STATE_ROOT/case"
    rm -rf "$dir"
    mkdir -p "$dir"
    PID_FILE="$dir/awake.pid"
    STATE_FILE="$dir/awake-state"
    LAST_ACTIVE_FILE="$dir/awake-last-active"
    CAFFEINE_PID_FILE="$dir/awake-caffeinate.pid"
    FOR_PID_FILE="$dir/awake-for.pid"
    FOR_END_FILE="$dir/awake-for-end"
    FOR_TOKEN_FILE="$dir/awake-for-token"
    DISPLAY_SLEEP_FILE="$dir/awake-display-sleep"
    LEASES_DIR="$dir/leases"
    RULES_DIR="$dir/rules.d"
    BASELINE_FILE="$dir/power-baseline.json"
    MODE_FILE="$dir/default-mode"
    WHY_FILE="$dir/awake-why"
    BATTERY_GUARD_FILE="$dir/awake-battery-guard"
    DAEMON_LOCK_DIR="$dir/daemon-lock"
    DAEMON_OWNER_FILE="$DAEMON_LOCK_DIR/pid"
    mkdir -p "$LEASES_DIR" "$RULES_DIR"
    echo "agent-safe" > "$MODE_FILE"
    : > "$PMSET_LOG"
    echo 0 > "$PMSET_STATE_DIR/disablesleep"
    rm -f "$PMSET_STATE_DIR/pmset-slept" "$PMSET_STATE_DIR/display-slept"
    rm -f "$BATTERY_GUARD_FILE"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    if [ "$expected" != "$actual" ]; then
        echo "expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

write_batt_case() {
    local pct="$1"
    local source="$2"
    local format="$3"
    local state="discharging"
    local source_label="Battery Power"
    if [ "$source" = "ac" ]; then
        state="charging"
        source_label="AC Power"
    fi

    case "$format" in
        split)
            printf "Now drawing from '%s'\n -InternalBattery-0 (id=1234567)\t%s%%; %s; 2:00 remaining\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        same-line)
            printf "Now drawing from '%s' -InternalBattery-0 %s%%; %s; 2:00 remaining\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        spaces)
            printf "Now drawing from '%s'\n    -InternalBattery-0      %s%%;   %s; no estimate\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        parenthesized)
            printf "Now drawing from '%s'\n -InternalBattery-0 (id=1234567) (%s%%); %s; 0:09 remaining\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        summary-percent)
            printf "Now drawing from '%s' estimate 88%%\n -InternalBattery-0 (id=1234567)\t%s%%; %s; 2:00 remaining\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        semicolon-tight)
            printf "Now drawing from '%s'\n -InternalBattery-0;%s%%;%s;2:00 remaining\n" "$source_label" "$pct" "$state" > "$BATT_FILE"
            ;;
        multiple-batteries)
            printf "Now drawing from '%s'\n -InternalBattery-0 (id=1)\t%s%%; %s; 2:00 remaining\n -InternalBattery-1 (id=2)\t99%%; %s; 9:00 remaining\n" "$source_label" "$pct" "$state" "$state" > "$BATT_FILE"
            ;;
        no-battery)
            printf "Now drawing from 'AC Power'\n" > "$BATT_FILE"
            ;;
        *)
            echo "unknown battery format: $format" >&2
            exit 1
            ;;
    esac
}

formats=(split same-line spaces parenthesized summary-percent semicolon-tight multiple-batteries)
for pct in 0 1 4 5 6 15 16 50 99 100; do
    for format in "${formats[@]}"; do
        setup_state
        write_batt_case "$pct" battery "$format"
        assert_equals "$pct" "$(get_battery_pct)"
    done
done

setup_state
write_batt_case 0 ac no-battery
assert_equals "" "$(get_battery_pct)"

setup_state
write_batt_case 4 battery split
enforce_battery_guard
grep -q "pmset sleepnow" "$PMSET_LOG"
[ -f "$PMSET_STATE_DIR/pmset-slept" ]

setup_state
write_batt_case 5 battery split
enforce_battery_guard
if ! grep -q "pmset sleepnow" "$PMSET_LOG"; then
    echo "battery guard did not force sleep at exactly BATTERY_CRITICAL" >&2
    exit 1
fi
if [ ! -f "$PMSET_STATE_DIR/pmset-slept" ]; then
    echo "battery guard did not record sleep at exactly BATTERY_CRITICAL" >&2
    exit 1
fi

setup_state
write_batt_case 4 ac split
if enforce_battery_guard; then
    echo "battery guard should not trigger while charging" >&2
    exit 1
fi
if grep -q "pmset sleepnow" "$PMSET_LOG"; then
    echo "battery guard force-slept while charging" >&2
    exit 1
fi

echo "battery guard fuzz tests passed"
