#!/bin/sh
# Builds DynamicIsland.app (needs an app bundle so macOS can ask for Automation permission).
set -e
cd "$(dirname "$0")"
swift build -c release ${ARCHS:-}
APP=DynamicIsland.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release ${ARCHS:-} --show-bin-path)/DynamicIsland" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.dynamicisland</string>
  <key>CFBundleName</key><string>DynamicIsland</string>
  <key>CFBundleExecutable</key><string>DynamicIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>แสดงแจ้งเตือนเมื่ออุปกรณ์ Bluetooth เชื่อมต่อหรือตัดการเชื่อมต่อ</string>
  <key>NSAppleEventsUsageDescription</key><string>อ่านเพลงหรือคลิปที่กำลังเล่นจาก Spotify, Music และ YouTube ในเบราว์เซอร์</string>
</dict></plist>
EOF
# Stable self-signed identity so macOS remembers permissions across rebuilds; falls back to ad-hoc.
ID=$(security find-identity -p codesigning 2>/dev/null | awk "/DynamicIsland Local/ {print \$2; exit}")
codesign --force --sign "${ID:--}" "$APP"
echo "Built $APP — run: open $APP"
