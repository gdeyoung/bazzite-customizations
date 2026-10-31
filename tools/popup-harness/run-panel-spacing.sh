#!/usr/bin/env bash
# run-bar2.sh — measure live-panel trio spacing by pre-seeding the harness
# with the REAL appletsrc and varying padWidth between shell restarts.
# Runtime writeConfig never reaches QML in harness mode; config LOADS at
# startup, so: sed pads -> launch shell -> shoot N frames -> kill, per combo.
# Env: COMBOS="6:16 16:16" (padA:padB), TAG, FRAMES (per combo).
set -u
ROOT=/tmp/stk-harness
TAG="${TAG:-bar2}"
COMBOS="${COMBOS:-6:16}"
FRAMES="${FRAMES:-3}"
OUT=$ROOT/shots; mkdir -p "$OUT" "$ROOT/home"
LIVE_APPLET=/var/home/gdeyoung/.config/plasma-org.kde.plasma.desktop-appletsrc

export HOME=$ROOT/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 XDG_RUNTIME_DIR=/run/user/1000

teardown() {
  [ -n "${SHELL_PID:-}" ] && kill "$SHELL_PID" 2>/dev/null
  [ -n "${KWIN_PID:-}" ] && kill "$KWIN_PID" 2>/dev/null
  sleep 2
  for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    [ -r "/proc/$pid/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmd" in *plasmashell*|*kwin_wayland*|*spectacle*) ;; *) continue ;; esac
    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q "^HOME=$ROOT/home$" || continue
    kill -9 "$pid" 2>/dev/null
  done
}
trap teardown EXIT

kwin_wayland --virtual --no-lockscreen --width 2560 --height 1440 \
  --socket wayland-hbar > "$ROOT/kwin-$TAG.log" 2>&1 & KWIN_PID=$!
for i in $(seq 1 40); do [ -S "$XDG_RUNTIME_DIR/wayland-hbar" ] && break; sleep 0.5; done
[ -S "$XDG_RUNTIME_DIR/wayland-hbar" ] || { echo "CKPT-KWIN-FAIL"; exit 1; }
export WAYLAND_DISPLAY=wayland-hbar

for p in plasma-stocktick plasma-timepiece plasma-weatherx plasma-panelpad; do
  D="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.${p#plasma-}"
  rm -rf "$D"; mkdir -p "$D" && cp -r "/var/home/gdeyoung/work/bazzite-customizations/$p/"* "$D/"
done
echo "CKPT-PKG-OK"

B="busctl --address=$DBUS_SESSION_BUS_ADDRESS"

for combo in $COMBOS; do
  PA=${combo%%:*}; PB=${combo##*:}
  SLUG="${PA}x${PB}"
  rm -rf "$XDG_CONFIG_HOME/plasma"*
  cp "$LIVE_APPLET" "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc"
  /usr/bin/python3 - "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc" "$PA" "$PB" <<'PYEOF'
import re, sys
path, pa, pb = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
ids = re.findall(r'\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]\n(?:[^\[]*\n)*?plugin=com\.gdeyoung\.plasma\.panelpad', s)
assert len(ids) == 2, f"expected 2 panelpads in live config, found {len(ids)}"
for i, (cont, aid) in enumerate(ids):
    val = pa if i == 0 else pb
    for suffix in ("", "[General]"):
        sec = f"[Containments][{cont}][Applets][{aid}][Configuration]{suffix}]"
        m = re.search(r'(' + re.escape(sec) + r']\n)((?:[^\[]*?\n)*?)(?=\n*\[|\Z)', s)
        if m:
            body = m.group(2)
            if re.search(r'^padWidth=', body, re.M):
                body = re.sub(r'^padWidth=.*$', f'padWidth={val}', body, flags=re.M)
            else:
                body = body + f'padWidth={val}\n'
            s = s[:m.start(2)] + body + s[m.end(2):]
        else:
            s += f"\n{sec}]\npadWidth={val}\n"
open(path, 'w').write(s)
print(f"pads: {ids[0][1]}={pa} {ids[1][1]}={pb}")
PYEOF
  plasmashell --no-respawn > "$ROOT/shell-$TAG-$SLUG.log" 2>&1 & SHELL_PID=$!
  for i in $(seq 1 60); do $B status org.kde.plasmashell >/dev/null 2>&1 && break; sleep 1; done
  $B status org.kde.plasmashell >/dev/null 2>&1 || { echo "CKPT-SHELL-FAIL $SLUG"; continue; }
  sleep 14   # fetches + one rotation settle
  for f in $(seq 1 "$FRAMES"); do
    spectacle -b -n -o "$OUT/bar-$TAG-$SLUG-f${f}.png" 2>/dev/null
    sleep 6
  done
  echo "SHOT-$SLUG"
  kill "$SHELL_PID" 2>/dev/null; wait "$SHELL_PID" 2>/dev/null
  sleep 2
done
echo "DONE-$TAG"
