#!/usr/bin/env bash
# Install PanelPad (user-level, reversible).
set -euo pipefail
DEST="${1:-$HOME/.local/share/plasma/plasmoids}"
SRC="$(cd "$(dirname "$0")" && pwd)"
ID="$(/usr/bin/python3 -c 'import json;print(json.load(open("'$SRC'/metadata.json"))["KPlugin"]["Id"])')"
mkdir -p "$DEST"
rm -rf "$DEST/$ID"
cp -r "$SRC" "$DEST/$ID"
rm -rf "$DEST/$ID/tests" "$DEST/$ID/.git"
chmod 755 "$DEST/$ID"/contents/scripts/*.sh 2>/dev/null || true
kpackagetool6 -t Plasma/Applet -u "$DEST/$ID" 2>/dev/null \
  || kpackagetool6 -t Plasma/Applet -i "$DEST/$ID"
echo "installed $ID → $DEST/$ID"
