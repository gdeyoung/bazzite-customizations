#!/usr/bin/env bash
# Hermes desktop keys for KDE Plasma 6 (user-level, reversible).
#
# What this wires (Omarchy-parity muscle memory on Bazzite):
#   Meta+Space        → KRunner search (make the Omarchy default explicit)
#   Meta+Return       → Konsole (Omarchy's "super enter = terminal")
#   Meta+H            → KRunner preloaded with "ai " — type the question, Enter
#   Meta+Shift+H      → "Hermes task" input box → fires hr <task> through the
#                       runner daemon (works even with KRunner closed)
#
# No remapper needed: kglobalaccel already ships this layer. Nothing here
# touches voxtype PTT (hold COMPOSE on the Ornata, evdev 127 — checked free).
#
# Usage:  ./hermes-keys.sh apply|revert|status
# After apply: log out/in once (or restart kglobalaccel) for binds to register;
# then verify each key per README-KEYS.md. All binds visible/removable in
# System Settings → Keyboard → Shortcuts.
set -euo pipefail

MODE="${1:-status}"
KSRC="$HOME/.config/kglobalshortcutsrc"
APPS="$HOME/.local/share/applications"

hermes_task_exec() {  # shared Exec for the two hermes lanes
  echo 'busctl --user call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "task:$(kdialog --title "Hermes task" --inputbox "Run unattended (hr):" 2>/dev/null)" ""'
}

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

apply() {
  mkdir -p "$APPS"

  # 1. KRunner on Meta+Space (keep Alt+Space as the stock secondary)
  kwriteconfig6 --file kglobalshortcutsrc --group krunner \
    --key Search "Meta+Space\tAlt+Space,Meta+Space\tAlt+Space,Search"

  # 2. Meta+Return → Konsole
  write_desktop hermes-terminal "Hermes Terminal" "konsole" "utilities-terminal"
  kwriteconfig6 --file kglobalshortcutsrc --group "hermes-terminal.desktop" \
    --key "_launch" "Meta+Return,Meta+Return,Hermes Terminal"

  # 3. Meta+H → KRunner preloaded with the ask prefix
  write_desktop hermes-ask "Hermes Ask" \
    'busctl --user call org.kde.krunner /App org.kde.krunner.App query s "ai "' \
    "help-browser"
  kwriteconfig6 --file kglobalshortcutsrc --group "hermes-ask.desktop" \
    --key "_launch" "Meta+H,Meta+H,Hermes Ask"

  # 4. Meta+Shift+H → task input box → runner daemon Run()
  write_desktop hermes-task "Hermes Task" "$(hermes_task_exec)" "system-run"
  kwriteconfig6 --file kglobalshortcutsrc --group "hermes-task.desktop" \
    --key "_launch" "Meta+Shift+H,Meta+Shift+H,Hermes Task"

  echo "Applied. Log out/in (or reboot) once so kglobalaccel picks these up."
  echo "Then verify per README-KEYS.md — each bind is also listed in"
  echo "System Settings → Keyboard → Shortcuts → Custom Shortcuts."
}

revert() {
  kwriteconfig6 --file kglobalshortcutsrc --group krunner \
    --key Search "Alt+Space,Alt+Space,Search"
  for g in "hermes-terminal.desktop" "hermes-ask.desktop" "hermes-task.desktop"; do
    kwriteconfig6 --file kglobalshortcutsrc --group "$g" --key "_launch" "none,none,"
  done
  rm -f "$APPS"/hermes-{terminal,ask,task}.desktop
  echo "Reverted (log out/in to settle). Custom .desktop launchers removed."
}

status() {
  echo "== current binds =="
  grep -E '^\[krunner\]|^\[hermes-' -A1 "$KSRC" 2>/dev/null || echo "(none yet)"
  echo
  echo "== collision scan (should be empty) =="
  grep -B1 -E 'Meta\+H,|Meta\+Return,' "$KSRC" 2>/dev/null \
    | grep -vE 'hermes-|krunner|\[krunner\]' || echo "  no collisions"
  echo
  echo "== voxtype PTT (unchanged by this script) =="
  grep -E '^key' "$HOME/.config/voxtype/config.toml" 2>/dev/null || echo "  (voxtype config not found)"
}

case "$MODE" in
  apply) apply ;;
  revert) revert ;;
  status) status ;;
  *) echo "usage: $0 apply|revert|status"; exit 2 ;;
esac
