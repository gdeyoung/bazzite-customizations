#!/usr/bin/env bash
# run-foyer-daemon.sh — nested-kwin harness for the user-space Foyer daemon.
# Proves: layer-shell window maps, DBus toggle/show/hide work, states drive,
# Esc/hide round-trips. Fleet rules: private runtime dir, unique kwin socket,
# PID+environ-gated teardown, log harvest, never the live session.
set -u

HARNESS=/tmp/foyer-d-harness
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# --- self-wrap into a private runtime dir (socket-isolation law) -----------
if [ -z "${FOYER_D_RW:-}" ]; then
  export FOYER_D_RW=1
  rm -rf "$HARNESS"; mkdir -p "$HARNESS/run"; chmod 0700 "$HARNESS/run"
  exec env XDG_RUNTIME_DIR="$HARNESS/run" FOYER_D_RW=1 dbus-run-session -- "$0" "$@"
fi

export QT_QPA_PLATFORM=wayland
export LIBGL_ALWAYS_SOFTWARE=1
export HOME="$HARNESS/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$HOME/shots"
cp /usr/share/color-schemes/BreezeDark.colors "$XDG_CONFIG_HOME/kdeglobals" 2>/dev/null || true
SOCKET="foyer-d-$$"

teardown() {
  echo "=== daemon.log tail ==="; tail -15 "$HARNESS/daemon.log" 2>/dev/null
  for p in ${DAEMON_PID:-} ${KWIN_PID:-}; do
    [ -n "$p" ] || continue
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -q "^HOME=$HOME$"; then
      kill "$p" 2>/dev/null
    elif ! [ -r "/proc/$p/environ" ] && [ -r "/proc/$p/cmdline" ]; then
      tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "foyer-d-" && kill "$p" 2>/dev/null
    fi
  done
}
trap teardown EXIT

echo "CKPT-0 private runtime + bus up"

# --- stage the daemon (FoyerWindow hosts canonical src/qml files) ----------
STAGE="$HARNESS/stage"; mkdir -p "$STAGE"
cp "$REPO/src/daemon/foyer.py" "$REPO/src/daemon/FoyerWindow.qml" "$STAGE/"
cp "$REPO/src/qml/FoyerRoot.qml" "$REPO/src/qml/FoyerData.js" "$STAGE/"
test -f "$STAGE/FoyerWindow.qml" && test -f "$STAGE/FoyerRoot.qml" \
  && echo "CKPT-1 staged" || { echo "CKPT-1 FAIL"; exit 1; }

# --- compositor --------------------------------------------------------------
kwin_wayland --virtual --no-lockscreen --socket "$SOCKET" \
  --width 1400 --height 1000 >"$HARNESS/kwin.log" 2>&1 &
KWIN_PID=$!
for i in $(seq 1 30); do
  [ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && break; sleep 0.5
done
[ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && echo "CKPT-2 kwin-socket" || { echo "CKPT-2 FAIL"; exit 1; }
export WAYLAND_DISPLAY="$SOCKET"

# --- daemon ------------------------------------------------------------------
/usr/bin/python3 "$STAGE/foyer.py" >"$HARNESS/daemon.log" 2>&1 &
DAEMON_PID=$!
BUSADDR="$DBUS_SESSION_BUS_ADDRESS"
BUS="busctl --address=$BUSADDR"
for i in $(seq 1 40); do
  $BUS status gdeyoung.foyer >/dev/null 2>&1 && break; sleep 0.5
done
$BUS status gdeyoung.foyer >/dev/null 2>&1 && echo "CKPT-3 daemon-on-bus" || {
  echo "CKPT-3 FAIL"; cat "$HARNESS/daemon.log"; exit 1; }

# --- show + capture ----------------------------------------------------------
BC="$BUS call gdeyoung.foyer /gdeyoung/foyer gdeyoung.foyer"
echo "=== introspect ==="
$BUS introspect gdeyoung.foyer /gdeyoung/foyer 2>&1 | grep -E 'method|interface' | head -10
$BC showUI; echo "showUI rc=$?"
echo "CKPT-4 showUI"
sleep 2
timeout 20 spectacle -b -n -o "$HOME/shots/d-boot.png" >/dev/null 2>&1
echo "SHOT boot $([ -s "$HOME/shots/d-boot.png" ] && echo OK || echo EMPTY)"

for s in games typed nomatch ai stream ready system fleet ssh settings; do
  $BC driveState s "$s" >/dev/null
  sleep 1.0
  timeout 20 spectacle -b -n -o "$HOME/shots/d-$s.png" >/dev/null 2>&1
  echo "SHOT $s $([ -s "$HOME/shots/d-$s.png" ] && echo OK || echo EMPTY)"
done

# --- toggle round-trip: hide → desktop-only, show → UI again ----------------
$BC toggle >/dev/null; sleep 0.8
timeout 20 spectacle -b -n -o "$HOME/shots/d-hidden.png" >/dev/null 2>&1
$BC toggle >/dev/null; sleep 0.8
$BC driveState s boot >/dev/null; sleep 0.6
timeout 20 spectacle -b -n -o "$HOME/shots/d-reshown.png" >/dev/null 2>&1
echo "CKPT-5 toggle-roundtrip"

# --- UI LAW gate: no light box fills behind text, in any rendered view -----
python3 "$(dirname "$0")/check-contrast.py" --shots "$HOME/shots" || {
  echo "CKPT-5b CONTRAST-FAIL"; exit 1; }
echo "CKPT-5b contrast-gate PASS"

# --- FULL-NAV gate: every option in every view reachable by arrows --------
python3 "$(dirname "$0")/check-nav.py" || {
  echo "CKPT-5c NAV-FAIL"; exit 1; }
echo "CKPT-5c nav-gate PASS"
echo "CKPT-6 done"
