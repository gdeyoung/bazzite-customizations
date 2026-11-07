#!/usr/bin/env bash
# run-foyer.sh — nested-kwin harness for the Foyer QML UI (plasmawindowed host).
# Fleet rules honored: private XDG_RUNTIME_DIR, unique kwin socket, harness HOME,
# PID+environ-gated teardown, no live-session contact, log harvest before kills.
set -u

HARNESS=/tmp/foyer-harness
PKGDIR="$(cd "$(dirname "$0")" && pwd)/package"

# --- self-wrap into a private runtime dir (socket-isolation law) -----------
if [ -z "${FOYER_RW:-}" ]; then
  export FOYER_RW=1
  rm -rf "$HARNESS"; mkdir -p "$HARNESS/run"; chmod 0700 "$HARNESS/run"
  exec env XDG_RUNTIME_DIR="$HARNESS/run" FOYER_RW=1 dbus-run-session -- "$0" "$@"
fi

export QT_QPA_PLATFORM=wayland
export LIBGL_ALWAYS_SOFTWARE=1
export QML_XHR_ALLOW_FILE_READ=1   # harness state channel (file XHR); never needed by the daemon
export HOME="$HARNESS/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$HOME/shots"
# deterministic scheme: Breeze Dark from the system dir (Vapor is value-identical
# per earlier verification; exact hues belong to the live scheme, not the harness)
cp /usr/share/color-schemes/BreezeDark.colors "$XDG_CONFIG_HOME/kdeglobals" 2>/dev/null || true
SOCKET="foyer-h-$$"

teardown() {
  echo "=== journal harvest (HARNESS lines + applet errors) ==="
  journalctl --user _PID=${WIN_PID:-0} --no-pager 2>/dev/null | grep -E "HARNESS-|error when loading applet" | tail -30 || true
  for p in ${WIN_PID:-} ${KWIN_PID:-} ${KAM_PID:-}; do
    [ -n "$p" ] || continue
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -q "^HOME=$HOME$"; then
      kill "$p" 2>/dev/null
    elif ! [ -r "/proc/$p/environ" ] && [ -r "/proc/$p/cmdline" ]; then
      # environ unreadable: harness-unique socket name is a safe identity
      if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "foyer-h-"; then
        kill "$p" 2>/dev/null
      fi
    fi
  done
}
trap teardown EXIT

echo "CKPT-0 private runtime + bus up"

# --- assemble package from src ---------------------------------------------
AS="$HARNESS/pkg"
rm -rf "$AS"
mkdir -p "$AS/contents/ui"
cp "$PKGDIR/metadata.json" "$AS/"
cp "$PKGDIR/contents/ui/main.qml" "$AS/contents/ui/"
cp "$(dirname "$0")/../src/qml/FoyerRoot.qml" "$AS/contents/ui/"
cp "$(dirname "$0")/../src/qml/FoyerData.js" "$AS/contents/ui/"
echo boot > "$AS/contents/ui/state.txt"
test -f "$AS/metadata.json" && test -f "$AS/contents/ui/FoyerRoot.qml" \
  && echo "CKPT-1 pkg-assembled" || { echo "CKPT-1 FAIL"; exit 1; }

# --- compositor --------------------------------------------------------------
kwin_wayland --virtual --no-lockscreen --socket "$SOCKET" \
  --width 1400 --height 1000 >"$HARNESS/kwin.log" 2>&1 &
KWIN_PID=$!
for i in $(seq 1 30); do
  [ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && break; sleep 0.5
done
[ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && echo "CKPT-2 kwin-socket" || { echo "CKPT-2 FAIL"; exit 1; }
export WAYLAND_DISPLAY="$SOCKET"

# kactivitymanagerd INSIDE the session (plasmashell aborts without it)
/usr/libexec/kactivitymanagerd >"$HARNESS/kam.log" 2>&1 &
KAM_PID=$!
for i in $(seq 1 20); do
  busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.ActivityManager >/dev/null 2>&1 && break
  sleep 0.5
done
busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.ActivityManager >/dev/null 2>&1 \
  && echo "CKPT-2b kam-up" || { echo "CKPT-2b kam FAIL"; exit 1; }

# --- install + launch --------------------------------------------------------
kpackagetool6 -t Plasma/Applet -i "$AS" >"$HARNESS/kpack.log" 2>&1 && echo "CKPT-3 installed" || {
  echo "CKPT-3 install FAIL"; cat "$HARNESS/kpack.log"; exit 1; }

plasmashell --no-respawn >"$HARNESS/shell.log" 2>&1 &
WIN_PID=$!
for i in $(seq 1 40); do
  busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.plasmashell >/dev/null 2>&1 && break
  sleep 0.5
done
busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.plasmashell >/dev/null 2>&1 \
  && echo "CKPT-4 shell-up" || { echo "CKPT-4 shell FAIL"; journalctl --user _PID=$WIN_PID --no-pager | tail -20; exit 1; }

# add the widget to the default panel (fresh shell installs nothing by itself)
cat > "$HARNESS/add.js" <<'EOF'
var ps = panels(); for (var i=0;i<ps.length;i++) ps[i].addWidget("org.kde.foyer");
EOF
busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell \
  org.kde.PlasmaShell evaluateScript s "$(cat "$HARNESS/add.js")" && echo "CKPT-4b added"

sleep 14   # applet load + 6s auto-open timer + popup settle
journalctl --user _PID=$WIN_PID --no-pager 2>/dev/null | grep -E "HARNESS-|error when loading applet" | head -8

# --- state drive + capture ---------------------------------------------------
INSTALLED="$XDG_DATA_HOME/plasma/plasmoids/org.kde.foyer/contents/ui/state.txt"
: > "$INSTALLED"
for s in boot games typed nomatch ai stream ready system fleet ssh settings; do
  echo "$s" > "$INSTALLED"
  if [ "$s" = "stream" ]; then sleep 1.2; else sleep 1.0; fi
  timeout 20 spectacle -b -n -o "$HOME/shots/qml-$s.png" >/dev/null 2>&1
  echo "SHOT $s $([ -s "$HOME/shots/qml-$s.png" ] && echo OK || echo EMPTY)"
done

echo "=== state transitions seen ==="
journalctl --user _PID=${WIN_PID:-0} --no-pager 2>/dev/null | grep -c HARNESS-STATE || true
echo "CKPT-5 done"
