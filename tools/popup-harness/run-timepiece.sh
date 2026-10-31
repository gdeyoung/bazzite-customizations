#!/bin/bash
# run-timepiece.sh — harness gate for plasma-timepiece (chip + popup, no user session).
# Env: SCALE (1|2), TAG.
set -u
SCALE="${SCALE:-1}"; TAG="${TAG:-tp}"
ROOT=/tmp/stk-harness
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 XDG_RUNTIME_DIR=/run/user/1000
kwin_wayland --virtual --no-lockscreen $([ "$SCALE" = "2" ] && echo "--width 5120 --height 2880" || echo "--width 2560 --height 1440") & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY=wayland-1
export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
rm -rf "$XDG_CONFIG_HOME/plasma"*   # fresh panel config = deterministic single instance

PKG="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.timepiece"
mkdir -p "$PKG" && cp -r /var/home/gdeyoung/work/bazzite-customizations/plasma-timepiece/* "$PKG/" \
  && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK"

MAIN="$PKG/contents/ui/main.qml"
python3 - "$MAIN" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("\n    // HARNESS-ONLY: delayed auto-open\n    Timer { id: harnessOpen; interval: 12000; running: true; onTriggered: root.expanded = true }\n", "")
hook = "\n    // HARNESS-ONLY: delayed auto-open (PlasmoidItem.expanded — the real lever)\n    Timer { id: harnessOpen; interval: 12000; running: true; onTriggered: root.expanded = true }\n"
anchor = "    compactRepresentation: MouseArea {"
assert anchor in s, "anchor missing"
s = s.replace(anchor, hook + "\n" + anchor, 1)
assert s.count("harnessOpen") == 1
open(p,'w').write(s); print("hook injected")
PY

cat > $ROOT/add-tp.js <<'JS'
var ps = panels(); for (var i=0;i<ps.length;i++) ps[i].addWidget("com.gdeyoung.plasma.timepiece");
JS

echo "CKPT-START scale=$SCALE"
QT_SCALE_FACTOR=$SCALE plasmashell --no-respawn > $ROOT/shell-tp-s$SCALE-$TAG.log 2>&1 & SHELL_PID=$!
sleep 18
busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasma.shell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-tp.js)" >/dev/null 2>&1 \
 || busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-tp.js)" >/dev/null 2>&1

sleep 7   # chip only (auto-open fires at ~+12s after widget add)
spectacle -b -n -o $ROOT/shots/tp-chip-s$SCALE-$TAG.png
sleep 14  # popup open + settle (calendar render)
spectacle -b -n -o $ROOT/shots/tp-popup-s$SCALE-$TAG.png
echo "HARNESS-LOG-BEGIN"
grep -aE "TypeError|ReferenceError|not a type|Cannot read|error when loading" $ROOT/shell-tp-s$SCALE-$TAG.log | head -5
echo "HARNESS-LOG-END"

# teardown without pgrep -f (self-match trap): kill by tracked pids, then a
# /proc scan gated on the process's OWN environment — NEVER on argv alone.
# ARGV IS NOT IDENTIFYING: the user's real Plasma 6 shell runs as
# `plasmashell --no-respawn` too (systemd unit plasma-plasmashell.service),
# and an argv-globbed kill SIGKILLed the live desktop shell twice on
# 2026-10-30. Only a process whose environ contains HOME=$ROOT/home belongs
# to this harness.
kill $SHELL_PID $KWIN_PID 2>/dev/null
sleep 2
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  [ -r "/proc/$pid/cmdline" ] || continue
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  case "$cmd" in
    *"plasmashell --no-respawn"*|*"kwin_wayland --virtual"*) ;;
    *) continue ;;
  esac
  tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "^HOME=$ROOT/home$" || continue
  kill -9 "$pid" 2>/dev/null
done
echo "DONE-tp-$TAG-s$SCALE"
