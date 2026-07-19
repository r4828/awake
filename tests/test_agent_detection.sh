#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/awake-agent-detection-test.XXXXXX)"
STUB_BIN="$TEST_ROOT/bin"
ACTIVE_AGENT_FILE="$TEST_ROOT/active-agent"
FALLBACK_AIDER_FILE="$TEST_ROOT/fallback-aider"
HOOK_DIR="$TEST_ROOT/hooks"
mkdir -p "$STUB_BIN" "$HOOK_DIR" "$TEST_ROOT/home"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
    -x)
        if [ "$(cat "$AWAKE_TEST_ACTIVE_AGENT_FILE" 2>/dev/null || true)" = "${2:-}" ]; then
            echo 4242
            exit 0
        fi
        ;;
    -f)
        if [ "${2:-}" = "python.*aider" ] && [ -f "$AWAKE_TEST_FALLBACK_AIDER_FILE" ]; then
            echo 4343
            exit 0
        fi
        ;;
esac
exit 1
EOF
chmod +x "$STUB_BIN/pgrep"

export HOME="$TEST_ROOT/home"
export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export AWAKE_TEST_ACTIVE_AGENT_FILE="$ACTIVE_AGENT_FILE"
export AWAKE_TEST_FALLBACK_AIDER_FILE="$FALLBACK_AIDER_FILE"
export AWAKE_HOOK_STATE_DIR="$HOOK_DIR"

AWAKE_LIB="$TEST_ROOT/awake-lib.sh"
sed '/^# --- Main ---/,$d' "$REPO_DIR/awake" > "$AWAKE_LIB"
# shellcheck source=/dev/null
source "$AWAKE_LIB"

assert_detected_process() {
    local agent="$1"
    printf '%s\n' "$agent" > "$ACTIVE_AGENT_FILE"
    agents_running
    [[ "$(agent_summary)" == *"$agent (1)"* ]]
}

for agent in codex aider copilot amp opencode; do
    assert_detected_process "$agent"
done

printf '%s\n' "none" > "$ACTIVE_AGENT_FILE"
touch "$FALLBACK_AIDER_FILE"
agents_running
rm -f "$FALLBACK_AIDER_FILE"

if agents_running; then
    echo "reported an agent while all process and hook sources were inactive" >&2
    exit 1
fi
[ "$(agent_summary)" = "none" ]

SESSION_ID="claude-session" "$REPO_DIR/awake-hook" claude
[ -f "$HOOK_DIR/awake-claude-claude-session" ]
agents_running
[[ "$(agent_summary)" == *"claude (1 active)"* ]]

CODEX_SESSION_ID="codex-session" "$REPO_DIR/awake-notify"
[ -f "$HOOK_DIR/awake-codex-codex-session" ]
[ "$(fresh_hook_files)" = "2" ]

touch -t 200001010000 "$HOOK_DIR/awake-claude-claude-session" "$HOOK_DIR/awake-codex-codex-session"
[ "$(fresh_hook_files)" = "0" ]
[ ! -e "$HOOK_DIR/awake-claude-claude-session" ]
[ ! -e "$HOOK_DIR/awake-codex-codex-session" ]

echo "agent detection tests passed"
