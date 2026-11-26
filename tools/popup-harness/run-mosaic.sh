#!/bin/bash
# run-mosaic.sh — plasma-mosaic v0.1 popup harness gate.
# Env: SCALE (1|2), TAG. Runs the REAL vendored CLI against a seeded
# harness HOME (fixture snapshot — no scan is ever fired; first real scan
# is the user at the desk). Asserts HARNESS probe lines + heartbeat file
# + journal cleanliness, and captures 5 popup states + the panel chip.
set -u
SCALE="${SCALE:-1}"; TAG="${TAG:-ui}"
ROOT=/tmp/stk-harness
REPO=/var/home/gdeyoung/work/bazzite-customizations
STATE_TAG="mosaic-$TAG-s$SCALE"

# --- 2026-10-31 isolation: private XDG_RUNTIME_DIR, harness HOME exported
# BEFORE kwin launch, named socket, self-wrapping re-exec.
export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
if [ -z "${HARNESS_RT_ISOLATED:-}" ]; then
  RT="$ROOT/run"; mkdir -p "$RT"; chmod 700 "$RT" 2>/dev/null || true
  mkdir -p "$ROOT/shots"
  exec dbus-run-session env HARNESS_RT_ISOLATED=1 XDG_RUNTIME_DIR="$RT" \
      HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
      XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_STATE_HOME="$HOME/.local/state" \
      TMPDIR=/var/home/gdeyoung/.hermes/cache/scratch \
      QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 bash "$0" "$@"
fi
SOCK="wayland-m$$"
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1

# --- fixture: deterministic snapshot the CLI `snapshot` op will serve -----
# 12 apps; Brave-ish spread across categories; one deep-scan-style app with
# breakdown; excluded possible/shared rows; partial app; unmapped app;
# limited=true (chip shows >=); one warning.
mkdir -p "$XDG_STATE_HOME/omarchy/mosaic"
python3 - "$XDG_STATE_HOME/omarchy/mosaic/plasma-snapshot.json" <<'PY'
import json, sys, time

GB, MB = 10**9, 10**6
def path(p, cat, conf, nbytes, status="complete", **extra):
    d = {"path": p, "label": p.rstrip("/").split("/")[-1], "category": cat,
         "confidence": conf, "reason": "namespace" if conf == "known" else "resemblance",
         "evidence": "install record: %s" % p.split("/")[-2],
         "source": "flatpak" if ".var/app" in p else "desktop", "bytes": nbytes, "status": status}
    d.update(extra)
    return d

apps = []
def app(aid, name, icon, paths, status="complete"):
    cats = {"config": 0, "data": 0, "cache": 0, "state": 0}
    total = 0
    for p in paths:
        if p["confidence"] == "known" and p["bytes"] is not None:
            cats[p["category"]] += p["bytes"]; total += p["bytes"]
    apps.append({"id": aid, "name": name, "icon": icon, "status": status,
                 "scannedAt": 1, "paths": paths, "categories": cats, "mappedBytes": total})

H = "/var/home/harness"
app("com.test.Brave", "Brave", "web-browser", [
    path(H+"/.var/app/com.test.Brave/config/BraveSoftware", "config", "known", 13.6*GB),
    path(H+"/.var/app/com.test.Brave/cache", "cache", "known", 1.21*GB),
    path(H+"/.var/app/com.test.Brave/data", "data", "known", 0.29*GB),
    path(H+"/.var/app/com.test.Brave/.local/state", "state", "known", 41*MB),
    path(H+"/.cache/brave-recovered", "cache", "possible", 812*MB),
])
app("com.test.Heroic", "Heroic", "applications-games", [
    path(H+"/.var/app/com.test.Heroic/data/heroic", "data", "known", 7.5*GB, status="partial"),
    path(H+"/.var/app/com.test.Heroic/config", "config", "known", 18*MB),
])
app("com.test.BigApp", "BigApp", "utilities-terminal", [
    path(H+"/.var/app/com.test.BigApp/data/big", "data", "known", 2.9*GB,
         breakdown=[{"name": "projects", "bytes": 1.4*GB, "status": "complete"},
                    {"name": "models/checkpoint-7b", "bytes": 0.9*GB, "status": "complete"},
                    {"name": "logs", "bytes": 210*MB, "status": "complete"},
                    {"name": "tmp-build", "bytes": 95*MB, "status": "failed"}],
         directBytes=0.3*GB, directFiles=12304,
         skippedCounts={"permission denied": 3}),
    path(H+"/.var/app/com.test.BigApp/config", "config", "known", 12*MB),
])
app("com.test.Mid", "Midnight", "preferences-system", [
    path(H+"/.var/app/com.test.Mid/data", "data", "known", 300*MB),
    path(H+"/.var/app/com.test.Mid/cache", "cache", "known", 44*MB),
])
app("com.test.Media", "Mediacenter", "audio-player", [
    path(H+"/.var/app/com.test.Media/data", "data", "known", 180*MB),
])
app("com.test.Mail", "Mailfeed", "mail-send", [
    path(H+"/.var/app/com.test.Mail/cache", "cache", "known", 95*MB),
    path(H+"/.var/app/com.test.Mail/config", "config", "known", 9*MB),
])
app("com.test.RustDesk", "RustDesk", "preferences-system-network", [], status="unmapped")
app("com.test.Tiny1", "TinyCalc", "accessories-calculator", [
    path(H+"/.var/app/com.test.Tiny1/config", "config", "known", 8*MB)])
app("com.test.Tiny2", "TinyNotes", "accessories-text-editor", [
    path(H+"/.var/app/com.test.Tiny2/config", "config", "known", 3*MB)])
app("com.test.Tiny3", "TinyDraw", "applications-graphics", [
    path(H+"/.var/app/com.test.Tiny3/data", "data", "known", 1*MB)])
app("com.test.Tiny4", "TinyTerm2", "utilities-terminal", [
    path(H+"/.var/app/com.test.Tiny4/state", "state", "known", 2*MB)])
app("com.test.Shared", "SharedFonts", "preferences-desktop-font", [
    path(H+"/.local/share/fonts-shared", "data", "shared", 240*MB)])

apps.sort(key=lambda a: (-a["mappedBytes"], a["name"].lower()))
cats = {"config": 0, "data": 0, "cache": 0, "state": 0}
total = completed = 0
partial = False
for a in apps:
    total += a["mappedBytes"]
    for k in cats: cats[k] += a["categories"][k]
    if a["status"] != "pending": completed += 1
    if a["status"] in ("partial", "pending"): partial = True
envelope = {"version": 1, "mode": "overview", "targetId": "", "apps": apps,
            "summary": {"bytes": total, "categories": cats,
                        "completed": completed, "partial": partial},
            "meta": {"scannedAt": int(time.time()*1000), "limited": True,
                     "warnings": ["2 locations skipped: permission denied (812 MB)"],
                     "inventoryComplete": True,
                     "paths": {"completed": 47, "total": 49}}}
open(sys.argv[1], "w").write(json.dumps(envelope, separators=(",", ":")) + "\n")
print("CKPT-FIXTURE-OK apps=%d bytes=%.2fGB" % (len(apps), total/GB))
PY
[ -s "$XDG_STATE_HOME/omarchy/mosaic/plasma-snapshot.json" ] && echo CKPT-FIXTURE-ON-DISK || echo CKPT-FIXTURE-FAIL

case "$SCALE" in
  2) W=5120; H=2880 ;;
  *) W=2560; H=1440 ;;
esac

kwin_wayland --virtual --no-lockscreen --width $W --height $H --socket "$SOCK" & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/$SOCK" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY="$SOCK"
rm -rf "$XDG_CONFIG_HOME/plasma"*
PKG="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.mosaic"
mkdir -p "$PKG"
cp -r "$REPO/plasma-mosaic/"* "$PKG/" && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK" || { echo "CKPT-PKG-FAIL"; exit 1; }
# sanity: the CLI must serve the fixture from this HOME
"$PKG/contents/scripts/mosaic" snapshot | python3 -c "import json,sys; d=json.load(sys.stdin); print('CKPT-CLI-OK apps=%d limited=%s' % (len(d['apps']), d['meta']['limited']))"

# --- injection 1: popup opens 6s after applet load (proven pattern) ---------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
hook = ("\n    Timer { interval: 6000; running: true; onTriggered: {\n"
        "        root.expanded = true\n"
        "        console.error(\"HARNESSOpen state=\" + MosaicStore.scanState\n"
        "            + \" apps=\" + (MosaicStore.snapshot ? MosaicStore.snapshot.apps.length : -1)\n"
        "            + \" bytes=\" + (MosaicStore.snapshot && MosaicStore.snapshot.summary ? MosaicStore.snapshot.summary.bytes : -1))\n"
        "    } }\n")
anchor = "    // =========================================================================\n    // COMPACT (panel chip)"
assert anchor in s, "compact anchor missing"
s = s.replace(anchor, hook + anchor, 1)
assert s.count("HARNESSOpen") == 1
open(p, 'w').write(s); print("open hook in")
PY

# --- injection 2: state driver (400ms steps; popup at t=6) ------------------
python3 - "$PKG/contents/ui/main.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
assert "harnessDrive" not in s
anchor = "    // =========================================================================\n    // COMPACT (panel chip)"
driver = """    Timer {
        id: harnessDrive
        interval: 400
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++
            if (step === 19) { console.error("HARNESSOV apps=" + MosaicStore.snapshot.apps.length
                + " mapped=" + MosaicStore.mappedCount + " max=" + MosaicStore.maxAppBytes
                + " stack=" + MosaicStore.viewStack.length) }
            else if (step === 23) { MosaicStore.searchQuery = "br"; console.error("HARNESSSearch q=br") }
            else if (step === 25) { MosaicStore.searchQuery = ""; console.error("HARNESSSearchClear") }
            else if (step === 26) { MosaicStore.pushView("app:com.test.BigApp"); console.error("HARNESSApp view=" + MosaicStore.currentView) }
            else if (step === 30) { MosaicStore.expandedPath = "/var/home/harness/.var/app/com.test.BigApp/data/big"; console.error("HARNESSExpand") }
            else if (step === 34) { MosaicStore.expandedPath = ""; MosaicStore.pushView("cat:cache"); console.error("HARNESSCat view=" + MosaicStore.currentView) }
            else if (step === 38) { console.error("HARNESSEnd stack=" + MosaicStore.viewStack.length
                + " state=" + MosaicStore.scanState) }
        }
    }

"""
s = s.replace(anchor, driver + anchor, 1)
assert s.count("harnessDrive") == 1
open(p, 'w').write(s); print("state driver in")
PY

# --- injection 3: paint probes on the harness COPY of the popup/category pages
python3 - "$PKG/contents/ui/MosaicPopup.qml" <<'PYI'
import sys
p = sys.argv[1]; s = open(p).read()
assert "harnessIdx" not in s
s = s.replace("""            currentIndex: MosaicStore.currentView.indexOf("app:") === 0 ? 1
                : MosaicStore.currentView.indexOf("cat:") === 0 ? 2 : 0""",
"""            currentIndex: MosaicStore.currentView.indexOf("app:") === 0 ? 1
                : MosaicStore.currentView.indexOf("cat:") === 0 ? 2 : 0
            onCurrentIndexChanged: console.error("HARNESSIdx " + currentIndex)""")
open(p, 'w').write(s); print("popup probe in")
PYI
python3 - "$PKG/contents/ui/CategoryPage.qml" <<'PYI'
import sys
p = sys.argv[1]; s = open(p).read()
assert "harnessCatVis" not in s
anchor2 = "    QQC2" if "    QQC2" in s else "    // exclusivity is derived"
s = s.replace(anchor2,
    '    onVisibleChanged: console.error("HARNESSCatVis " + visible)\n' + anchor2, 1)
open(p, 'w').write(s); print("cat probe in")
PYI

cat > $ROOT/add-mosaic.js <<'JS'
var ps = panels(); for (var i=0;i<ps.length;i++) ps[i].addWidget("com.gdeyoung.plasma.mosaic");
JS

echo "CKPT-START scale=$SCALE tag=$TAG"
QT_SCALE_FACTOR=$SCALE plasmashell --no-respawn > $ROOT/shell-$STATE_TAG.log 2>&1 & SHELL_PID=$!
sleep 18
timeout 10 busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-mosaic.js)" >/dev/null 2>&1 \
 || timeout 10 busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.kde.plasma.shell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat $ROOT/add-mosaic.js)" >/dev/null 2>&1
# T0 = widget added. t6 popup; t7.6 OV probe; t9.2 search; t10.4 clear+app;
# t12 expand; t13.6 category; t15.2 end.
# NOSHOTS=1 -> load-check mode: no spectacles, journal/probe evidence only
sleep 2.0  # t2: panel chip, popup closed
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-chip-s$SCALE.png; fi
sleep 6.4  # t8.4: overview
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-overview-s$SCALE.png; fi
sleep 1.2  # t9.6: search filtered ("br")
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-search-s$SCALE.png; fi
sleep 0.8  # t10.4: clearing; app view lands t10.4
sleep 0.6
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-app-s$SCALE.png; fi   # t11.0 app detail
sleep 1.4  # t12.4: expanded evidence card
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-expanded-s$SCALE.png; fi
sleep 1.2  # t13.6: category view lands
sleep 2.0
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-category-s$SCALE.png; fi  # t14.2
sleep 4.0  # settled: did the category paint land late?
if [ -z "${NOSHOTS:-}" ]; then timeout 20 spectacle -b -n -o $ROOT/shots/$TAG-settled-s$SCALE.png; fi
sleep 1.0  # t15.2 end checkpoint landed
sleep 0.8

echo "TSEQ-DONE"
echo "HARNESS-LOG-BEGIN"
grep -a "HARNESS" $ROOT/shell-$STATE_TAG.log || echo "(no HARNESS lines in shell log — check journal)"
echo "HARNESS-LOG-END"
echo "QML-ERROR-SCAN-BEGIN"
grep -aiE "mosaic.*(error|TypeError|ReferenceError|unable|non-existent|undefined)" $ROOT/shell-$STATE_TAG.log || echo "(no mosaic errors in shell log)"
echo "QML-ERROR-SCAN-END"
if [ -f /tmp/plasma-mosaic-hb.json ]; then
  echo "HEARTBEAT: $(cat /tmp/plasma-mosaic-hb.json)"
else
  echo "HEARTBEAT: MISSING"
fi
echo "DONE-$STATE_TAG"

kill $SHELL_PID 2>/dev/null; sleep 2; kill $KWIN_PID 2>/dev/null
timeout 15 bash -c '
for d in /proc/[0-9]*; do
  [ -r "$d/environ" ] || continue
  readlink "${d}/exe" 2>/dev/null | grep -q dbus-daemon && continue
  tr "\0" "\n" < "$d/environ" 2>/dev/null | grep -q "^HOME='"$ROOT"'/home$" && kill "${d#/proc/}" 2>/dev/null
done' 2>/dev/null
echo "CKPT-CLEANUP-DONE"
