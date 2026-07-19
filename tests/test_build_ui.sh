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
grep -Fq 'AGENT_AUTO_FILE' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq '["runtime-status"]' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq '["repair-runtime"]' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'titleVisibility = .hidden' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'standardWindowButton(.zoomButton)?.isHidden = true' "$APP_ROOT/Contents/Resources/ui/main.swift"
if grep -Fq 'title: "Allow menu bar control"' "$APP_ROOT/Contents/Resources/ui/main.swift"; then
    echo "menu bar control permission should not appear in onboarding" >&2
    exit 1
fi
if grep -Eq 'CGWarpMouseCursorPosition|promoteStatusItemToVisibleEdge|scheduleStatusItemPromotion|Move top icon forward' "$APP_ROOT/Contents/Resources/ui/main.swift"; then
    echo "menu bar icon automation should not control the pointer" >&2
    exit 1
fi
grep -Fq 'awake.blackoutFirstUseHintShown' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'Press Option + 1 anytime to show your screens' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'UserDefaults.standard.set(true, forKey: Self.firstUseHintDefaultsKey)' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'CGDisplayIsBuiltin(displayID) != 0' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'func applicationWillTerminate' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'blackoutController.deactivate(synchronously: true)' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'forceShowScreens(synchronously: true)' "$APP_ROOT/Contents/Resources/ui/main.swift"
grep -Fq 'event.keyCode == UInt16(kVK_Escape)' "$APP_ROOT/Contents/Resources/ui/main.swift"

echo "build ui tests passed"
