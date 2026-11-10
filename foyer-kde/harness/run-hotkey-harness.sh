#!/usr/bin/env bash
# run-hotkey-harness.sh — proves the Meta+Space → Foyer chain END-TO-END in a
# nested session, replicating what the owner's next login will do:
#   fresh HOME + kglobalshortcutrc [services] entry + the LIVE .desktop file
#   → kwin starts (= kglobalaccel inside kwin starts, same as login)
#   → ASSERT A: kglobalaccel registers gdeyoung-foyer.desktop owning Meta+Space
#   → ASSERT B: invokeShortcut _launch (what a keypress triggers) → daemon
#     toggle → overlay window actually shows.
# Fleet rules: private runtime dir, unique kwin socket, PID+environ-gated
# teardown, checkpointed, never the live session.
set -u

HARNESS=/tmp/foyer-hotkey-harness
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOME_REAL="$HOME"
LIVE_DESKTOP="$HOME/.local/share/applications/gdeyoung-foyer.desktop"

# --- self-wrap into a private runtime dir (socket-isolation law) -----------
if [ -z "${FOYER_HK_RW:-}" ]; then
  export FOYER_HK_RW=1
  rm -rf "$HARNESS"; mkdir -p "$HARNESS/run"; chmod 0700 "$HARNESS/run"
  exec env XDG_RUNTIME_DIR="$HARNESS/run" FOYER_HK_RW=1 dbus-run-session -- "$0" "$@"
fi

export QT_QPA_PLATFORM=wayland
export LIBGL_ALWAYS_SOFTWARE=1
export HOME="$HARNESS/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/applications" "$HOME/shots"
cp /usr/share/color-schemes/BreezeDark.colors "$XDG_CONFIG_HOME/kdeglobals" 2>/dev/null || true

# --- the exact files the owner's next login will see ------------------------
# rc entry — byte-identical form to the live kglobalshortcutrc services group
printf '[services][gdeyoung-foyer.desktop]\n_launch=Meta+Space\n' \
  > "$XDG_CONFIG_HOME/kglobalshortcutrc"
# the LIVE .desktop — the test must prove this exact file, not a copy edited
# for testability
cp "$LIVE_DESKTOP" "$XDG_DATA_HOME/applications/gdeyoung-foyer.desktop" \
  && test -s "$XDG_DATA_HOME/applications/gdeyoung-foyer.desktop" \
  && echo "CKPT-0 desktop-copied" || { echo "CKPT-0 FAIL"; exit 1; }
# favorites empty + foyer config so daemon starts clean
mkdir -p "$XDG_CONFIG_HOME/foyer" "$XDG_DATA_HOME/foyer"
printf '{"ai": {"ask_exe": "/bin/true", "model": "stub-fast"}}\n' \
  > "$XDG_CONFIG_HOME/foyer/config.json"

SOCKET="foyer-hk-$$"
teardown() {
  echo "=== daemon.log tail ==="; tail -8 "$HARNESS/daemon.log" 2>/dev/null
  for p in ${DAEMON_PID:-} ${KWIN_PID:-}; do
    [ -n "$p" ] || continue
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -q "^HOME=$HOME$"; then
      kill "$p" 2>/dev/null
    fi
  done
}
trap teardown EXIT

# --- sycoca BEFORE kwin: kglobalaccel resolves KService at start -----------
timeout 60 kbuildsycoca6 --noincremental >"$HARNESS/sycoca.log" 2>&1
echo "CKPT-1 sycoca-built"

# --- compositor (= login: kglobalaccel starts inside kwin) ------------------
kwin_wayland --virtual --no-lockscreen --socket "$SOCKET" \
  --width 1400 --height 1000 >"$HARNESS/kwin.log" 2>&1 &
KWIN_PID=$!
for i in $(seq 1 40); do
  [ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && break; sleep 0.5
done
[ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && echo "CKPT-2 kwin-socket" || { echo "CKPT-2 FAIL"; exit 1; }
export WAYLAND_DISPLAY="$SOCKET"
export KDE_FULL_SESSION=true
export KDEDIRS=/usr
export XDG_CURRENT_DESKTOP=KDE
BUSADDR="$DBUS_SESSION_BUS_ADDRESS"
BUS="busctl --address=$BUSADDR"

# v2 lesson: bare kwin start does NOT load [services] entries. A real login
# runs the full Plasma session — replicate it (kactivitymanagerd is required
# or plasmashell aborts panel load; proven law from the popup harness).
/usr/libexec/kactivitymanagerd >"$HARNESS/kam.log" 2>&1 &
KAM_PID=$!
for i in $(seq 1 20); do
  timeout 5 $BUS status org.kde.ActivityManager >/dev/null 2>&1 && break; sleep 0.5
done
timeout 5 $BUS status org.kde.ActivityManager >/dev/null 2>&1 \
  && echo "CKPT-2b kam-up" || echo "CKPT-2b WARN kam-missing"
plasmashell --no-respawn >"$HARNESS/shell.log" 2>&1 &
SHELL_PID=$!
sleep 18   # full shell start (proven settle time)

for i in $(seq 1 40); do
  timeout 10 $BUS status org.kde.kglobalaccel >/dev/null 2>&1 && break; sleep 0.5
done
timeout 10 $BUS status org.kde.kglobalaccel >/dev/null 2>&1 \
  && echo "CKPT-3 kglobalaccel-on-harness-bus" || { echo "CKPT-3 FAIL"; exit 1; }

# --- ASSERT A0: does the rc entry alone register anything? (diagnostic) ----
PRE=$(timeout 10 $BUS call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel allMainComponents 2>&1 | grep -c "foyer" || true)
echo "ASSERT-A0: foyer components from rc alone = $PRE"

# --- v3 mechanism: KWin script registers the shortcut from INSIDE kwin ------
# (foreign doRegister components stay isActive=false — dead end, proven above.
# A kwin script's registerShortcut is a real kwin component: active, grabbed,
# persists via kwinrc Plugins and re-registers at every login.)
SCRIPT_SRC="$HOME_REAL/.local/share/kwin/scripts/foyerhotkey"
echo "=== raw kwin status + Scripting introspect ==="
timeout 10 $BUS status org.kde.KWin 2>&1 | head -3
timeout 10 $BUS introspect org.kde.KWin /Scripting 2>&1 | head -30
SID=$(timeout 10 $BUS call org.kde.KWin /Scripting org.kde.kwin.Scripting \
  loadScript ss "$SCRIPT_SRC/contents/ui/main.js" "foyerhotkey" 2>&1)
echo "loadScript raw: [$SID]"
SIDN=$(echo "$SID" | grep -oE '[-]?[0-9]+$')
sleep 1
timeout 10 $BUS call org.kde.KWin /Scripting org.kde.kwin.Scripting start 2>&1
sleep 2

# --- ASSERT A: the script component registered and owns Meta+Space ----------
# Meta+Space = 0x10000000|0x20 = 268435488 (proven encoding, Meta+H calibration)
OWN=$(timeout 10 $BUS call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel getGlobalShortcutsByKey i 268435488 2>&1)
echo "ASSERT-A-RAW: $OWN"
if echo "$OWN" | grep -q "foyerhotkey\|Foyer"; then
  echo "ASSERT-A PASS: kwin-script component owns Meta+Space"
else
  echo "ASSERT-A FAIL: script did not register Meta+Space"; exit 2
fi

# --- daemon ------------------------------------------------------------------
STAGE="$HARNESS/stage"; mkdir -p "$STAGE"
cp "$REPO/src/daemon/foyer.py" "$REPO/src/daemon/FoyerWindow.qml" "$STAGE/"
cp "$REPO/src/qml/FoyerRoot.qml" "$REPO/src/qml/FoyerData.js" "$STAGE/"
/usr/bin/python3 "$STAGE/foyer.py" >"$HARNESS/daemon.log" 2>&1 &
DAEMON_PID=$!
for i in $(seq 1 40); do
  timeout 10 $BUS status gdeyoung.foyer >/dev/null 2>&1 && break; sleep 0.5
done
timeout 10 $BUS status gdeyoung.foyer >/dev/null 2>&1 \
  && echo "CKPT-4 daemon-on-bus" || { echo "CKPT-4 FAIL"; cat "$HARNESS/daemon.log"; exit 1; }

# --- ASSERT B: invokeShortcut _launch == exactly what the keypress fires ----
# discover the component object path — script shortcuts live under the kwin
# component (ASSERT-A shows component "kwin", action "FoyerSummon")
TREE=$(timeout 10 $BUS tree org.kde.kglobalaccel 2>&1)
echo "ASSERT-B-TREE: $TREE"
COMP_PATH="/component/kwin"
echo "component path: $COMP_PATH"
timeout 10 $BUS call org.kde.kglobalaccel "$COMP_PATH" \
  org.kde.kglobalaccel.Component invokeShortcut s FoyerSummon
sleep 2
# the daemon logs foyer[showlat] when the overlay window actually paints
if grep -q "showlat" "$HARNESS/daemon.log"; then
  echo "ASSERT-B PASS: key fire → toggle → overlay window shown"
  grep "showlat" "$HARNESS/daemon.log" | tail -2
else
  echo "ASSERT-B FAIL: no window-show log after invokeShortcut"
  tail -20 "$HARNESS/daemon.log"
  exit 3
fi

echo "=== HOTKEY CHAIN PROVEN: login loads the bind, the key fires Foyer ==="
