#!/usr/bin/env bash
# plasma-tailfin — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop with the
# tailscale CLI installed.
#
# Usage:
#   ./install.sh [--plasmoid-id ID] [--dest DIR] [--no-restart] [--dry-run]
#
#   --plasmoid-id ID   install under a different KPlugin.Id (default
#                      com.gdeyoung.plasma.tailfin; useful for testing a
#                      modified copy side-by-side with the real one)
#   --dest DIR         target plasmoids directory
#                      (default ~/.local/share/plasma/plasmoids)
#   --no-restart       copy files but skip the plasmashell restart
#   --dry-run          show what would happen, change nothing
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plasmoid_id="com.gdeyoung.plasma.tailfin"
dest_root="$HOME/.local/share/plasma/plasmoids"
restart=yes

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plasmoid-id) plasmoid_id="${2:?}"; shift 2 ;;
        --dest)        dest_root="${2:?}"; shift 2 ;;
        --no-restart)  restart=no; shift ;;
        --dry-run)     restart=dry; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if ! command -v tailscale >/dev/null 2>&1; then
    echo "WARNING: 'tailscale' CLI not found on PATH — the widget will show the disconnected state until it is installed." >&2
fi

dest="$dest_root/$plasmoid_id"
echo "Installing plasma-tailfin ($plasmoid_id) to $dest"

if [[ "$restart" == "dry" ]]; then
    echo "dry-run: would rm -rf + cp -r '$here' -> '$dest'"
    echo "dry-run: would strip tests/, Model.js mirror, README.md, install.sh from the copy"
    exit 0
fi

mkdir -p "$dest_root"
rm -rf "$dest"
cp -r "$here" "$dest"
# keep the installed package clean of repo-only test scaffolding
rm -rf "$dest/tests" "$dest/Model.js" "$dest/README.md" "$dest/install.sh"

if [[ "$restart" == "yes" ]]; then
    echo "Restarting plasmashell to register it…"
    systemctl --user restart plasma-plasmashell.service
fi

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "Tailfin" → drag to panel.

Uninstall: kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.tailfin && systemctl --user restart plasma-plasmashell.service
MSG
