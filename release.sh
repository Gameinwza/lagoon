#!/bin/sh
# Builds a universal (Apple silicon + Intel) app and publishes it as a GitHub release.
# Usage: ./release.sh 1.0.0
set -e
cd "$(dirname "$0")"
V=${1:?usage: ./release.sh <version>}
VERSION=$V ARCHS="--arch arm64 --arch x86_64" ./build.sh
ZIP=DynamicIsland-$V.zip
rm -f "$ZIP"
ditto -c -k --keepParent DynamicIsland.app "$ZIP"   # ditto keeps the code signature intact
gh release create "v$V" "$ZIP" --target main --title "DynamicIsland $V" --generate-notes
rm -f "$ZIP"
