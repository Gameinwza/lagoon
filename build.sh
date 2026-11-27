#!/bin/sh
# Builds Lagoon.app (needs an app bundle so macOS can ask for Automation permission).
set -e
cd "$(dirname "$0")"
swift build -c release ${ARCHS:-}
# Default to the latest release tag, so local builds don't look outdated to the in-app updater.
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
APP=Lagoon.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
cp "$(swift build -c release ${ARCHS:-} --show-bin-path)/DynamicIsland" "$APP/Contents/MacOS/Lagoon"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.gameinwza.lagoon</string>
  <key>CFBundleName</key><string>Lagoon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Lagoon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>แสดงแจ้งเตือนเมื่ออุปกรณ์ Bluetooth เชื่อมต่อหรือตัดการเชื่อมต่อ</string>
  <key>NSAppleEventsUsageDescription</key><string>อ่านเพลงหรือคลิปที่กำลังเล่นจาก Spotify, Music และ YouTube ในเบราว์เซอร์</string>
</dict></plist>
EOF
# Stable self-signed identity so macOS remembers permissions across rebuilds; falls back to ad-hoc.
ID=$(security find-identity -p codesigning 2>/dev/null | awk "/DynamicIsland Local/ {print \$2; exit}")
codesign --force --sign "${ID:--}" "$APP"
echo "Built $APP — run: open $APP"
