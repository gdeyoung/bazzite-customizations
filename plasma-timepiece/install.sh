#!/usr/bin/env bash
# plasma-timepiece — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
# Parameterized like plasma-sysmon's installer: PLASMOID_ID / DEST overridable.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="${PLASMOID_ID:-com.gdeyoung.plasma.timepiece}"
dest="${DEST:-$HOME/.local/share/plasma/plasmoids/$id}"

echo "Installing plasma-timepiece ($id) to $dest"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -r "$here" "$dest"

echo "Restarting plasmashell to register it…"
systemctl --user restart plasma-plasmashell.service

cat <<MSG

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "Time Piece" → drag to panel.
(The stock clock shows no date by default — keep or remove it as you like; this chip carries the date.)

Uninstall: kpackagetool6 -t Plasma/Applet -r $id && systemctl --user restart plasma-plasmashell.service
MSG
