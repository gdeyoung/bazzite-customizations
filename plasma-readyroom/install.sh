#!/usr/bin/env bash
# plasma-readyroom — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
#
# Optional env overrides (none needed on a stock Bazzite -dx KDE image):
#   DEST     alternate install dir (default ~/.local/share/plasma/plasmoids/<id>)
#   NO_RESTART=1  copy only; skip the plasmashell restart
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(python3 -c 'import json;print(json.load(open("'"$here"'/metadata.json"))["KPlugin"]["Id"])')"
dest="${DEST:-$HOME/.local/share/plasma/plasmoids/$id}"

echo "Installing plasma-readyroom ($id) to $dest"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -r "$here" "$dest"
# The scripts ship executable; assert that so the dataengine can run them.
chmod +x "$dest"/contents/scripts/gc-* || true

# BANNED (2026-11-01; sweep 2026-11-03): installers must NEVER restart
# plasmashell — the live shell reloads updated applet packages itself.
echo "Files installed. plasmashell picks up the update on its own; no restart performed."

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "Ready Room" → drag to panel.

Rollback: kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.readyroom && systemctl --user restart plasma-plasmashell.service
MSG
