#!/bin/sh
# Builds DynamicIsland.app (needs an app bundle so macOS can ask for Automation permission).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=DynamicIsland.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/DynamicIsland "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.dynamicisland</string>
  <key>CFBundleName</key><string>DynamicIsland</string>
  <key>CFBundleExecutable</key><string>DynamicIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>อ่านชื่อเพลงที่กำลังเล่นจาก Spotify และ Music</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP — run: open $APP"
