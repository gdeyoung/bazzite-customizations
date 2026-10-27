#!/usr/bin/env bash
# plasma-timemachine — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
#
# Usage: install.sh [plasmoid-id]     (default: com.gdeyoung.plasma.timemachine)
set -euo pipefail

id="${1:-com.gdeyoung.plasma.timemachine}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$HOME/.local/share/plasma/plasmoids/$id"

echo "Installing plasma-timemachine ($id) to $dest"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -r "$here" "$dest"

echo "Restarting plasmashell to register it…"
systemctl --user restart plasma-plasmashell.service

cat <<MSG

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "TimeMachine" → drag to panel.

Engine setup (once): cp "$dest/contents/scripts/bin/timemachine.conf.example" ~/.config/timemachine.conf
then edit TM_HOST/TM_DEST. Or use the bundled bridge: "$dest/contents/scripts/bin/tm-conf.sh" init

Uninstall: kpackagetool6 -t Plasma/Applet -r $id && systemctl --user restart plasma-plasmashell.service
MSG
