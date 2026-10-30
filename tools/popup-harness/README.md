# Popup test harness (nested virtual Plasma session)

Opens the stocktick popup on a virtual display — no user desktop involvement.
Usage: `timeout 110 dbus-run-session ./run-harness.sh` then vision/PIL the shot
at /tmp/stk-harness/shots/. Fresh HOME per run (deterministic single instance);
appends a HARNESS-ONLY Timer that sets `root.expanded = true` (PlasmoidItem —
NOT Plasmoid.expanded, which silently no-ops) 5s after the widget is added.
Set QT_SCALE_FACTOR=2 on the plasmashell line to replicate DPR-2 hosts.
Verified 2026-10-30: popup 960×641, chart full-height, date ticks + price
labels painting, no blank band, no bottom cutoff.
