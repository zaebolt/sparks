#!/bin/bash
# Builds and runs the test suites. Run: ./Tests/run.sh [store|panel|hover|reorder]
#
# Each suite is its own executable because each declares @main. They are linked
# against the app's sources directly, minus App.swift, whose @main would clash.
set -uo pipefail
cd "$(dirname "$0")/.."

SRC=(Sources/Sparks/Store.swift Sources/Sparks/Icon.swift Sources/Sparks/HotKey.swift
     Sources/Sparks/ContentView.swift Sources/Sparks/AppDelegate.swift)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# StoreTests is headless. The other three drive the real status item and popover,
# so they need a session that can put a window on screen, and they briefly take
# focus and move the pointer. Do not drive the mouse while they run.
declare -a SUITES=(
  "store:Tests/StoreTests.swift"
  "panel:Tests/PanelTests.swift"
  "hover:Tests/HoverTests.swift"
  "reorder:Tests/ReorderTests.swift"
)

want="${1:-all}"
failed=0

for entry in "${SUITES[@]}"; do
    name="${entry%%:*}"
    file="${entry#*:}"
    [[ "$want" != "all" && "$want" != "$name" ]] && continue

    echo "=== $name ==="
    if ! swiftc -O -swift-version 5 -parse-as-library "${SRC[@]}" "$file" -o "$OUT/$name" 2>&1; then
        echo "  build failed"; failed=1; continue
    fi

    # A running copy of the app owns the hot key and a menu bar slot; the suites
    # register their own, so stand it down first.
    pkill -f "Sparks.app/Contents/MacOS/Sparks" 2>/dev/null
    sleep 1
    "$OUT/$name" || failed=1
    echo
done

exit $failed
