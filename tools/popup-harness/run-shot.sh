#!/bin/bash
# run-shot.sh — generic full-desktop capture for any PlasmoidItem-rooted widget.
# Two frames in a nested virtual Plasma session (never the user's desktop):
#   <tag>-chip.png    panel with the chip only (popup closed)
#   <tag>-popup.png   same frame with the popup open (auto-opened by an injected Timer)
#   <tag>-popup2.png  +15s later (network / probe data landed)
# Usage: ./run-shot.sh <plugin-id> <repo-subdir> <tag> [open-ms]
# e.g.  ./run-shot.sh com.gdeyoung.plasma.weatherx plasma-weatherx weatherx 12000
# Env: SCALE (1|2), NOWALL (1 = keep the stock wallpaper),
#      SEEDCFG=<file>  key=value lines written into the widget's applet config (demo inventory),
#      PATCH=<file>    'file<TAB>literal<TAB>replacement' lines applied to the COPIED package only,
#      STUBDIR=<dir>    prepended to PATH for the nested session (fixture `tailscale` etc.).
# Same isolation law as run-timepiece.sh: private XDG_RUNTIME_DIR, harness HOME
# exported BEFORE kwin, unique socket, tracked-PID + environ-gated teardown.
set -u
ID="${1:?plugin id}"; SUB="${2:?repo subdir}"; TAG="${3:?tag}"; OPEN_MS="${4:-12000}"
SCALE="${SCALE:-1}"
ROOT=/tmp/stk-harness
export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
if [ -z "${HARNESS_RT_ISOLATED:-}" ]; then
  RT="$ROOT/run"; mkdir -p "$RT"; chmod 700 "$RT" 2>/dev/null || true
  exec dbus-run-session env HARNESS_RT_ISOLATED=1 XDG_RUNTIME_DIR="$RT" \
      HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
      XDG_CACHE_HOME="$XDG_CACHE_HOME" QT_QPA_PLATFORM=wayland \
      LIBGL_ALWAYS_SOFTWARE=1 bash "$0" "$@"
fi
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SOCK="wayland-s-$TAG-$$"
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1
kwin_wayland --virtual --no-lockscreen --socket "$SOCK" $([ "$SCALE" = "2" ] && echo "--width 5120 --height 2880" || echo "--width 2560 --height 1440") & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/$SOCK" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY="$SOCK"
[ -n "${STUBDIR:-}" ] && export PATH="$STUBDIR:$PATH"   # fixture binaries (e.g. tailfin stub) shadow the real ones in this session only
rm -rf "$XDG_CONFIG_HOME/plasma"*   # fresh panel config = deterministic single instance
cp "$(dirname "$0")/appletsrc.template" "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc"   # stock panel + flat dark wallpaper
if [ -n "${SEEDCFG:-}" ]; then
python3 - "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc" "$ID" "$SEEDCFG" <<'PY'
import sys, re
cfg = open(sys.argv[1]).read(); kv = [l.rstrip("\n").split("=", 1) for l in open(sys.argv[3]) if "=" in l and not l.startswith("#")]
grp = next((l.split("\t", 1)[1].strip() for l in open(sys.argv[3]) if l.startswith("#group\t")), "General")   # main.xml <group name>; Plasma nests keys under [Configuration][<group>]
block = "[Containments][2][Applets][90]\nimmutability=1\nplugin=" + sys.argv[2] + "\n\n[Containments][2][Applets][90][Configuration][" + grp + "]\n" + "".join(k + "=" + v.replace("\\", "\\\\").replace("\n", "\\n") + "\n" for k, v in kv)
cfg = re.sub(r"(AppletOrder=[^\n]*89;?)", lambda m: m.group(1).rstrip(";") + ";90\n", cfg, count=1) if re.search(r"AppletOrder=[^\n]*", cfg) else cfg
cfg = cfg.replace("AppletOrder=3;4;5;6;7;23;24", "AppletOrder=3;4;5;6;7;23;24;90")
open(sys.argv[1], "w").write(cfg + "\n" + block); print("CKPT-SEED", len(kv), "keys")
PY
fi
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
cp /usr/share/color-schemes/BreezeDark.colors "$XDG_CONFIG_HOME/kdeglobals" 2>/dev/null   # match the live desktop's scheme (fresh HOME defaults to Light)
python3 -c "from PIL import Image; Image.new('RGB',(16,16),(16,20,27)).save('$HOME/.local/share/wall-dark.png')"  # flat #10141b wallpaper
/usr/libexec/kactivitymanagerd >/dev/null 2>&1 &   # nested plasmashell aborts its shell load without it (not on PATH)
for i in $(seq 1 20); do busctl --address="$DBUS_SESSION_BUS_ADDRESS" status org.kde.ActivityManager >/dev/null 2>&1 && break; sleep 0.5; done

PKG="$XDG_DATA_HOME/plasma/plasmoids/$ID"
mkdir -p "$PKG" && cp -r "$REPO/$SUB/." "$PKG/" && test -f "$PKG/metadata.json" && echo "CKPT-PKG-OK $ID" || { echo "CKPT-PKG-FAIL $ID"; exit 2; }

if [ -n "${PATCH:-}" ]; then
python3 - "$PKG" "$PATCH" <<'PY'
import sys, re, os
pkg, pf = sys.argv[1], sys.argv[2]
for l in open(pf):
    parts = l.rstrip("\n").split("\t")
    if len(parts) != 3 or parts[0].startswith("#"): continue
    f = os.path.join(pkg, parts[0]); s = open(f).read(); s2 = s.replace(parts[1], parts[2], 1)
    assert s2 != s, "PATCH no-op: " + parts[0] + " :: " + parts[1]
    open(f, "w").write(s2); print("CKPT-PATCH", parts[0])
PY
fi

MAIN="$PKG/contents/ui/main.qml"
python3 - "$MAIN" "$OPEN_MS" <<'PY' || exit 3
import sys, re
p, ms = sys.argv[1], sys.argv[2]; s = open(p).read()
hook = f"\n    // HARNESS-ONLY: delayed auto-open (PlasmoidItem.expanded — the real lever)\n    Timer {{ id: harnessOpen; interval: {ms}; running: true; onTriggered: root.expanded = true }}\n"
assert "harnessOpen" not in s, "stale hook present"
m = re.search(r"PlasmoidItem\s*\{(.{0,400}?)id:\s*root[^\n]*\n", s, re.S)
assert m, "PlasmoidItem id: root not found"
s = s[:m.end()] + hook + s[m.end():]
open(p, "w").write(s); print("CKPT-HOOK-OK")
PY

cat > "$ROOT/add-$TAG.js" <<JS
var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].addWidget("$ID"); print("HARNESS-ADD " + ps[i].id); }
JS
cat > "$ROOT/wall-$TAG.js" <<'JS'
var ds = desktops(); for (var i = 0; i < ds.length; i++) {
  ds[i].wallpaperPlugin = "org.kde.image";
  ds[i].currentConfigGroup = "General"; ds[i].writeConfig("Image", "/tmp/stk-harness/home/.local/share/wall-dark.png");
  ds[i].writeConfig("FillMode", "0"); ds[i].reloadConfig();
}
JS
mkdir -p "$ROOT/shots/$TAG"
echo "CKPT-START $TAG scale=$SCALE open=${OPEN_MS}ms"
QT_SCALE_FACTOR=$SCALE plasmashell --no-respawn > "$ROOT/shell-$TAG.log" 2>&1 & SHELL_PID=$!
sleep 18
B="busctl --address=$DBUS_SESSION_BUS_ADDRESS"
[ -z "${NOWALL:-}" ] && $B call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat "$ROOT/wall-$TAG.js")" >/dev/null 2>&1
[ -z "${SEEDCFG:-}" ] && $B call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat "$ROOT/add-$TAG.js")" 2>&1 | head -1
NP=$($B call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "print(panels().length)" 2>/dev/null | awk '{print $NF}' | tr -d '"')
echo "CKPT-PANELS $NP"
sleep 7
timeout 20 spectacle -b -n -o "$ROOT/shots/$TAG/$TAG-chip.png" && echo "SHOT chip"
OPEN_S=$(( OPEN_MS / 1000 - 7 + 4 )); [ "$OPEN_S" -lt 6 ] && OPEN_S=6
sleep "$OPEN_S"
timeout 20 spectacle -b -n -o "$ROOT/shots/$TAG/$TAG-popup.png" && echo "SHOT popup"
sleep 15
timeout 20 spectacle -b -n -o "$ROOT/shots/$TAG/$TAG-popup2.png" && echo "SHOT popup2"
echo "HARNESS-LOG-BEGIN"
journalctl --user _PID=$SHELL_PID --no-pager 2>/dev/null | grep -aE "error when loading|TypeError|ReferenceError|is not a type|Cannot read" | head -5
grep -aE "error when loading|TypeError|ReferenceError|is not a type" "$ROOT/shell-$TAG.log" | head -3
echo "HARNESS-LOG-END"

kill $SHELL_PID $KWIN_PID 2>/dev/null
sleep 2
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  [ -r "/proc/$pid/cmdline" ] || continue
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  case "$cmd" in
    *"plasmashell --no-respawn"*|*"kwin_wayland --virtual"*|*kactivitymanagerd*) ;;
    *) continue ;;
  esac
  tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "^HOME=$ROOT/home$" || continue
  kill -9 "$pid" 2>/dev/null
done
echo "DONE-$TAG"
