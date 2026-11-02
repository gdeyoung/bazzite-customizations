#!/usr/bin/env bash
# Hermes desktop keys for KDE Plasma 6 (user-level, reversible).
#
# What this wires (Omarchy-parity muscle memory on Bazzite):
#   Meta+Space        → KRunner PRELOADED with "apps" — the launcher menu
#                       (pins, most-used, categories) is on screen at open;
#                       backspace = plain search box. Requires the v0.6
#                       hermes-runner apps lane. (v3)
#   Meta+Return       → Konsole (Omarchy's "super enter = terminal")
#   Meta+H            → KRunner preloaded with "ai " — type the question, Enter
#   Meta+Shift+H      → KRunner preloaded with "hr " — type the task, Enter
#
# v3: Super+Space moves from plain KRunner to the apps-menu preload.
# revert returns to the v2 state (Super+Space = plain KRunner).
#
# No remapper needed: kglobalaccel already ships this layer. Nothing here
# touches voxtype PTT (hold COMPOSE on the Ornata, evdev 127 — checked free).
#
# Mechanism notes (v2, reconciled against the live box 2026-11-01):
#   - App-launcher shortcuts live in kglobalshortcutsrc as nested groups:
#     [services][<desktop-file-id>] with key _launch. Bare combo value
#     (e.g. "Meta+Return") matches how the daemon normalizes the file.
#   - The preloads call KRunner's DBus /App query, which opens the window
#     with the text prefilled (verified against KRunner 6.31 in the runner
#     harness). Everything then flows through the normal Match→Run path,
#     so counters/recents work. The v1 kdialog+direct-Run design is gone:
#     .desktop Exec lines are NOT shell-parsed, so $(kdialog …) never ran.
#
# Usage:  ./hermes-keys.sh apply|revert|status
# After apply: log out/in once (or restart kglobalaccel) for binds to register;
# then verify each key per README-KEYS.md. All binds visible/removable in
# System Settings → Keyboard → Shortcuts.
set -euo pipefail

MODE="${1:-status}"
KSRC="$HOME/.config/kglobalshortcutsrc"
APPS="$HOME/.local/share/applications"

write_desktop() {  # id, Name, Exec, Icon
  cat > "$APPS/$1.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
NoDisplay=true
DESK
}

svc() {  # desktop-id, combo  → kwriteconfig6 into [services][<id>] _launch
  kwriteconfig6 --file kglobalshortcutsrc --group services --group "$1" \
    --key "_launch" "$2"
}

apply() {
  mkdir -p "$APPS"

  # 1. Meta+Space → KRunner preloaded with the apps browse menu (v3).
  #    The preload opens the window AND renders the lane, so Super+Space
  #    lands on a menu, not an empty box. kglobalaccel allows one _launch
  #    owner per combo: drop krunner's own stanza, then claim it.
  write_desktop hermes-menu "Hermes Menu" \
    'busctl --user call org.kde.krunner /App org.kde.krunner.App query s "apps"' \
    "start-here-kde"
  kwriteconfig6 --file kglobalshortcutsrc --delete \
    --group services --group "org.kde.krunner.desktop" --key "_launch" \
    >/dev/null 2>&1 || true
  svc "hermes-menu.desktop" "Meta+Space"

  # 2. Meta+Return → Konsole
  write_desktop hermes-terminal "Hermes Terminal" "konsole" "utilities-terminal"
  svc "hermes-terminal.desktop" "Meta+Return"

  # 3. Meta+H → KRunner preloaded with the ask prefix
  write_desktop hermes-ask "Hermes Ask" \
    'busctl --user call org.kde.krunner /App org.kde.krunner.App query s "ai "' \
    "help-browser"
  svc "hermes-ask.desktop" "Meta+H"

  # 4. Meta+Shift+H → KRunner preloaded with the task prefix
  write_desktop hermes-task "Hermes Task" \
    'busctl --user call org.kde.krunner /App org.kde.krunner.App query s "hr "' \
    "system-run"
  svc "hermes-task.desktop" "Meta+Shift+H"

  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  echo "Applied. Log out/in (or reboot) once so kglobalaccel picks these up."
  echo "Then verify per README-KEYS.md — each bind is also listed in"
  echo "System Settings → Keyboard → Shortcuts."
}

revert() {
  # Back to v2 state: plain KRunner on Meta+Space; drop custom groups+files.
  svc "org.kde.krunner.desktop" "Meta+Space"
  for g in "hermes-terminal.desktop" "hermes-ask.desktop" \
           "hermes-task.desktop" "hermes-menu.desktop"; do
    # --delete before the groups, KEY-level: group-only delete is a no-op in
    # kwriteconfig6; deleting the last key drops the group header with it.
    kwriteconfig6 --file kglobalshortcutsrc --delete \
      --group services --group "$g" --key "_launch" >/dev/null 2>&1 || true
  done
  rm -f "$APPS"/hermes-{terminal,ask,task,menu}.desktop
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  echo "Reverted (log out/in to settle). Custom .desktop launchers removed."
}

status() {
  echo "== current binds ([services] groups) =="
  grep -E '^\[services\]\[org\.kde\.krunner\.desktop\]|^\[services\]\[hermes-' \
    -A1 "$KSRC" 2>/dev/null || echo "  (none yet)"
  echo
  echo "== collision scan for the four combos (should be empty) =="
  grep -B1 -E '=(Meta\+H|Meta\+Return|Meta\+Shift\+H|Meta\+Space)(,|;|$)' "$KSRC" 2>/dev/null \
    | grep -vE 'hermes-|\[services\]' || echo "  no collisions"
  echo
  echo "== hermes-runner (preloads need it) =="
  systemctl --user is-active hermes-runner.service 2>/dev/null \
    || echo "  (not installed/active)"
  echo
  echo "== voxtype PTT (unchanged by this script) =="
  grep -E '^key' "$HOME/.config/voxtype/config.toml" 2>/dev/null \
    || echo "  (voxtype config not found)"
}

case "$MODE" in
  apply) apply ;;
  revert) revert ;;
  status) status ;;
  *) echo "usage: $0 apply|revert|status"; exit 2 ;;
esac
