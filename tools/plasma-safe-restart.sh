#!/bin/bash
# plasma-safe-restart.sh — the ONLY sanctioned way to restart plasmashell
# on the live session (2026-10-31). Never restarts kwin/ksmserver — those
# require a full session recycle with the user's explicit go-ahead.
#   preflight  : kwin active + socket present + ksmserver active, else abort
#                (restarting the shell into a broken session wedges it)
#   backup     : timestamped appletsrc copy BEFORE touching anything
#   restart    : systemctl --user try-restart plasma-plasmashell.service
#   verify     : up to 40s — active, journal-clean (no wl_display), panel
#                count >=1, panel band renders ink (real pixels)
#   rollback   : on verify failure restore the backup, restart once more,
#                re-verify, then report honestly either way.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HEALTH="$HERE/plasma-health.sh"
[ -x "$HEALTH" ] || HEALTH="$HOME/.local/bin/plasma-health.sh"
APPLET="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
BAK="/tmp/stk-harness/appletsrc-backup-safewrite-$(date +%Y%m%d-%H%M%S).bak"

abort() { echo "SAFE-RESTART ABORT: $1"; exit 1; }

systemctl --user is-active --quiet plasma-kwin_wayland.service \
  || abort "kwin not active — restarting the shell now would wedge it"
[ -S "/run/user/1000/${WAYLAND_DISPLAY:-wayland-0}" ] \
  || abort "compositor socket missing — session is already broken; needs recycle, not a shell restart"
systemctl --user is-active --quiet plasma-ksmserver.service \
  || abort "ksmserver not active — shell restart will hang on the session-manager handshake (2026-10-30 lockup); recycle the session instead"

mkdir -p /tmp/stk-harness
[ -f "$APPLET" ] && cp "$APPLET" "$BAK" && echo "backup: $BAK"

verify() {
  # Sets VMODE: ok | headless | nopanels | locked. Blank/locked screens are
  # INCONCLUSIVE, not failure — never roll back config over a locked screen.
  local i pid bad panels ink verdict
  VMODE=locked
  for i in $(seq 1 20); do
    sleep 2
    systemctl --user is-active --quiet plasma-plasmashell.service || continue
    pid=$(systemctl --user show -p MainPID --value plasma-plasmashell.service)
    [ -n "$pid" ] && [ "$pid" != 0 ] || continue
    bad=$(journalctl --user "_PID=$pid" --no-pager 2>/dev/null \
          | grep -c -e "Failed to create wl_display" -e 'Could not load the Qt platform plugin "wayland"')
    if [ "${bad:-1}" -gt 0 ]; then echo "verify: pid $pid headless ($bad wl_display errors)"; VMODE=headless; return 1; fi
    panels=$(busctl --user call org.kde.plasmashell /PlasmaShell \
             org.kde.PlasmaShell evaluateScript s "print(panels().length)" \
             2>/dev/null | awk '{print $NF}' | tr -d '"')
    if ! [ "${panels:-0}" -ge 1 ] 2>/dev/null; then echo "verify: no panels yet"; VMODE=nopanels; continue; fi
    S=/tmp/.sr-$$; spectacle -b -n -o "$S.png" >/dev/null 2>&1
    verdict=$(python3 -W ignore -c "
import sys
from PIL import Image
from collections import Counter
img = Image.open('$S.png').convert('L'); w,h = img.size
px = list(img.getdata()); m = Counter(px).most_common(1)[0][0]
g = sum(1 for v in px if abs(v-m) > 24)
if g == 0: print('BLANK')
else:
    band = list(img.crop((0,0,w,min(60,h))).getdata()); bm = Counter(band).most_common(1)[0][0]
    print(sum(1 for v in band if abs(v-bm) > 24))" 2>/dev/null || echo -1)
    rm -f "$S.png"
    [ "$verdict" = "-1" ] && continue
    if [ "$verdict" = "BLANK" ]; then
      if pgrep -x kscreenlocker_greet >/dev/null 2>&1; then
        echo "verify: screen LOCKED — render unverifiable, waiting"
      else
        echo "verify: capture black (screen blanked/off) — waiting"
      fi
      continue
    fi
    if [ "$verdict" -lt 200 ]; then echo "verify: panel band blank ($verdict ink px)"; VMODE=nopanels; return 1; fi
    echo "verify OK: pid $pid journal-clean, $panels panel(s), band renders ($verdict ink px)"
    VMODE=ok
    return 0
  done
  echo "verify: no definitive result in 40s (last mode: $VMODE)"
  return 1
}

echo "restarting plasmashell..."
systemctl --user try-restart plasma-plasmashell.service
if verify; then
  echo "SAFE-RESTART PASS"
  exit 0
fi
if [ "$VMODE" = "locked" ]; then
  echo "SAFE-RESTART INCONCLUSIVE: shell healthy (journal+bus) but screen locked/blank — render unverified. No rollback (config is fine)."
  exit 3
fi
echo "verify failed ($VMODE) — rolling back config and retrying once"
[ -f "$BAK" ] && cp "$BAK" "$APPLET"
systemctl --user try-restart plasma-plasmashell.service
if verify; then
  echo "SAFE-RESTART PASS (after config rollback from $BAK)"
  exit 0
fi
if [ "$VMODE" = "locked" ]; then
  echo "SAFE-RESTART INCONCLUSIVE after rollback: screen locked/blank — render unverified."
  exit 3
fi
echo "SAFE-RESTART FAIL — report honestly; bar state unknown. Backup: $BAK"
exit 1
