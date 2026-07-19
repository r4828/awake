#!/bin/bash

set -euo pipefail


REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-status-test.XXXXXX)"
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
PMSET_STATE_DIR="$TEST_ROOT/pmset"
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$STUB_BIN" "$STATE_ROOT" "$PMSET_STATE_DIR" "$TEST_HOME/.claude" "$TEST_HOME/.codex" "$TEST_HOME/.local/bin" "$TEST_HOME/.config/awake"

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
exec "$@"
EOF

cat > "$STUB_BIN/pmset" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-g" ] && [ "${2:-}" = "batt" ]; then
    echo "Now drawing from 'AC Power'"
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
    echo " disablesleep 0"
    exit 0
fi
exit 0
EOF

cat > "$STUB_BIN/powermetrics" <<'EOF'
#!/bin/bash
exit 0
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

chmod +x "$STUB_BIN"/*

export HOME="$TEST_HOME"
export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export AWAKE_STATE_DIR="$STATE_ROOT"

printf '{\n  "hooks": {}\n}\n' > "$TEST_HOME/.claude/settings.json"
touch "$TEST_HOME/.codex/config.toml"
printf '#!/bin/bash\nexit 0\n' > "$TEST_HOME/.local/bin/awake-hook"
printf '#!/bin/bash\nexit 0\n' > "$TEST_HOME/.local/bin/awake-notify"
chmod +x "$TEST_HOME/.local/bin/awake-hook" "$TEST_HOME/.local/bin/awake-notify"

json="$("$REPO_DIR/awake" status --json)"
[[ "$json" == *'"defaultMode":"running"'* ]]
[[ "$json" == *'"leases":['* ]]
[[ "$json" == *'"rules":['* ]]
[[ "$json" == *'"warnings":['* ]]
[[ "$json" == *'"whyAwake":"Normal sleep. No active leases."'* ]]
[[ "$json" == *'"sleepControlConfigured":true'* ]]
[[ "$json" == *'"temperatureConfigured":true'* ]]

why_json="$("$REPO_DIR/awake" why --json)"
doctor_json="$("$REPO_DIR/awake" doctor --json)"
[[ "$why_json" == *'"whyAwake":"Normal sleep. No active leases."'* ]]
[[ "$doctor_json" == *'"warnings":['* ]]

"$REPO_DIR/awake" rules add process codex --mode running --reason 'Rule "quoted" value' >/dev/null
mkdir -p "$STATE_ROOT/awake-leases/manual-toggle"
printf 'manual-toggle' > "$STATE_ROOT/awake-leases/manual-toggle/id"
printf 'manual' > "$STATE_ROOT/awake-leases/manual-toggle/type"
printf 'presenting' > "$STATE_ROOT/awake-leases/manual-toggle/mode"
printf 'Manual awake session' > "$STATE_ROOT/awake-leases/manual-toggle/reason"
printf '100' > "$STATE_ROOT/awake-leases/manual-toggle/priority"
printf '1' > "$STATE_ROOT/awake-leases/manual-toggle/started_at"
printf 'cli' > "$STATE_ROOT/awake-leases/manual-toggle/source"
printf '' > "$STATE_ROOT/awake-leases/manual-toggle/expires_at"
printf '1' > "$STATE_ROOT/awake-leases/manual-toggle/ready"
json="$("$REPO_DIR/awake" status --json)"
[[ "$json" == *'"leaseCount":1'* ]]
[[ "$json" == *'"effectiveMode":"presenting"'* ]]
[[ "$json" == *'"effectiveResolvedMode":"presenting"'* ]]
[[ "$json" == *'"effectiveReason":"Manual awake session"'* ]]
[[ "$json" == *'Rule \"quoted\" value'* ]]

echo "status json tests passed"
