#!/usr/bin/env bash
# Install StockTick v2 (user-level, reversible).
# IMPORTANT: pass the REPO path to kpackagetool6, never a path inside the
# install destination — KPackage -u uninstalls (deletes) the package at the
# given path before installing from it, so destination-path args self-destruct.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
ID="$(/usr/bin/python3 -c 'import json;print(json.load(open("'$SRC'/metadata.json"))["KPlugin"]["Id"])')"
# Executable dataengine refuses non-executable scripts — force the bit in source.
chmod 755 "$SRC"/contents/scripts/*.sh 2>/dev/null || true
kpackagetool6 -t Plasma/Applet -u "$SRC" 2>/dev/null \
  || kpackagetool6 -t Plasma/Applet -i "$SRC"
kbuildsycoca6 2>/dev/null || true
echo "installed $ID → ~/.local/share/plasma/plasmoids/$ID"
