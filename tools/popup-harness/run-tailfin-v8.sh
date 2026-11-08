#!/bin/bash
# run-tailfin-v7.sh — tailfin v0.7 §V7 acceptance gate (UX-SPEC-V7 §V7-13).
# Fixture-driven: FIXTURE=norm19|norm19h|zero19|empty|login|down|missing|parse
# GATE=enabled|disabled · LIGHT=0|1 · SCALE. REAL tailscale never touched
# (PATH stub). Drives the 3-tab popup through PEERS view/offline/search,
# EXIT NODES, CONNECTION (toggles), and the machine detail page; asserts fixed frame,
# count-sum invariant, tab sequencing, search semantics, edge states —
# pixels verified outside this script.
set -u
FIXTURE="${FIXTURE:-norm19h}"; GATE="${GATE:-enabled}"
LIGHT="${LIGHT:-0}"; SCALE="${SCALE:-1}"; TAG="${TAG:-v8}"
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
elif fx == "mullvad":
    # norm19h base + mullvad exit nodes (add-on ON): 9 regions, one ACTIVE.
    # Region set mirrors real Mullvad naming (country-city-wg-NNN).
    for i in range(1, 20):
        peers[f"p{i}"] = peer(i, True, exitc=(i % 3 == 0),
                              active=(i % 2 == 0), routes=(["192.168.1.0/24"] if i % 4 == 0 else None))
    peers["p3"]["ExitNode"] = False  # mullvad active ⇒ tailnet exit NOT active
    for i in range(100, 121):
        peers[f"p{i}"] = peer(i, False)
    health = [
        "SELinux is preventing tailscaled from opening the SSH server on the tailnet.",
        "accept-routes is disabled on this node while other nodes advertise routes",
    ]
    regions = ["de-fra-wg-001", "de-fra-wg-002", "nl-ams-wg-001", "se-sto-wg-002",
               "uk-lon-wg-003", "us-nyc-wg-001", "us-chi-wg-002", "jp-tyo-wg-001",
               "au-syd-wg-001"]
    for j, r in enumerate(regions):
        p = peer(200 + j, True, exitc=True)
        p["HostName"] = r
        p["DNSName"] = r + ".mullvad.ts.net."
        p["OS"] = "linux"
        p["Relay"] = ""
        p["CurAddr"] = ""
        p["RxBytes"] = 1
        p["TxBytes"] = 1
        p["LastHandshake"] = "0001-01-01T00:00:00Z"
        if j == 0:
            p["ExitNode"] = True  # Frankfurt is the active mullvad exit
        peers["m" + r] = p
    doc_self_mullvad = "de-fra-wg-001.mullvad.ts.net."
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
        "ActiveMullvadExit": (doc_self_mullvad if fx == "mullvad" else ""),
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
hook = "\n    Timer { interval: 12000; running: true; onTriggered: { root.expanded = true; console.error(\"HARNESSGate \" + root.gateState + \" edge=\" + root.edgeState) } }\n"
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

# --- injection 2: §V7 driver — tab sequencing + per-tab invariants.
# Ids used: shell, machinesTab (PopupShell scope). Data reads via ctx only.
python3 - "$PKG/contents/ui/PopupShell.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
assert "HARNESSV7" not in s
anchor = "    Layout.minimumWidth: Kirigami.Units.gridUnit * 40"
assert anchor in s, "frame anchor missing"
drv = """    Timer {
        id: harnessV7
        interval: 500
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++
            console.error("HARNESSSTEP " + step + " tab=" + shell.ctx.selectedTab)
            const ok = shell.ctx.edgeState === "ok" && !shell.ctx.needsLogin
                       && shell.ctx.peers.length > 0
            if (step === 4) {
                console.error("HARNESSGEO t0 " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
            if (ok && step >= 4 && step <= 12) {
                const online = shell.ctx.onlinePeers.length
                const off = shell.ctx.offlinePeers.length
                const sumOk = (online + off === shell.ctx.peers.length) ? "ok" : "BAD"
                let ready = 0
                const rm = shell.ctx.rateMap
                for (const k in rm) { if (rm[k] && rm[k].ready) ready++ }
                console.error("HARNESSV7 tab=" + shell.ctx.selectedTab
                    + " online=" + online + " off=" + off
                    + " total=" + shell.ctx.peers.length
                    + " rateReady=" + ready + " sum=" + sumOk)
            }
            if (ok && step === 14 && shell.ctx.offlinePeers.length > 0) {
                machinesTab.offlineExpanded = true
                console.error("HARNESSTOGGLE expanded=1")
            }
            // scroll the lane to the bottom so the offexp capture shows
            // the offline block (proven v5 pattern)
            if (ok && (step === 16 || step === 17) && machinesTab.offlineExpanded) {
                machinesTab.laneScrollBottom()
            }
            if (ok && step === 26) {
                shell.ctx.searchOpen = true
                shell.ctx.peerQuery = "host03"
                console.error("HARNESSSEARCH q=host03 n=" + shell.ctx.searchResults.length)
            }
            if (ok && step === 40) {
                shell.ctx.peerQuery = "host zzz"
                console.error("HARNESSSEARCH q=hostzzz n=" + shell.ctx.searchResults.length)
            }
            if (ok && step === 44) {
                shell.ctx.peerQuery = ""
                shell.ctx.searchOpen = false
                console.error("HARNESSSEARCH q=cleared n=" + shell.ctx.searchResults.length)
            }
            if (ok && step === 46) {
                shell.ctx.selectedTab = 1
                const ax = shell.ctx.activeExitPeer()
                console.error("HARNESSTAB exit cands=" + shell.ctx.exitNodes.length
                    + " active=" + (ax ? ax.HostName : "none"))
            }
            if (ok && step === 62) {
                shell.ctx.selectedTab = 0
                console.error("HARNESSTAB connection prefs=" + (shell.ctx.gatePrefs !== "" ? "parsed" : "empty")
                    + " health=" + (shell.ctx.health || []).length)
            }
            if (ok && step === 66) {
                console.error("HARNESSGEO t1 " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
            if (ok && step === 78) {
                shell.ctx.selectedTab = 2
                console.error("HARNESSTAB machines pre-detail")
            }
            if (ok && step === 80) {
                const list = shell.ctx.onlinePeers.length > 0 ? shell.ctx.onlinePeers : shell.ctx.peers
                machinesTab.openDetail(list[0])
                console.error("HARNESSDETAIL open=" + (shell.ctx.detailPeer ? shell.ctx.detailPeer.HostName : "FAIL"))
            }
            if (ok && step === 88) {
                console.error("HARNESSGEO t2 " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
            if (step === 96) {
                machinesTab.closeDetail()
                console.error("HARNESSDETAIL open=" + (shell.ctx.detailPeer ? "STILL" : "closed"))
            }
            if (step === 98) {
                console.error("HARNESSGEO t0b " + Math.round(shell.width) + "x" + Math.round(shell.height))
            }
        }
    }

"""
s = s.replace(anchor, drv + anchor, 1)

# instrumentation: log popup visibility flips + tab truth each driver step
vis_anchor = "    onVisibleChanged: {"
assert vis_anchor in s
s = s.replace(vis_anchor,
    '    onVisibleChanged: { console.error("HARNESSVIS " + (visible ? "true" : "false"))', 1)
step_anchor = "            if (step === 4) {"
assert step_anchor in s
s = s.replace(step_anchor,
    '            if (step === 6 || step === 8) {'
    ' console.error("HARNESSGEO2 shell=" + Math.round(shell.width) + "x" + Math.round(shell.height)'
    ' + " machinesTab=" + Math.round(machinesTab.width) + "x" + Math.round(machinesTab.height)'
    ' + " stack=" + Math.round(machinesTab.stackDepth())'
    ' + " at=" + JSON.stringify(shell.mapToGlobal(0, 0))'
    ' + " dlg=" + (shell.Window.window ? Math.round(shell.Window.window.width) + "x" + Math.round(shell.Window.window.height) : "none")'
    ' + " lane=" + (machinesTab.laneH ? Math.round(machinesTab.laneH()) : -1));'
    ' const col = shell.children[0]; let dump = "";'
    ' for (let i = 0; i < col.children.length; i++) { const c = col.children[i];'
    '   dump += " [" + i + "] h=" + Math.round(c.height) + " vis=" + c.visible + " imp=" + Math.round(c.implicitHeight) + " fillH=" + c.Layout.fillHeight + " prefH=" + c.Layout.preferredHeight; }'
    ' console.error("HARNESSCOL n=" + col.children.length + " colH=" + Math.round(col.height) + dump) }\n'
    + step_anchor, 1)
peers_path = p.replace("PopupShell.qml", "MachinesTab.qml")
pt = open(peers_path).read()
assert "function stackDepth()" not in pt
pt = pt.replace("    function searchable() {",
    "    function stackDepth() { return stack.depth }\n    function laneH() { return lane ? lane.height : -1 }\n"
    "    function laneScrollBottom() { if (lane && lane.contentItem) lane.contentItem.contentY = lane.contentItem.contentHeight }\n"
    "    function searchable() {", 1)
open(peers_path, "w").write(pt)
open(p, 'w').write(s); print("v8 driver in")
PY
# injection failure must abort loudly — a driverless run produces empty
# asserts that look green (2026-11-08 v8h/v8i incident).
grep -aq "HARNESSSTEP" "$PKG/contents/ui/PopupShell.qml" || {
  echo "FATAL: driver injection failed (HARNESSSTEP absent) — aborting"
  exit 9
}

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
# Popup opens 12 s after applet load (post-status; running=true ⇒
# MACHINES landing). fullRepresentation (and the driver Timer) are
# CREATED at open — t0 = open = add+12 s; step N wall = add + 12 + N/2.
# Windows (step): settle+t0 4-12 · expand 14-17 · search q=host03 26-40
# · zzz 40 · cleared 44 · exit 46 · t1 66 · connection 62 · machines 78
# · detail 80 · t2 88 · closeDetail 96 · t0b 98. Shots launch at add+
# 15/21/27/38/46/55; spectacle latency 1-3 s lands shutters in-window.
sleep 15
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-machines-s$SCALE$LIGHT.png
echo "SHOTDONE-machines $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 6
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-offexp-s$SCALE$LIGHT.png
echo "SHOTDONE-offexp $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 6
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-search-s$SCALE$LIGHT.png
echo "SHOTDONE-search $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 11
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-exittab-s$SCALE$LIGHT.png
echo "SHOTDONE-exittab $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 8
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-connection-s$SCALE$LIGHT.png
echo "SHOTDONE-connection $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 9
spectacle -b -n -o $ROOT/shots/$TAG-$FIXTURE-detail-s$SCALE$LIGHT.png
echo "SHOTDONE-detail $(date +%s.%N)" >> $ROOT/shot-times.log
sleep 10

kill $SHELL_PID 2>/dev/null; sleep 2; kill $KWIN_PID 2>/dev/null
echo "CKPT-CLEANUP-DONE"

# console.error from applet QML lands in the USER JOURNAL, never the
# shell's stderr redirect (0 bytes is normal for a healthy shell) —
# skill law. Harvest the journal for this shell pid, then grep THAT.
LOG=$ROOT/shell-tailfin-v3-$FIXTURE-s$SCALE$LIGHT.log
journalctl --user _PID=$SHELL_PID --no-pager > "$ROOT/harness-journal-$TAG-$FIXTURE.log" 2>/dev/null || true
LOG=$ROOT/harness-journal-$TAG-$FIXTURE.log
echo "===ASSERTS==="
# A1: frame is fixed — one unique geometry across PEERS→EXIT→DEVICE→detail.
G=$(grep -ao "HARNESSGEO t[0-9b]* [0-9]*x[0-9]*" "$LOG" | awk '{print $3}' | sort -u | wc -l)
echo "GEO-UNIQUE=$G (want 1)"
grep -ao "HARNESSGEO t[0-9b]* [0-9]*x[0-9]*" "$LOG"
# A2: count-sum invariant on the PEERS tab
SUMBAD=$(grep -ac "sum=BAD" "$LOG" || true); echo "SUM-BAD=$SUMBAD (want 0)"
grep -ao "HARNESSV7 tab=.*sum=ok" "$LOG" | tail -2
# A3: offline toggle fired (norm fixtures)
grep -a "HARNESSTOGGLE" "$LOG" || echo "TOGGLE-ABSENT (ok for 0-offline fixtures)"
# A4: search semantics — host03 -> 1, host+zzz -> 0, cleared -> sections
grep -ao "HARNESSSEARCH q=[a-z0-9]* n=[0-9]*" "$LOG"
# A5: tab sequencing — exit candidates counted, device facts probed
grep -ao "HARNESSTAB [a-z]* .*" "$LOG"
# A6: detail push/pop
grep -ao "HARNESSDETAIL open=[A-Za-z0-9-]*" "$LOG"
# gate/edge verdict
grep -ao "HARNESSGate .*" "$LOG" || echo "GATE-LINE-MISSING"
# A7: no QML runtime errors of the classes we've been burned by
QMLERR=$(grep -ac "is not defined\|Cannot read\|ReferenceError\|TypeError\|Invalid write\|Invalid read\|Syntax error" "$LOG" || true)
echo "QML-ERR=$QMLERR (want 0)"
grep -a "is not defined\|Cannot read\|ReferenceError\|TypeError" "$LOG" | sort -u | head -5
echo "===SHOTS==="
ls -la $ROOT/shots/$TAG-$FIXTURE-*.png 2>/dev/null
# A9: stub argv allowlist (status / debug prefs / id -un only)
BAD=$(grep -avE "^tailscale (status --json|debug prefs|set --exit-node|up|down)$" "$STUBLOG" | grep -ac "^tailscale" || true)
echo "STUB-ARGV-BAD=$BAD (want 0)"
echo "STUB-ARGV:"; cat "$STUBLOG"
# A11: no frozen popupWidth/Height keys on the applet
grep -c "popupWidth\|popupHeight" "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | sed 's/^/POPUPKEYS=/'
echo "DONE-$FIXTURE-s$SCALE$LIGHT"
# Teardown (2026-11-08 incident fix): the PGID nuke is BANNED — it killed
# the invoking agent's wrapper (terminal -15 noise), which pushed agents
# into pattern-killing "strays" — and a pattern kill TERMs the REAL shell
# (argv-identical `plasmashell --no-respawn`; SIGTERM counts as a clean
# exit so plasma-plasmashell.service does NOT auto-restart; Greg's panel
# died this way twice on 2026-11-08). Kill ONLY processes whose OWN
# environ says they belong to this harness — never by name/argv/pgid:
for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  [ "$pid" = "$$" ] && continue
  readlink "$d/exe" 2>/dev/null | grep -q dbus-daemon && continue
  tr "\0" "\n" < "$d/environ" 2>/dev/null | grep -q "^HOME=$ROOT/home$" || continue
  kill "$pid" 2>/dev/null
done
exit 0
