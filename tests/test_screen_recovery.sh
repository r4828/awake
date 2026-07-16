#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_HOME="$(mktemp -d /tmp/awake-screen-recovery-test.XXXXXX)"
STUB_BIN="$TEST_HOME/stub-bin"
CALL_LOG="$TEST_HOME/calls.log"

cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

mkdir -p "$STUB_BIN" "$TEST_HOME/.local/bin/Awake.app"

for command in open osascript pkill; do
    printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$command" "$CALL_LOG" > "$STUB_BIN/$command"
    chmod +x "$STUB_BIN/$command"
done

cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$STUB_BIN/pgrep"

HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens show >/dev/null
grep -Fq 'open awake://blackout?action=off' "$CALL_LOG"
grep -Fq 'osascript -e tell application id "com.awake.menubar" to quit' "$CALL_LOG"
grep -Fq "open -na $TEST_HOME/.local/bin/Awake.app --args --restore-screens" "$CALL_LOG"

: > "$CALL_LOG"
HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens blackout >/dev/null
grep -Fq 'open awake://blackout?action=on' "$CALL_LOG"

: > "$CALL_LOG"
HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens toggle >/dev/null
grep -Fq 'open awake://blackout?action=toggle' "$CALL_LOG"

if HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens invalid >/dev/null 2>&1; then
    echo "invalid screen action unexpectedly succeeded" >&2
    exit 1
fi

cat > "$STUB_BIN/open" <<EOF
#!/bin/bash
printf '%s %s\n' "open" "\$*" >> "$CALL_LOG"
if [ "\${1:-}" = "-na" ]; then
    exit 1
fi
EOF
chmod +x "$STUB_BIN/open"
if HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens show >/dev/null 2>&1; then
    echo "screen recovery unexpectedly ignored relaunch failure" >&2
    exit 1
fi

cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$STUB_BIN/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB_BIN/pgrep" "$STUB_BIN/sleep"
: > "$CALL_LOG"
if HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin" "$REPO_DIR/awake" screens show >/dev/null 2>&1; then
    echo "screen recovery launched while an old UI process was still alive" >&2
    exit 1
fi
grep -Fq 'pkill -TERM -x AwakeUI' "$CALL_LOG"
if grep -Fq "open -na $TEST_HOME/.local/bin/Awake.app" "$CALL_LOG"; then
    echo "screen recovery launched a concurrent UI instance" >&2
    exit 1
fi

echo "screen recovery tests passed"
