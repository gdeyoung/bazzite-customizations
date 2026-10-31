#!/bin/bash
# run-sysmon-v7.sh — sysmon v0.7 harness gate.
# Env: SCALE (1|2), TAB (0-3), SORT, FILTER, KILLPID (0=skip kill test), TAG.
# One run: geometry across ALL 4 tabs (driver walks tabs), then settles on
# TAB/SORT/FILTER; optional kill test (bar shot -> TERM -> verify).
set -u
SCALE="${SCALE:-1}"; TAB="${TAB:-0}"; SORT="${SORT:-cpu}"; FILTER="${FILTER:-}"; KILLPID="${KILLPID:-0}"; SELECTPID="${SELECTPID:-0}"; TAG="${TAG:-v7}"
ROOT=/tmp/stk-harness
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 XDG_RUNTIME_DIR=/run/user/1000

case "$SCALE" in
  2) W=5120; H=2880 ;;
  *) W=2560; H=1440 ;;
esac

kwin_wayland --virtual --no-lockscreen --width $W --height $H & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY=wayland-1
export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
rm -rf "$XDG_CONFIG_HOME/plasma"*
PKG="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.sysmon"
mkdir -p "$PKG"
cp -r /var/home/gdeyoung/work/bazzite-customizations/plasma-sysmon/* "$PKG/" && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK" || { echo "CKPT-PKG-FAIL"; exit 1; }

# --- injection 1: popup opens 6s after applet load (proven pattern) --------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
hook = "\n        Timer { interval: 6000; running: true; onTriggered: root.expanded = true }\n"
anchor = "compactRepresentation: MouseArea {"
assert anchor in s, "popup anchor missing"
s = s.replace(anchor, anchor + hook, 1)
assert s.count("root.expanded = true") == 1
open(p, 'w').write(s); print("popup hook in")
PY

# --- injection 2: driver — walk all 4 tabs logging geometry, then settle ---
python3 - "$PKG/contents/ui/Details.qml" "$TAB" "$SORT" "$FILTER" "$KILLPID" "$SELECTPID" <<'PY'
import sys
p, tab, sort, filt, killpid, selpid = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
s = open(p).read()
assert "harnessDrive" not in s
anchor = "    required property var sysmon\n"
assert anchor in s, "driver anchor missing"
driver = anchor + """
    Timer {
        id: harnessDrive
        interval: 800
        repeat: true
        running: true
        property int step: 0
        function geo(tag) {
            console.error("HARNESSGeoTab " + tag + " " + Math.round(details.width) + "x" + Math.round(details.height))
        }
        onTriggered: {
            step++
            if (step === 8) { details.currentTab = 1; geo(1) }
            else if (step === 12) { details.currentTab = 2; geo(2) }
            else if (step === 16) { details.currentTab = 3; geo(3) }
            else if (step === 20) {
                details.currentTab = %s
                sysmon.procSort = "%s"
                sysmon.procFilter = "%s"
                sysmon.procSelectedPid = %s
                geo(%s)
            }
            else if (step === 55 && %s > 0) { sysmon.killTarget = %s }
            else if (step === 85 && %s > 0) { console.error("HARNESSKill go " + sysmon.killTarget); sysmon.doKill(sysmon.killTarget, 15) }
            else if (step === 98) {
                console.error("HARNESSEnd procs=" + sysmon.procs.length
                    + " sort=" + sysmon.procSort + " filter=[" + sysmon.procFilter + "]"
                    + " killTarget=" + sysmon.killTarget + " killExit=" + sysmon.killExit)
            }
        }
    }
""" % (tab, sort, filt, selpid, tab, killpid, killpid, killpid)
s = s.replace(anchor, driver, 1)
open(p, 'w').write(s); print("driver in tab=%s sort=%s filter=[%s] kill=%s" % (tab, sort, filt, killpid))
PY

mkdir -p $ROOT/shots
cat > $ROOT/add-sysmon.js <<'JS'
var ps = panels(); for (var i=0;i<ps.length;i++) ps[i].addWidget("com.gdeyoung.plasma.sysmon");
JS

echo "CKPT-START scale=$SCALE"
QT_SCALE_FACTOR=$SCALE plasmashell --no-respawn > $ROOT/shell-v7-s$SCALE-$TAG.log 2>&1 & SHELL_PID=$!
sleep 18
busctl --user call org.kde.plasma.shell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-sysmon.js)" >/dev/null 2>&1 \
 || busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-sysmon.js)" >/dev/null 2>&1

if [ "$KILLPID" -gt 0 ]; then
  sleep 55   # ~step 55 (driver starts when popup opens): bar window ~t69-93
  spectacle -b -n -o $ROOT/shots/$TAG-killbar-s$SCALE.png
  sleep 24   # ~step 85: TERM fired
  sleep 12   # ~step 78: end state
  spectacle -b -n -o $ROOT/shots/$TAG-postkill-s$SCALE.png
  ps -p "$KILLPID" -o pid=,comm= >/dev/null 2>&1 && echo "KILL-RESULT still-alive" || echo "KILL-RESULT dead"
else
  sleep 32   # settled on TAB/SORT/FILTER
  spectacle -b -n -o $ROOT/shots/$TAG-tab$TAB-s$SCALE.png
  sleep 6
  spectacle -b -n -o $ROOT/shots/$TAG-tab$TAB-s$SCALE-late.png
fi

kill $SHELL_PID 2>/dev/null; sleep 2; kill $KWIN_PID 2>/dev/null
# proc-exact cleanup (never pattern-kill)
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
  case "$c" in
    /usr/bin/kwin_wayland*--virtual*|*plasmashell*--no-respawn*) kill "${d#/proc/}" 2>/dev/null ;;
  esac
done
echo "HARNESS-LOG-BEGIN"
grep -a "HARNESS" $ROOT/shell-v7-s$SCALE-$TAG.log || echo "(no HARNESS lines in shell log — check journal)"
echo "HARNESS-LOG-END"
echo "DONE-$TAG-s$SCALE"
