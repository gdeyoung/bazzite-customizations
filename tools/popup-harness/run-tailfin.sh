#!/bin/bash
# run-tailfin.sh — tailfin v0.2 control-surface harness gate.
# Env: SCALE (1|2), TAG. The REAL tailscale binary is never touched: a stub
# dir is first in the nested plasmashell's PATH (logger + canned JSON), and
# the driver asserts the stub LOG, not just pixels. First real op is the
# user at the desk — automation never fires one (harness skill rule).
set -u
SCALE="${SCALE:-1}"; TAG="${TAG:-ctl}"
ROOT=/tmp/stk-harness
REPO=/var/home/gdeyoung/work/bazzite-customizations

# --- 2026-10-31 isolation: private XDG_RUNTIME_DIR, harness HOME exported
# BEFORE kwin launch, named socket, self-wrapping re-exec.
export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
STUBDIR="$ROOT/stub-tailfin"
if [ -z "${HARNESS_RT_ISOLATED:-}" ]; then
  RT="$ROOT/run"; mkdir -p "$RT"; chmod 700 "$RT" 2>/dev/null || true
  mkdir -p "$STUBDIR" "$ROOT/shots"
  exec dbus-run-session env HARNESS_RT_ISOLATED=1 XDG_RUNTIME_DIR="$RT" \
      HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
      XDG_CACHE_HOME="$XDG_CACHE_HOME" QT_QPA_PLATFORM=wayland \
      LIBGL_ALWAYS_SOFTWARE=1 PATH="$STUBDIR:$PATH" bash "$0" "$@"
fi
SOCK="wayland-h$$"
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1

# --- stub binary: logs argv, serves canned data, exit-0 on allowlisted ops --
STUBLOG="$ROOT/tailfin-stub-$TAG-s$SCALE.log"
STATUSJSON="$ROOT/tailfin-status-$TAG.json"
: > "$STUBLOG"
cat > "$STATUSJSON" <<'JSON'
{
  "Version": "1.104.1-stub",
  "BackendState": "Running",
  "Health": [],
  "TUN": true,
  "Self": {
    "ID": "self", "HostName": "gdtower", "DNSName": "gdtower.horse-frog.ts.net.",
    "UserID": 1, "TailscaleIPs": ["100.71.87.72", "fd7a:115c:a1e0::1"],
    "Capabilities": []
  },
  "Peer": {
    "p1": {
      "ID": "p1", "HostName": "watertower", "DNSName": "watertower.horse-frog.ts.net.",
      "OS": "linux", "UserID": 1, "Online": true, "Active": true,
      "ExitNodeOption": true, "ExitNode": true,
      "TailscaleIPs": ["100.96.254.1"],
      "AllowedIPs": ["100.96.254.1/32", "0.0.0.0/0", "::/0"],
      "RxBytes": 1, "TxBytes": 1, "LastSeen": "2026-11-01T00:00:00Z"
    },
    "p2": {
      "ID": "p2", "HostName": "nasbox", "DNSName": "nasbox.horse-frog.ts.net.",
      "OS": "linux", "UserID": 1, "Online": true, "Active": true,
      "ExitNodeOption": true, "ExitNode": false,
      "TailscaleIPs": ["100.97.1.2"],
      "AllowedIPs": ["100.97.1.2/32", "0.0.0.0/0", "::/0"],
      "RxBytes": 1, "TxBytes": 1, "LastSeen": "2026-11-01T00:00:00Z"
    },
    "p3": {
      "ID": "p3", "HostName": "oldspark", "DNSName": "oldspark.horse-frog.ts.net.",
      "OS": "linux", "UserID": 1, "Online": false, "Active": false,
      "ExitNodeOption": false, "ExitNode": false,
      "TailscaleIPs": ["100.97.1.3"],
      "AllowedIPs": ["100.97.1.3/32", "192.168.1.0/24"],
      "RxBytes": 0, "TxBytes": 0, "LastSeen": "2026-10-01T00:00:00Z"
    }
  }
}
JSON
cat > "$STUBDIR/tailscale" <<STUB
#!/bin/bash
echo "tailscale \$*" >> "$STUBLOG"
case "\$1" in
  status) cat "$STATUSJSON"; exit 0 ;;
  debug)  echo '{"OperatorUser":"gdeyoung","RouteAll":false,"CorpDNS":true}'; exit 0 ;;
  up|down) exit 0 ;;
  set)    case "\$2" in --exit-node=*) exit 0 ;; *) exit 2 ;; esac ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$STUBDIR/tailscale"

case "$SCALE" in
  2) W=5120; H=2880 ;;
  *) W=2560; H=1440 ;;
esac

kwin_wayland --virtual --no-lockscreen --width $W --height $H --socket "$SOCK" & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/$SOCK" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY="$SOCK"
rm -rf "$XDG_CONFIG_HOME/plasma"*
PKG="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.tailfin"
mkdir -p "$PKG"
cp -r "$REPO/plasma-tailfin/"* "$PKG/" && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK" || { echo "CKPT-PKG-FAIL"; exit 1; }
command -v tailscale && ls -la "$(command -v tailscale)" | sed 's/^/CKPT-STUB /'

# --- injection 1: popup opens 6s after applet load (proven pattern) ---------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
hook = "\n    Timer { interval: 6000; running: true; onTriggered: { root.expanded = true; console.error(\"HARNESSGate \" + root.gateState) } }\n"
anchor = "    // ---- Data plumbing"
assert anchor in s, "data-plumbing anchor missing"
s = s.replace(anchor, hook + anchor, 1)
assert s.count("HARNESSGate") == 1
open(p, 'w').write(s); print("popup+gate hook in")
PY

# --- injection 2: control-sequence driver (400ms steps; popup at t=6) -------
# t=8 ARM · t=8.4 dead-zone re-click (must stay armed) · t=10.4 FIRE down ·
# t=14.4 exit-set nasbox · t=17.6 end checkpoint.
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
assert "harnessDrive" not in s
anchor = "    function pollNow() {"
assert anchor in s, "driver anchor missing"
driver = """    Timer {
        id: harnessDrive
        interval: 400
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++
            if (step === 20) { root.powerClicked(); console.error("HARNESSArm " + root.ctlArmed) }
            else if (step === 21) { root.powerClicked(); console.error("HARNESSDeadzone " + root.ctlArmed) }
            else if (step === 26) { root.powerClicked(); console.error("HARNESSFire") }
            else if (step === 31) { console.error("HARNESSPost busy=" + root.ctlBusy + " ctlError=[" + root.ctlError + "]") }
            else if (step === 36) { root.runControlOp("exit-set", "nasbox.horse-frog.ts.net"); console.error("HARNESSExitSet busy=" + root.ctlBusy + " switching=[" + root.ctlSwitching + "]") }
            else if (step === 44) { console.error("HARNESSEnd gate=" + root.gateState + " busy=" + root.ctlBusy + " ctlError=[" + root.ctlError + "]") }
        }
    }

"""
s = s.replace(anchor, driver + anchor, 1)
open(p, 'w').write(s); print("control driver in")
PY

cat > $ROOT/add-tailfin.js <<'JS'
var ps = panels(); for (var i=0;i<ps.length;i++) ps[i].addWidget("com.gdeyoung.plasma.tailfin");
JS

echo "CKPT-START scale=$SCALE"
QT_SCALE_FACTOR=$SCALE plasmashell --no-respawn > $ROOT/shell-tailfin-$TAG-s$SCALE.log 2>&1 & SHELL_PID=$!
sleep 18
busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-tailfin.js)" >/dev/null 2>&1 \
 || busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasma.shell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-tailfin.js)" >/dev/null 2>&1
# T0 = widget added. Popup t6, ARM t8, dead-zone t8.4, FIRE t10.4,
# post-down t12.4, exit-set t14.4, end t17.6.
sleep 7   # t7: base popup (title, Disconnect, banner+×, use on nasbox)
spectacle -b -n -o $ROOT/shots/$TAG-base-s$SCALE.png
sleep 2.5 # t9.5: armed state (post dead-zone click)
spectacle -b -n -o $ROOT/shots/$TAG-armed-s$SCALE.png
sleep 3   # t12.5: post-down (op done, forced re-poll)
spectacle -b -n -o $ROOT/shots/$TAG-postdown-s$SCALE.png
sleep 4   # t16.5: post exit-set
spectacle -b -n -o $ROOT/shots/$TAG-postexit-s$SCALE.png
sleep 2   # t18.5: end checkpoint landed

kill $SHELL_PID 2>/dev/null; sleep 2; kill $KWIN_PID 2>/dev/null
# environ-gated cleanup only — ARGV IS NOT IDENTITY (2026-10-30 incident).
# Bounded and quiet: [ -r ] pre-filter, stderr swallowed, hard 15 s cap.
timeout 15 bash -c '
for d in /proc/[0-9]*; do
  [ -r "$d/environ" ] || continue
  tr "\0" "\n" < "$d/environ" 2>/dev/null | grep -q "^HOME='"$ROOT"'/home$" && kill "${d#/proc/}" 2>/dev/null
done' 2>/dev/null
echo "CKPT-CLEANUP-DONE"

echo "HARNESS-LOG-BEGIN"
grep -a "HARNESS" $ROOT/shell-tailfin-$TAG-s$SCALE.log || echo "(no HARNESS lines in shell log — check journal)"
echo "HARNESS-LOG-END"
echo "STUB-LOG-BEGIN"
cat "$STUBLOG"
echo "STUB-LOG-END"
DOWNS=$(grep -ac "^tailscale down$" "$STUBLOG" || true)
SETS=$(grep -ac "^tailscale set --exit-node=nasbox.horse-frog.ts.net$" "$STUBLOG" || true)
echo "ASSERT downs=$DOWNS (want 1 — dead-zone must not fire) exitsets=$SETS (want 1)"
echo "DONE-$TAG-s$SCALE"
