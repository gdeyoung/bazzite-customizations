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

# BANNED (2026-11-01; sweep 2026-11-03): installers must NEVER restart
# plasmashell — the live shell reloads updated applet packages itself;
# a restart bounces the user's panel mid-session.
echo "Files installed. plasmashell picks up the update on its own; no restart performed."

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "SysMon" → drag to panel.

Uninstall: kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.sysmon && systemctl --user restart plasma-plasmashell.service
MSG
