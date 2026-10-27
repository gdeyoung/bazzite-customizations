#!/usr/bin/env bash
# Install StockTick (user-level, reversible). NOT run during the build session —
# install is a deliberate, at-the-tower step.
# Usage: ./install.sh [DEST]   (default ~/.local/share/plasma/plasmoids)
set -euo pipefail
DEST="${1:-$HOME/.local/share/plasma/plasmoids}"
SRC="$(cd "$(dirname "$0")" && pwd)"
ID="$(/usr/bin/python3 -c 'import json;print(json.load(open("'$SRC'/metadata.json"))["KPlugin"]["Id"])')"
mkdir -p "$DEST"
rm -rf "$DEST/$ID"
cp -r "$SRC" "$DEST/$ID"
rm -rf "$DEST/$ID/tests" "$DEST/$ID/.git"
kpackagetool6 -t Plasma/Applet -u "$DEST/$ID" 2>/dev/null \
  || kpackagetool6 -t Plasma/Applet -i "$DEST/$ID"
echo "installed $ID → $DEST/$ID"
echo "next: restart plasmashell (systemctl --user restart plasma-plasmashell.service),"
echo "Add Widgets → StockTick, then verify /tmp/plasma-stocktick-hb.json advances."
