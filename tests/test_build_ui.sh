#!/bin/bash

set -euo pipefail

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_HOME="$(mktemp -d /tmp/awake-build-ui-test.XXXXXX)"

cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

HOME="$TEST_HOME" "$REPO_DIR/awake-build-ui" >/dev/null

APP_ROOT="$TEST_HOME/.local/bin/Awake.app"
PLIST="$APP_ROOT/Contents/Info.plist"
BINARY="$APP_ROOT/Contents/MacOS/AwakeUI"
PACKAGE_VERSION="$(/usr/bin/python3 -c 'import json; print(json.load(open("'"$REPO_DIR"'/package.json"))["version"])')"

[ -x "$BINARY" ]
[ -f "$PLIST" ]
grep -Fq "<string>awake</string>" "$PLIST"
grep -Fq "<string>$PACKAGE_VERSION</string>" "$PLIST"
[ -f "$APP_ROOT/Contents/Resources/bin/awake-package.json" ]
[ -f "$APP_ROOT/Contents/Resources/ui/main.swift" ]
grep -Fq '<string>_daemon</string>' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq '<key>SuccessfulExit</key>' "$APP_ROOT/Contents/Resources/ui/main.swift"
if grep -Fq 'title: "Allow menu bar control"' "$APP_ROOT/Contents/Resources/ui/main.swift"; then
    echo "menu bar control permission should not appear in onboarding" >&2
    exit 1
fi

echo "build ui tests passed"
