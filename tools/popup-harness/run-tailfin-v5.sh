#!/bin/bash
# run-tailfin-v3.sh — tailfin v0.4 §V acceptance gate (UX-SPEC §V-13).
# Fixture-driven: FIXTURE=norm19|norm24|norm25|empty|login|down|missing|parse
# GATE=enabled|disabled · LIGHT=0|1 · SCALE. REAL tailscale never touched
# (PATH stub). Asserts fixed frame, section-stack zero-scroll budget,
# count-sum invariant (E+census+banner+offline === total), offline toggle,
# search semantics, edge states, stub argv allowlist — pixels verified
# outside this script.
set -u
FIXTURE="${FIXTURE:-norm19}"; GATE="${GATE:-enabled}"
LIGHT="${LIGHT:-0}"; SCALE="${SCALE:-1}"; TAG="${TAG:-v3}"
ROOT=/tmp/stk-harness
REPO=/var/home/gdeyoung/work/bazzite-customizations

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

STUBLOG="$ROOT/tailfin-stub-$TAG-$FIXTURE-s$SCALE.log"
STATUSJSON="$ROOT/tailfin-status-v3-$FIXTURE.json"
: > "$STUBLOG"

# --- fixture JSON (norm19 mirrors the real tailnet shape: 19/40) ----------
python3 - "$STATUSJSON" "$FIXTURE" <<'PY'
import json, sys
path, fx = sys.argv[1], sys.argv[2]
def peer(i, online, exitc=False, exit_node=False, active=False, routes=None):
    ips = [f"100.{64 + i//250}.{i%250}.{(i%250)+2}"]
    allowed = [ips[0] + "/32"]
    if routes: allowed += routes
    if exitc:  allowed += ["0.0.0.0/0", "::/0"]
    # v0.5 fields: OS rotates across the real tailnet set; direct vs DERP
    # (CurAddr empty ⇒ relayed via Relay region); LastHandshake fresh for
    # active peers, stale for idle online, zero-time for offline.
    osv = ["linux", "windows", "macOS", "android", "iOS"][i % 5]
    direct = (i % 2 == 0)
    hs = ("2026-11-07T03:00:00Z" if active else "2026-11-06T20:00:00Z") if online \
         else "0001-01-01T00:00:00Z"
    return {
        "ID": f"p{i}", "HostName": f"host{i:02d}",
        "DNSName": f"host{i:02d}.horse-frog.ts.net.", "OS": osv, "UserID": 1,
        "Online": online, "Active": active and online,
        "ExitNodeOption": exitc, "ExitNode": exit_node and online,
        "TailscaleIPs": ips, "AllowedIPs": allowed,
        "RxBytes": 1 if not active else 1_000_000 + i * 1234,
        "TxBytes": 1 if not active else 500_000 + i * 432,
        "LastSeen": "2026-11-01T00:00:00Z" if online else "2026-10-01T00:00:00Z",
        "CurAddr": f"192.168.1.{i}" if (direct and online) else "",
        "Relay": "" if (direct and online) else "dfw",
        "LastHandshake": hs,
    }
peers = {}
health = []
if fx == "norm19" or fx == "norm19h":
    for i in range(1, 20):
        peers[f"p{i}"] = peer(i, True, exitc=(i % 3 == 0), exit_node=(i == 3),
                              active=(i % 2 == 0), routes=(["192.168.1.0/24"] if i % 4 == 0 else None))
    for i in range(100, 121):
        peers[f"p{i}"] = peer(i, False)
    if fx == "norm19h":
        health = [
            "SELinux is preventing tailscaled from opening the SSH server on the tailnet.",
            "accept-routes is disabled on this node while other nodes advertise routes",
        ]
elif fx == "zero19":
    for i in range(100, 121):
        peers[f"p{i}"] = peer(i, False)
elif fx == "empty":
    pass
elif fx in ("norm24", "norm25"):
    n = 24 if fx == "norm24" else 25
    for i in range(1, n + 1):
        peers[f"p{i}"] = peer(i, True, exitc=(i % 3 == 0), active=(i % 2 == 0))
    if fx == "norm25":
        peers["p100"] = peer(100, False)
doc = {
    "Version": "1.104.1-stub",
    "BackendState": "NeedsLogin" if fx == "login" else "Running",
    "Health": health,
    "TUN": True,
    "Self": {
        "ID": "self", "HostName": "gdtower", "DNSName": "gdtower.horse-frog.ts.net.",
        "UserID": 1, "TailscaleIPs": ["100.71.87.72", "fd7a:115c:a1e0::1"],
        "Capabilities": [],
    },
    "Peer": peers,
}
open(path, "w").write(json.dumps(doc))
print("fixture", fx, "peers", len(peers))
PY

# --- stub binary ------------------------------------------------------------
cat > "$STUBDIR/tailscale" <<STUB
#!/bin/bash
echo "tailscale \$*" >> "$STUBLOG"
case "\$1" in
  status)
    case "$FIXTURE" in
      down)    echo "failed to connect to local tailscaled; is it running?" >&2; exit 1 ;;
      missing) echo "bash: tailscale: command not found" >&2; exit 127 ;;
      parse)   echo "{not-json"; exit 0 ;;
      *)       cat "$STATUSJSON"; exit 0 ;;
    esac ;;
  debug)
    case "$GATE" in
      disabled) echo '{}'; exit 0 ;;
      *)        echo '{"OperatorUser":"gdeyoung","RouteAll":false,"CorpDNS":true}'; exit 0 ;;
    esac ;;
  up|down) exit 0 ;;
  set)    case "\$2" in --exit-node=*|--exit-node) exit 0 ;; *) exit 2 ;; esac ;;
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

# Root-cause fix (2026-11-03): nested plasmashell ABORTS shell load
# ("Aborting shell load: The activity manager daemon (kactivitymanagerd)
# is not running") on an isolated bus where DBus activation of
# org.kde.ActivityManager never spawns it. Shell then serves a hollow
# bus: panels()=0 forever, applets never instantiate. Start it ourselves.
/usr/libexec/kactivitymanagerd > "$ROOT/kamd-$FIXTURE.log" 2>&1 & KAMD_PID=$!
KAMD=0
for i in $(seq 1 20); do
  busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.ActivityManager >/dev/null 2>&1 && { KAMD=1; break; }
  sleep 0.5
done
echo "CKPT-KAMD=$KAMD"
rm -rf "$XDG_CONFIG_HOME/plasma"*
PKG="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.tailfin"
mkdir -p "$PKG"
SRCDIR="$REPO/plasma-tailfin"
if [ "${PKGSRC:-}" = "v2git" ]; then
  rm -rf "$ROOT/tailfin-v2src"; mkdir -p "$ROOT/tailfin-v2src"
  git -C "$REPO" archive HEAD plasma-tailfin | tar -x -C "$ROOT/tailfin-v2src"
  SRCDIR="$ROOT/tailfin-v2src/plasma-tailfin"
fi
cp -r "$SRCDIR/." "$PKG/" && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK src=${PKGSRC:-work}" || { echo "CKPT-PKG-FAIL"; exit 1; }

# Portal storm fix (2026-11-03): nested plasmashell's portal probes each
# cost a 25 s dbus activation timeout against backends that cannot run
# here. Blacklist all portals -> interfaces fail fast instead.
mkdir -p "$XDG_CONFIG_HOME/xdg-desktop-portals"
printf '[preferred]\ndefault=none\n' > "$XDG_CONFIG_HOME/xdg-desktop-portals/portals.conf"
echo "CKPT-PORTALS-BLACKLISTED"

if [ "$LIGHT" = "1" ]; then
  mkdir -p "$XDG_CONFIG_HOME"
  printf '[General]\nColorScheme=BreezeLight\n' > "$XDG_CONFIG_HOME/kdeglobals"
  echo "CKPT-LIGHT-ON"
fi

# --- injection 1: popup opens at t=6 (main.qml, proven pattern) -------------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
hook = "\n    Timer { interval: 6000; running: true; onTriggered: { root.expanded = true; console.error(\"HARNESSGate \" + root.gateState + \" edge=\" + root.edgeState) } }\n"
anchor = "    // ---- Data plumbing"
assert anchor in s, "data-plumbing anchor missing"
s = s.replace(anchor, hook + anchor, 1)
open(p, 'w').write(s); print("popup hook in")
PY

# --- injection 1b: applet heartbeat (is main.qml alive at all?) -----------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "    Component.onCompleted: {"
assert a in s, "onCompleted anchor missing"
s = s.replace(a, """    Component.onCompleted: {
        execSource.connectSource("echo HARNESS-APPLET-UP " + Date.now() + " >> /tmp/stk-harness/applet-up.$HARNESS_PID")""", 1)
open(p, 'w').write(s); print("heartbeat in")
PY

# --- injection 2: §V driver — geometry, census metrics, offline toggle,
# search probes (replaces the v0.3 tab/PeersTab drivers) ------------------
python3 - "$PKG/contents/ui/PopupShell.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
assert "HARNESSV4" not in s
anchor = "    Layout.minimumWidth: Kirigami.Units.gridUnit * 34"
assert anchor in s, "frame anchor missing"
drv = """    Timer {
        id: harnessV5
        interval: 500
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++
            const ok = shell.ctx.edgeState === "ok" && !shell.ctx.needsLogin
                       && shell.ctx.peers.length > 0
            if (step === 2) {
                console.error("HARNESSGEO t0 " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
            if (ok && step >= 2 && step <= 9) {
                const banner = shell.ctx.exitBannerText() !== "" ? 1 : 0
                const online = shell.ctx.onlinePeers.length
                const off = shell.ctx.offlinePeers.length
                const cands = shell.ctx.exitCandidateCount()
                // §W-14 invariants: online+offline === total; the online
                // partition (candidates+census+active-exit row) sums too.
                const sumOk = (online + off === shell.ctx.peers.length
                               && shell.ctx.exitNodes.length
                                  + shell.ctx.censusPeers.length + banner === online) ? "ok" : "BAD"
                const ch = Math.round(lane.contentItem ? lane.contentItem.contentHeight : 0)
                const vh = Math.round(lane.height)
                console.error("HARNESSV5 content=" + ch + " view=" + vh
                    + " needs=" + (ch > vh + 2 ? 1 : 0)
                    + " online=" + online
                    + " cands=" + cands
                    + " off=" + off
                    + " total=" + shell.ctx.peers.length
                    + " band=" + banner + " sum=" + sumOk)
            }
            if (step === 7 && ok && shell.ctx.offlinePeers.length > 0) {
                shell.offlineExpanded = true
                console.error("HARNESSTOGGLE expanded=1")
            }
            // Scroll the lane to the bottom after expanding so the offexp
            // capture shows the offline block, not the top fold.
            if (step === 9 && ok && shell.offlineExpanded) {
                lane.contentItem.contentY = lane.contentItem.contentHeight
            }
            if (ok && step === 14) {
                shell.ctx.searchOpen = true
                shell.ctx.peerQuery = "host03"
                console.error("HARNESSSEARCH q=host03 n=" + shell.ctx.searchResults.length)
            }
            if (ok && step === 20) {
                shell.ctx.peerQuery = "host zzz"
                console.error("HARNESSSEARCH q=hostzzz n=" + shell.ctx.searchResults.length)
            }
            if (ok && step === 22) {
                shell.ctx.peerQuery = ""
                shell.ctx.searchOpen = false
                console.error("HARNESSSEARCH q=cleared n=" + shell.ctx.searchResults.length)
                console.error("HARNESSGEO t0b " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
        }
    }

"""
s = s.replace(anchor, drv + anchor, 1)
open(p, 'w').write(s); print("v4 driver in")
PY

echo "CKPT-START fixture=$FIXTURE gate=$GATE light=$LIGHT scale=$SCALE"
QT_SCALE_FACTOR=$SCALE QT_LOGGING_RULES="org.kde.plasma*=true;js=true" plasmashell --no-respawn > $ROOT/shell-tailfin-v3-$FIXTURE-s$SCALE$LIGHT.log 2>&1 & SHELL_PID=$!
# Poll for the shell bus name (up to 120 s) + settle, then add the widget.
READY=0
for i in $(seq 1 240); do
  busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.plasmashell >/dev/null 2>&1 && { READY=1; break; }
  sleep 0.5
done
echo "CKPT-SHELL-READY=$READY after=$(( (i+1)/2 ))s"
sleep 6
cat > $ROOT/add-tailfin.js <<'JS'
// Nested shells no longer auto-create a default panel (observed
// 2026-11-03; October builds did). Create one deterministically.
var ps = panels();
var p = ps.length > 0 ? ps[0] : new Panel;
var w = p.addWidget("com.gdeyoung.plasma.tailfin");
var c = p.addWidget("org.kde.plasma.analogclock");
throw new Error("HADD " + w.id + " CLOCK " + c.id + " PANELS " + ps.length);
JS
cat > $ROOT/count-panels.js <<'JS'
throw new Error("NPANELS " + panels().length);
JS
PANELS=0
for i in $(seq 1 180); do
  busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/count-panels.js)" 2>&1 | grep -aq "NPANELS [1-9]" && { PANELS=1; break; }
  sleep 0.5
done
echo "CKPT-PANELS=$PANELS after=$(( (i+1)/2 ))s"
ADDERR=$(busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-tailfin.js)" 2>&1)
echo "CKPT-ADD: $(echo "$ADDERR" | head -1)"
# Popup opens 6 s after applet load; §V driver steps are 500 ms each from
# popup creation. Shots: view @T+1 (step2) · offline-expanded @T+4 (toggle
# step7) · search mode @T+5.5 (probe step10).
sleep 7
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-view-s$SCALE$LIGHT.png
sleep 3
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-offexp-s$SCALE$LIGHT.png
sleep 3.5
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-search-s$SCALE$LIGHT.png
sleep 4

kill $SHELL_PID 2>/dev/null; sleep 2; kill $KWIN_PID 2>/dev/null
echo "CKPT-CLEANUP-DONE"

# console.error from applet QML lands in the USER JOURNAL, never the
# shell's stderr redirect (0 bytes is normal for a healthy shell) —
# skill law. Harvest the journal for this shell pid, then grep THAT.
LOG=$ROOT/shell-tailfin-v3-$FIXTURE-s$SCALE$LIGHT.log
journalctl --user _PID=$SHELL_PID --no-pager > "$ROOT/harness-journal-$TAG-$FIXTURE.log" 2>/dev/null || true
LOG=$ROOT/harness-journal-$TAG-$FIXTURE.log
echo "===ASSERTS==="
# A1: frame is fixed — one unique geometry across the whole run incl. the
# search round-trip (t0/t0b) and never resized by content.
G=$(grep -ao "HARNESSGEO t[0-9b]* [0-9]*x[0-9]*" "$LOG" | awk '{print $3}' | sort -u | wc -l)
echo "GEO-UNIQUE=$G (want 1)"
grep -ao "HARNESSGEO t[0-9b]* [0-9]*x[0-9]*" "$LOG"
# A2: section-stack scroll budget (latest 4 lines incl. expanded + post-search)
grep -ao "HARNESSV5 content=[0-9]* view=[0-9]* needs=[01] online=[0-9]* cands=[0-9]* off=[0-9]* total=[0-9]* band=[01] sum=ok" "$LOG" | tail -4
SUMBAD=$(grep -ac "sum=BAD" "$LOG" || true); echo "SUM-BAD=$SUMBAD (want 0)"
# A3: offline toggle fired (norm fixtures with offline peers)
grep -a "HARNESSTOGGLE" "$LOG" || echo "TOGGLE-ABSENT (ok for 0-offline fixtures)"
# A4: search semantics — host03 -> 1, host+zzz -> 0, cleared -> sections
grep -ao "HARNESSSEARCH q=[a-z0-9]* n=[0-9]*" "$LOG"
# gate/edge verdict
grep -ao "HARNESSGate .*" "$LOG" || echo "GATE-LINE-MISSING"
# A9: stub argv allowlist (status / debug prefs / id -un only)
BAD=$(grep -avE "^tailscale (status --json|debug prefs|set --exit-node|up|down)$" "$STUBLOG" | grep -ac "^tailscale" || true)
echo "STUB-ARGV-BAD=$BAD (want 0)"
echo "STUB-ARGV:"; cat "$STUBLOG"
# A11: no frozen popupWidth/Height keys on the applet
grep -c "popupWidth\|popupHeight" "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | sed 's/^/POPUPKEYS=/'
echo "DONE-$FIXTURE-s$SCALE$LIGHT"
# Nuke our whole process group (dbus-run-session's): session bus daemon,
# portal strays, everything. The REAL session bus is a systemd user unit
# in a different group — untouchable by this.
KILLPG=$(ps -o pgid= -p $$ | tr -d ' ')
[ -n "$KILLPG" ] && kill -- -"$KILLPG" 2>/dev/null
exit 0
