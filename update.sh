#!/bin/sh
# Pulls main and, if it changed, rebuilds and reinstalls /Applications/Lagoon.app.
# Run by the launchd agent from install-autoupdate.sh; safe to run by hand too.
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "$(dirname "$0")"
# Everything runs inside main(), so sh has read the whole file before the git merge below rewrites it.
main() {
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
  pkill -x Lagoon || true
  pkill -x DynamicIsland || true  # app was called DynamicIsland before 1.1
  sleep 1
  rm -rf /Applications/Lagoon.app /Applications/DynamicIsland.app
  cp -R Lagoon.app /Applications/
  open /Applications/Lagoon.app
  echo "installed and relaunched"
  rm -rf DynamicIsland.app  # leftover build from before the rename
}
main "$@"
exit
