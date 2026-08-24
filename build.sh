#!/bin/bash
# Builds Sparks.app into ./build. Run: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sparks.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling"
swiftc -O -swift-version 5 -parse-as-library Sources/Sparks/*.swift \
  -o "$APP/Contents/MacOS/Sparks"

echo "→ icon"
swiftc -O -parse-as-library Sources/Sparks/Icon.swift Tools/makeicon.swift -o build/makeicon
build/makeicon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset build/makeicon

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sparks</string>
  <key>CFBundleDisplayName</key><string>Sparks</string>
  <key>CFBundleExecutable</key><string>Sparks</string>
  <key>CFBundleIdentifier</key><string>com.local.sparks</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true
echo "✓ built $APP"
