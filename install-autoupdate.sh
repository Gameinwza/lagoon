#!/bin/sh
# Installs a launchd agent that runs update.sh at login and every 30 minutes.
# Remove with: launchctl bootout gui/$(id -u)/local.dynamicisland.updater && rm ~/Library/LaunchAgents/local.dynamicisland.updater.plist
set -e
# launchd jobs can't read ~/Desktop or ~/Documents (macOS privacy), so the updater keeps its own clone.
DIR="$HOME/Library/Application Support/DynamicIsland/repo"
if [ ! -d "$DIR/.git" ]; then
  mkdir -p "$(dirname "$DIR")"
  git clone -q https://github.com/Gameinwza/mac-dynamic-island.git "$DIR"
fi
LABEL=local.dynamicisland.updater
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/DynamicIsland-update.log"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$DIR/update.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>1800</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Auto-update on: checks main at login and every 30 min. Log: $LOG"
