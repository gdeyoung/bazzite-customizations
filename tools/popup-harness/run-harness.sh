#!/bin/bash
export QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 XDG_RUNTIME_DIR=/run/user/1000
kwin_wayland --virtual --no-lockscreen --width 2560 --height 1440 & KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY=wayland-1
export HOME=/tmp/stk-harness/home
export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
rm -rf "$XDG_CONFIG_HOME/plasma"*   # fresh panel config each run = deterministic single instance
MAIN="$XDG_DATA_HOME/plasma/plasmoids/com.gdeyoung.plasma.stocktick/contents/ui/main.qml"
python3 - "$MAIN" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
# strip any previous hook, then inject with the CORRECT property (PlasmoidItem root id)
s = s.replace("\n    // HARNESS-ONLY: delayed auto-open\n    Timer { id: harnessOpen; interval: 4000; running: true; onTriggered: Plasmoid.expanded = true }\n", "")
hook = "\n    // HARNESS-ONLY: delayed auto-open (PlasmoidItem.expanded — the real lever)\n    Timer { id: harnessOpen; interval: 5000; running: true; onTriggered: root.expanded = true }\n"
anchor = "    // ---- popup shell"
assert anchor in s
s = s.replace(anchor, hook + anchor, 1)
assert "root.expanded = true" in s and s.count("harnessOpen") == 1
open(p,'w').write(s); print("hook v2 injected")
PY
plasmashell --no-respawn > /tmp/stk-harness/shell4.log 2>&1 & SHELL_PID=$!
sleep 18
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$(cat /tmp/stk-harness/add.js)" 2>&1 | head -1
sleep 14
spectacle -b -n -o /tmp/stk-harness/shots/popup-test4.png
kill $SHELL_PID $KWIN_PID 2>/dev/null
echo DONE
