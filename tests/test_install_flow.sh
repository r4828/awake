#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-install-test.XXXXXX)"
STUB_BIN="$TEST_ROOT/bin"
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$STUB_BIN" "$TEST_HOME/.codex" "$TEST_HOME/.local/bin"

cleanup() {
    if [ -x "$STUB_BIN/launchctl" ]; then
        AWAKE_STATE_DIR="$TEST_ROOT/state" "$STUB_BIN/launchctl" bootout "gui/$(id -u)/com.awake.runtime" >/dev/null 2>&1 || true
    fi
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
exit 0
EOF

cat > "$STUB_BIN/powermetrics" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/xcode-select" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-p" ]; then
    echo /Applications/Xcode.app/Contents/Developer
    exit 0
fi
exit 0
EOF

cat > "$STUB_BIN/swiftc" <<'EOF'
#!/bin/bash
set -euo pipefail
out=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        out="$2"
        shift 2
    else
        shift
    fi
done
[ -n "$out" ] || exit 1
mkdir -p "$(dirname "$out")"
printf '#!/bin/bash\nexit 0\n' > "$out"
chmod +x "$out"
EOF

cat > "$STUB_BIN/codesign" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/iconutil" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/sips" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/osascript" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/open" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${AWAKE_TEST_OPEN_FAIL:-0}" != "1" ] || exit 1
touch "$AWAKE_STATE_DIR/ui-running"
count="$(cat "$AWAKE_STATE_DIR/ui-open-count" 2>/dev/null || echo 0)"
echo $(( count + 1 )) > "$AWAKE_STATE_DIR/ui-open-count"
exit 0
EOF

cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-x" ] && [ "${2:-}" = "AwakeUI" ] && [ -f "$AWAKE_STATE_DIR/ui-running" ]; then
    echo 42424
    exit 0
fi
exit 1
EOF

cat > "$STUB_BIN/pkill" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-TERM" ] && [ "${2:-}" = "-x" ] && [ "${3:-}" = "AwakeUI" ]; then
    rm -f "$AWAKE_STATE_DIR/ui-running"
fi
exit 0
EOF

cat > "$STUB_BIN/caffeinate" <<'EOF'
#!/bin/bash
sleep 600
EOF

cat > "$STUB_BIN/launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
state="$AWAKE_STATE_DIR/launchctl-loaded"
runtime_pid="$AWAKE_STATE_DIR/launchctl-runtime-pid"
case "${1:-}" in
    print)
        [ -f "$state" ]
        ;;
    bootstrap)
        touch "$state"
        nohup "$HOME/.local/bin/awake" _runtime </dev/null >>"$AWAKE_STATE_DIR/runtime.log" 2>&1 &
        printf '%s\n' "$!" > "$runtime_pid"
        ;;
    kickstart)
        ;;
    bootout)
        if [ -f "$runtime_pid" ]; then
            kill "$(cat "$runtime_pid")" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                kill -0 "$(cat "$runtime_pid")" 2>/dev/null || break
                sleep 0.05
            done
        fi
        rm -f "$state" "$runtime_pid"
        ;;
esac
EOF

cat > "$STUB_BIN/claude" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB_BIN/codex" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$STUB_BIN"/*

export HOME="$TEST_HOME"
export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export AWAKE_STATE_DIR="$TEST_ROOT/state"
export AWAKE_LAUNCHCTL_BIN="$STUB_BIN/launchctl"
mkdir -p "$AWAKE_STATE_DIR"

touch "$TEST_HOME/.codex/config.toml"

INSTALL_OUTPUT="$("$REPO_DIR/awake" install 2>&1)"

[ -f "$TEST_HOME/.claude/settings.json" ]
grep -Fq "awake-hook claude" "$TEST_HOME/.claude/settings.json"
grep -Fq 'notify = "'"$TEST_HOME"'/.local/bin/awake-notify"' "$TEST_HOME/.codex/config.toml"
[ -f "$TEST_HOME/.local/bin/awake-package.json" ]
[ -f "$TEST_HOME/.config/awake/install-metadata.json" ]
grep -Fq '"packageName": "awake-agent"' "$TEST_HOME/.config/awake/install-metadata.json"
[ -f "$TEST_HOME/.local/bin/Awake.app/Contents/Resources/bin/awake-package.json" ] || {
    printf '%s\n' "$INSTALL_OUTPUT" >&2
    find "$TEST_HOME/.local/bin/Awake.app" -maxdepth 5 -type f -print >&2 || true
    exit 1
}
[ -f "$TEST_HOME/.local/bin/Awake.app/Contents/Resources/ui/main.swift" ]
[ -f "$AWAKE_STATE_DIR/ui-running" ]
[ "$(cat "$AWAKE_STATE_DIR/ui-open-count")" = "1" ]
grep -Fq "Awake.app is running" <<<"$INSTALL_OUTPUT"

# Exercise the installed CLI as a user would. The five-minute timer must
# outlive the shell that invoked it, publish a 300-second deadline, keep the
# runtime and menu-bar app alive, and restore normal sleep when cancelled.
TIMER_START="$(date +%s)"
/bin/bash -c '"$1" for 5m >/dev/null' awake-test "$TEST_HOME/.local/bin/awake"
TIMER_END="$(cat "$AWAKE_STATE_DIR/awake-for-end")"
TIMER_DELTA=$(( TIMER_END - TIMER_START ))
[ "$TIMER_DELTA" -ge 298 ]
[ "$TIMER_DELTA" -le 302 ]
TIMER_PID="$(cat "$AWAKE_STATE_DIR/awake-for.pid")"
kill -0 "$TIMER_PID"
sleep 0.2
kill -0 "$TIMER_PID"
[ -d "$AWAKE_STATE_DIR/awake-leases/manual-timer" ]
TIMER_STATUS="$("$TEST_HOME/.local/bin/awake" status --json)"
[[ "$TIMER_STATUS" == *'"timerActive":true'* ]]
[[ "$TIMER_STATUS" == *'"effectiveLeaseId":"manual-timer"'* ]]
[[ "$TIMER_STATUS" == *'"powerState":"nosleep-display"'* ]]
[ -f "$AWAKE_STATE_DIR/ui-running" ]
"$TEST_HOME/.local/bin/awake" cancel-timer >/dev/null
TIMER_STATUS="$("$TEST_HOME/.local/bin/awake" status --json)"
[[ "$TIMER_STATUS" == *'"timerActive":false'* ]]
[[ "$TIMER_STATUS" == *'"leaseCount":0'* ]]
[[ "$TIMER_STATUS" == *'"powerState":"normal"'* ]]

"$TEST_HOME/.local/bin/awake" nosleep >/dev/null
[[ "$("$TEST_HOME/.local/bin/awake" status --json)" == *'"powerState":"nosleep-full"'* ]]
"$TEST_HOME/.local/bin/awake" yessleep >/dev/null
"$TEST_HOME/.local/bin/awake" run /usr/bin/true >/dev/null
"$TEST_HOME/.local/bin/awake" agent-auto on >/dev/null
[ "$("$TEST_HOME/.local/bin/awake" agent-auto status)" = "enabled" ]
"$TEST_HOME/.local/bin/awake" agent-auto off >/dev/null
[ "$("$TEST_HOME/.local/bin/awake" agent-auto status)" = "disabled" ]
"$TEST_HOME/.local/bin/awake" runtime-status >/dev/null

rm -f "$TEST_HOME/.local/bin/awake-package.json" \
    "$TEST_HOME/.local/bin/AwakeApp/main.swift" \
    "$TEST_HOME/Library/LaunchAgents/com.awake.runtime.plist"
SECOND_INSTALL_OUTPUT="$("$TEST_HOME/.local/bin/Awake.app/Contents/Resources/bin/awake" install 2>&1)" || {
    printf '%s\n' "$SECOND_INSTALL_OUTPUT" >&2
    exit 1
}
[ -f "$TEST_HOME/.local/bin/awake-package.json" ]
[ -f "$TEST_HOME/.local/bin/AwakeApp/main.swift" ]
[ -f "$AWAKE_STATE_DIR/ui-running" ]
[ "$(cat "$AWAKE_STATE_DIR/ui-open-count")" = "2" ]

if AWAKE_TEST_OPEN_FAIL=1 "$TEST_HOME/.local/bin/awake" install >"$TEST_ROOT/failed-install.log" 2>&1; then
    echo "install unexpectedly succeeded when the menu-bar app could not open" >&2
    exit 1
fi
grep -Fq "the menu bar app could not be started" "$TEST_ROOT/failed-install.log"

echo "install flow tests passed"
