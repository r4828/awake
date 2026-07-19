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
exit 0
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

rm -f "$TEST_HOME/.local/bin/awake-package.json" \
    "$TEST_HOME/.local/bin/AwakeApp/main.swift" \
    "$TEST_HOME/Library/LaunchAgents/com.awake.runtime.plist"
SECOND_INSTALL_OUTPUT="$("$TEST_HOME/.local/bin/Awake.app/Contents/Resources/bin/awake" install 2>&1)" || {
    printf '%s\n' "$SECOND_INSTALL_OUTPUT" >&2
    exit 1
}
[ -f "$TEST_HOME/.local/bin/awake-package.json" ]
[ -f "$TEST_HOME/.local/bin/AwakeApp/main.swift" ]

echo "install flow tests passed"
