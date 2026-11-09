#!/usr/bin/env bash
# install.sh — Foyer for KDE, 100% user-space install (no rpm-ostree, no sudo).
#
#   ./install.sh --install            stage files, dbus activation, systemd user unit
#   ./install.sh --take-hotkey        ALSO rebind Meta+Space from hermes-menu to Foyer
#                                     (edits kglobalshortcutrc + restarts kglobalaccel;
#                                     hermes-ask/task/terminal bindings untouched)
#   ./install.sh --uninstall          remove everything (hotkey revert is manual)
#
# What lands where (all inside $HOME):
#   ~/.local/share/foyer/                 foyer.py, FoyerWindow.qml, FoyerRoot.qml, FoyerData.js
#   ~/.local/share/dbus-1/services/       gdeyoung.foyer.service (dbus activation → warm daemon)
#   ~/.config/systemd/user/               foyer.service (Type=dbus; starts on demand, stays warm)
#   ~/.local/share/applications/          gdeyoung-foyer.desktop (Exec = busctl toggle)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.local/share/foyer"

do_install() {
  mkdir -p "$DEST" \
    "$HOME/.local/share/dbus-1/services" \
    "$HOME/.config/systemd/user" \
    "$HOME/.local/share/applications"

  cp "$REPO/src/daemon/foyer.py" "$REPO/src/daemon/FoyerWindow.qml" "$DEST/"
  cp "$REPO/src/qml/FoyerRoot.qml" "$REPO/src/qml/FoyerData.js" "$DEST/"
  echo "staged: $DEST"

  # Activation goes THROUGH systemd (SystemdService=): a bare python3
  # Exec spawns an unmanaged daemon that bypasses the unit — no
  # Restart=on-failure, no unit journal, no watchdog. SystemdService=
  # hands activation to systemd directly (dbus 1.14+ user services);
  # Type=dbus blocks the activating call until BusName is claimed.
  cat > "$HOME/.local/share/dbus-1/services/gdeyoung.foyer.service" <<EOF
[D-BUS Service]
Name=gdeyoung.foyer
SystemdService=foyer.service
EOF

  cat > "$HOME/.config/systemd/user/foyer.service" <<EOF
[Unit]
Description=Foyer launcher daemon (user-space, layer-shell overlay)
# Type=dbus: systemd (or any bus client) starts us on first call; we stay
# resident so subsequent summons are a warm show() — the krunner pattern.
After=graphical-session.target

[Service]
Type=dbus
BusName=gdeyoung.foyer
ExecStart=/usr/bin/python3 $DEST/foyer.py
Restart=on-failure
RestartSec=2
# no start limit: RestartSec=2 bounds crash-loop load to one try per 2 s,
# and a launcher should never stop trying (measured: 6 rapid kills never
# trip the default burst window)
StartLimitIntervalSec=0
# steady RSS ~185 MB with the 252-app catalog; 768M bounds runaway
# without OOM-killing normal QML render peaks (4x headroom)
MemoryMax=768M
CPUWeight=50
# hung event loop (no frameSwapped, no sd_notify pings) restarts after 10 s
WatchdogSec=10

[Install]
WantedBy=default.target
EOF

  cat > "$HOME/.local/share/applications/gdeyoung-foyer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Foyer
Comment=Summon the Foyer launcher
Exec=busctl --user call gdeyoung.foyer /gdeyoung/foyer gdeyoung.foyer toggle
Icon=preferences-system-windows
NoDisplay=true
X-KDE-GlobalAccel-CommandScript=true
EOF

  systemctl --user daemon-reload
  systemctl --user enable foyer.service >/dev/null 2>&1 || true
  # Refresh the KDE service database so any fresh launch path (kioclient,
  # kglobalaccel after relogin) resolves the NEW Exec, not a stale sycoca copy.
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  echo "installed: dbus activation + systemd user unit + launcher desktop file"
  echo "summon:    systemctl --user start foyer.service   (or just call the bus)"
  echo "hotkey:    re-run with --take-hotkey to bind Meta+Space (removes it from hermes-menu)"
}

do_take_hotkey() {
  # hermes-menu.desktop currently holds Meta+Space in kglobalshortcutrc
  # [services]; move it to gdeyoung-foyer.desktop. Flag-gated on purpose.
  kwriteconfig6 --file kglobalshortcutsrc \
    --group services --group hermes-menu.desktop --key _launch none
  kwriteconfig6 --file kglobalshortcutrc \
    --group services --group gdeyoung-foyer.desktop --key _launch 'Meta+Space'
  qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.blockGlobalShortcuts true 2>/dev/null || true
  systemctl --user restart plasma-kglobalaccel.service 2>/dev/null \
    || pkill -HUP -x kglobalaccel 2>/dev/null || true
  echo "hotkey: Meta+Space → gdeyoung-foyer.desktop (hermes-menu released)"
}

do_uninstall() {
  systemctl --user disable --now foyer.service >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/foyer.service" \
    "$HOME/.local/share/dbus-1/services/gdeyoung.foyer.service" \
    "$HOME/.local/share/applications/gdeyoung-foyer.desktop"
  rm -rf "$DEST"
  systemctl --user daemon-reload
  echo "uninstalled (if you ran --take-hotkey, rebind Meta+Space by hand)"
}

case "${1:-}" in
  --install)      do_install ;;
  --take-hotkey)  do_take_hotkey ;;
  --uninstall)    do_uninstall ;;
  *) echo "usage: $0 --install | --take-hotkey | --uninstall"; exit 1 ;;
esac
