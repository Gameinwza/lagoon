#!/bin/sh
# Pulls main and, if it changed, rebuilds and reinstalls /Applications/DynamicIsland.app.
# Run by the launchd agent from install-autoupdate.sh; safe to run by hand too.
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "$(dirname "$0")"
echo "== $(date '+%F %T') checking for updates"

git fetch -q origin main
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
[ "$LOCAL" = "$REMOTE" ] && { echo "up to date ($LOCAL)"; exit 0; }

# Only fast-forward: never overwrite local commits or edits.
git switch -q main
git merge -q --ff-only origin/main
echo "updated $LOCAL -> $REMOTE"

./build.sh
pkill -x DynamicIsland || true
sleep 1
rm -rf /Applications/DynamicIsland.app
cp -R DynamicIsland.app /Applications/
open /Applications/DynamicIsland.app
echo "installed and relaunched"
