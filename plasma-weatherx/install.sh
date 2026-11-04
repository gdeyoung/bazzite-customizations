#!/usr/bin/env bash
# plasma-weatherx — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
#
# Optional env overrides (install into a throwaway prefix for testing):
#   WX_DEST  destination plasmoid dir (default ~/.local/share/plasma/plasmoids)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="com.gdeyoung.plasma.weatherx"
dest_root="${WX_DEST:-$HOME/.local/share/plasma/plasmoids}"
dest="$dest_root/$id"

echo "Installing plasma-weatherx to $dest"
mkdir -p "$dest_root"
rm -rf "$dest"
cp -r "$here" "$dest"

# BANNED (2026-11-01; sweep 2026-11-03): installers must NEVER restart
# plasmashell — the live shell reloads updated applet packages itself;
# a restart bounces the user's panel mid-session.
echo "Files installed. plasmashell picks up the update on its own; no restart performed."

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "WeatherX" → drag to panel.

First run: the widget shows 🌡️ only — open its settings (gear in the popup or widget context
menu) and set latitude, longitude + place name (example: 40.7128, -74.0060), or just pin
cities with the ＋ button in the popup. No API keys needed.

Uninstall: kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.weatherx && systemctl --user restart plasma-plasmashell.service
MSG
