#!/bin/zsh
# Captures the slide editor's inspector, each tab, at its narrowest width, and prints any overflow the Debug
# build's overflowGuard logged (docs/adr/0002-spacing-and-panel-padding.md).
#
# Usage: scripts/layout-screenshots.sh [data directory]
#   The data directory holds a Project.json and Media/ to test with. It defaults to build/layout/data; empty,
#   the app opens its sample project there. Use a project with image and video backgrounds to check those rows.
#   The operator's own show is never opened or changed.
#
# Needs: Terminal allowed under Privacy & Security › Screen Recording and › Accessibility, and no other copy of
# Presenter running (a second copy doesn't open its window). Output goes to build/layout/.
set -euo pipefail

ROOT=${0:A:h:h}
OUT=$ROOT/build/layout
DATA=${1:-$OUT/data}
APP=$ROOT/build/Build/Products/Debug/Presenter.app
mkdir -p $OUT $DATA

if pgrep -xq Presenter; then
    echo "Quit Presenter first: a second copy doesn't open its window." >&2
    exit 1
fi

xcodebuild -project $ROOT/Presenter.xcodeproj -scheme Presenter -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath $ROOT/build CODE_SIGNING_ALLOWED=NO build -quiet

# The window ID for screencapture, from the window server.
window_id() {
    swift - "$1" <<'SWIFT'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let main = windows.first { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
print(main?[kCGWindowNumber as String] as? Int ?? 0)
SWIFT
}

start=$(date '+%Y-%m-%d %H:%M:%S')
for tab in format animate document; do
    open -n $APP --args -PresenterDebugDataDirectory $DATA -PresenterDebugOpenEditor YES \
        -PresenterDebugEditorTab $tab -PresenterDebugInspectorWidth 270 -ApplePersistenceIgnoreState YES
    sleep 5
    pid=$(pgrep -f "$APP/Contents/MacOS/Presenter")
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid)
        set frontmost to true
        set size of window 1 to {1100, 700}
    end tell"
    sleep 1
    screencapture -o -x -l$(window_id $pid) $OUT/inspector-$tab-270.png
    echo "Saved $OUT/inspector-$tab-270.png"
    kill -TERM $pid
    sleep 2
done

echo "Overflow logged by the Debug build (none is good):"
/usr/bin/log show --start "$start" --predicate 'subsystem == "io.github.alps2005.Presenter" AND category == "Layout"' \
    --style compact | grep -v '^Timestamp' || true
