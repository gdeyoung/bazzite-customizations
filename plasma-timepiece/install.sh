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

# BANNED (2026-11-01; sweep 2026-11-03): installers must NEVER restart
# plasmashell — the live shell reloads updated applet packages itself;
# a restart bounces the user's panel mid-session.
echo "Files installed. plasmashell picks up the update on its own; no restart performed."

cat <<MSG

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "Time Piece" → drag to panel.
(The stock clock shows no date by default — keep or remove it as you like; this chip carries the date.)

Uninstall: kpackagetool6 -t Plasma/Applet -r $id && systemctl --user restart plasma-plasmashell.service
MSG
