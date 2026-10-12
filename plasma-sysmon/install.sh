#!/usr/bin/env bash
# plasma-sysmon — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$HOME/.local/share/plasma/plasmoids/com.gdeyoung.plasma.sysmon"

echo "Installing plasma-sysmon to $dest"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -r "$here" "$dest"

echo "Restarting plasmashell to register it…"
systemctl --user restart plasma-plasmashell.service

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "SysMon" → drag to panel.

Uninstall: kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.sysmon && systemctl --user restart plasma-plasmashell.service
MSG
