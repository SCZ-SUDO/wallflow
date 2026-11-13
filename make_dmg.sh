#!/bin/bash
#
# Packages Wallflow.app into a drag-to-Applications disk image.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Wallflow.app"
STAGE="$ROOT/build/dmg"
DMG="$ROOT/build/Wallflow-1.1.dmg"

if [[ ! -d "$APP" ]]; then
  echo "Run ./build.sh first." >&2
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Wallflow.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Wallflow" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"
echo "▸ DMG: $DMG"
