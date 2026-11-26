#!/usr/bin/env bash
# plasma-driveway — install for the current user (no sudo, no layering).
# Works on Bazzite / Fedora Kinoite / any Plasma 6 (6.3+) desktop.
#
# All paths are parameters; nothing is hardcoded.
#   DRIVEWAY_DEST   (default ~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.driveway)
#   DRIVEWAY_NO_RESTART=1  skip the plasmashell restart (register later)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${DRIVEWAY_DEST:-$HOME/.local/share/plasma/plasmoids/com.gdeyoung.plasma.driveway}"

# ---- prerequisites --------------------------------------------------------
missing=()
command -v python3 >/dev/null 2>&1 || missing+=("python3 (usually present on Bazzite; rpm-ostree install python3)")
command -v lsblk >/dev/null 2>&1 || missing+=("lsblk (util-linux, standard)")
command -v findmnt >/dev/null 2>&1 || missing+=("findmnt (util-linux, standard)")
command -v udisksctl >/dev/null 2>&1 || missing+=("udisksctl (udisks2, standard for disk actions)")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING PREREQUISITES:"
  printf '  - %s\n' "${missing[@]}"
  echo "Install them, then re-run."
  exit 1
fi
# Optional — the Cloud tab degrades to a hint without it.
if ! command -v rclone >/dev/null 2>&1; then
  echo "NOTE: rclone is not installed — the Cloud tab will show a hint instead of remotes."
  echo "      Optional: rpm-ostree install rclone  (or your distro's equivalent)."
fi
# Engine is stdlib-only (verified: no pip imports in lib/driveway/*.py) —
# nothing else to check.

echo "Installing plasma-driveway to $dest"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -r "$here" "$dest"
rm -rf "$dest"/.git   # never ship repo metadata

# BANNED (2026-11-01; sweep 2026-11-03): installers must NEVER restart
# plasmashell — the live shell reloads updated applet packages itself.
echo "Files installed. plasmashell picks up the update on its own; no restart performed."

cat <<'MSG'

Done. Add it: right-click panel → Enter Edit Mode → Add Widgets → search "Driveway" → drag to panel.

First run needs the cloud unit template (only if you use the Cloud tab):
  cp <repo>/plasma-driveway/contents/systemd/driveway-cloud@.service ~/.config/systemd/user/
  systemctl --user daemon-reload
(The engine also installs it on first cloud mount, automatically.)

Uninstall:
  kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.driveway && systemctl --user restart plasma-plasmashell.service
MSG
