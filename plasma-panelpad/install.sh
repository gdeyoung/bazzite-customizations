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
kpackagetool6 -t Plasma/Applet -u "$SRC" 2>/dev/null \
  || true   # -u DELETES the package at the given path: never point it at
            # $DEST (self-destruct). Repo-path -u just unregisters; files
            # are already copied in place above.
test -f "$DEST/$ID/metadata.json"
echo "installed $ID → $DEST/$ID (from repo $SRC)"
