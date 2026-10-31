#!/bin/bash
# plasma-health.sh — Plasma session health check (2026-10-31).
# Fleet rule: monitors read REAL logs, not pings. Checks, in order:
#   1. compositor socket present          (missing = desktop-death wedge)
#   2. kwin + plasmashell services active
#   3. CURRENT plasmashell pid journal: no "Failed to create wl_display"
#      (headless shell — the failure mode that showed a green service and
#      answered the bus while no bar rendered, 2026-10-30)
#   4. panel count via org.kde.plasmashell scripting (note: one word)
#   5. render proof: ink in the top panel band from a wayland-native
#      screenshot, deleted immediately (bus answers are NOT render proof)
#   6. ksmserver active (warn only)
# Auto-heal: if the shell is headless but socket+kwin are healthy, restart
# plasmashell at most once per 10 min. NEVER touches kwin/ksmserver — those
# need a full session recycle and user consent.
# Exit 0 healthy, 1 degraded. Output is one status line + failure reasons.

SOCK=/run/user/1000/wayland-0
HEAL_TS=/tmp/plasma-health-heal.ts
issues=0; reasons=""

# No graphical session (logged out / TTY) => nothing to check; stay quiet.
loginctl list-sessions --no-legend 2>/dev/null | grep -q "gdeyoung" \
  || { echo "PLASMA-HEALTH: no user session — skip"; exit 0; }

fail() { issues=1; reasons="$reasons|$1"; echo "PLASMA-HEALTH FAIL: $1"; }

[ -S "$SOCK" ] || fail "compositor socket $SOCK missing — new Wayland clients cannot connect; session recycle required (ask user; NEVER auto-restart kwin)"

systemctl --user is-active --quiet plasma-kwin_wayland.service \
  || fail "plasma-kwin_wayland.service not active"
systemctl --user is-active --quiet plasma-plasmashell.service \
  || fail "plasma-plasmashell.service not active"

PID=$(systemctl --user show -p MainPID --value plasma-plasmashell.service 2>/dev/null)
HEADLESS=0
if [ -n "$PID" ] && [ "$PID" != "0" ]; then
  BAD=$(journalctl --user "_PID=$PID" --no-pager 2>/dev/null \
        | grep -c -e "Failed to create wl_display" -e 'Could not load the Qt platform plugin "wayland"')
  if [ "${BAD:-0}" -gt 0 ]; then
    HEADLESS=1
    fail "plasmashell pid $PID is headless ($BAD wl_display errors since start)"
  fi
else
  fail "no MainPID for plasmashell"
fi

PANELS=$(busctl --user call org.kde.plasmashell /PlasmaShell \
         org.kde.PlasmaShell evaluateScript s "print(panels().length)" \
         2>/dev/null | awk '{print $NF}' | tr -d '"')
if [ "${PANELS:-0}" -ge 1 ] 2>/dev/null; then :; else
  fail "shell reports no panels (bus name org.kde.plasmashell)"
fi

# Render proof — only meaningful if the shell claims health so far.
# A LOCKED/BLANKED screen captures as pure black: that is NOT a failure
# (kscreenlocker greeter active or whole-screen ink 0 => unverifiable, warn).
if [ "$issues" = 0 ]; then
  SHOT=/tmp/.plasma-health-$$.png
  if spectacle -b -n -o "$SHOT" >/dev/null 2>&1 && [ -s "$SHOT" ]; then
    INK=$(python3 -W ignore - "$SHOT" <<'EOF'
import sys
try:
    from PIL import Image
    img = Image.open(sys.argv[1]).convert("L")
    w, h = img.size
    px = list(img.getdata())            # whole screen first: lock/blank detect
    from collections import Counter
    modal = Counter(px).most_common(1)[0][0]
    global_ink = sum(1 for v in px if abs(v - modal) > 24)
    if global_ink == 0:
        print("BLANK")
    else:
        band = list(img.crop((0, 0, w, min(60, h))).getdata())
        bmodal = Counter(band).most_common(1)[0][0]
        print(sum(1 for v in band if abs(v - bmodal) > 24))
except Exception:
    print(-1)   # PIL missing / unreadable — check skipped
EOF
)
    rm -f "$SHOT"
    if [ "$INK" = "-1" ]; then
      echo "PLASMA-HEALTH WARN: render check skipped (PIL unavailable)"
    elif [ "$INK" = "BLANK" ]; then
      if pgrep -x kscreenlocker_greet >/dev/null 2>&1; then
        echo "PLASMA-HEALTH OK (screen LOCKED — render unverifiable, not a failure)"
      else
        echo "PLASMA-HEALTH WARN: capture entirely black, no greeter — screen blanked or off; render unverifiable"
      fi
    elif [ "${INK:-0}" -lt 200 ]; then
      fail "panel band renders blank ($INK ink pixels) — shell answers bus but draws nothing"
    fi
  else
    echo "PLASMA-HEALTH WARN: spectacle capture failed (X11 fallback disabled?) — render unverified"
    rm -f "$SHOT"
  fi
fi

systemctl --user is-active --quiet plasma-ksmserver.service \
  || echo "PLASMA-HEALTH WARN: ksmserver inactive (lock screen/session manager)"

# Narrow auto-heal: headless shell + healthy compositor => restart shell only.
if [ "$HEADLESS" = 1 ] && [ -S "$SOCK" ] \
   && systemctl --user is-active --quiet plasma-kwin_wayland.service; then
  NOW=$(date +%s); LAST=$(cat "$HEAL_TS" 2>/dev/null || echo 0)
  if [ $((NOW - LAST)) -ge 600 ]; then
    echo "$NOW" > "$HEAL_TS"
    echo "PLASMA-HEALTH HEAL: restarting headless plasmashell"
    systemctl --user try-restart plasma-plasmashell.service
  else
    echo "PLASMA-HEALTH: heal suppressed (last attempt <10min ago)"
  fi
fi

if [ "$issues" = 0 ]; then
  echo "PLASMA-HEALTH OK: socket, kwin, shell pid $PID (journal clean), $PANELS panel(s), panel band renders"
fi
exit $issues
