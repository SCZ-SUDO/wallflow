#!/bin/bash
#
# Builds and installs Wallflow into /Applications, then launches it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Wallflow.app"
DEST="/Applications/Wallflow.app"

"$ROOT/build.sh"

echo "▸ Installing to $DEST"
pkill -TERM -f "$DEST/Contents/MacOS/Wallflow" 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto "$APP" "$DEST"

open "$DEST"
echo "▸ Installed. Wallflow is now running in the menu bar."
