# Popup test harness (nested virtual Plasma session)

Opens the stocktick popup on a virtual display — no user desktop involvement.
Usage: `timeout 110 dbus-run-session ./run-harness.sh` then vision/PIL the shot
at /tmp/stk-harness/shots/. Fresh HOME per run (deterministic single instance);
appends a HARNESS-ONLY Timer that sets `root.expanded = true` (PlasmoidItem —
NOT Plasmoid.expanded, which silently no-ops) 5s after the widget is added.
Set QT_SCALE_FACTOR=2 on the plasmashell line to replicate DPR-2 hosts.
Verified 2026-10-30: popup 960×641, chart full-height, date ticks + price
labels painting, no blank band, no bottom cutoff.
## `run-shot.sh` — one generic full-desktop capture for any PlasmoidItem widget

Runs the widget in a nested virtual Plasma session (never the desktop you are logged into): private HOME and
XDG dirs under `/tmp/stk-harness`, `dbus-run-session` + private runtime dir, `kwin_wayland` + `plasmashell`,
Breeze Dark seeded, flat wallpaper, panel on top so popups are not clipped. Three frames per run:
`<tag>-chip.png` (popup closed), `<tag>-popup.png` (auto-opened), `<tag>-popup2.png` (+15 s).

    ./run-shot.sh <plugin-id> <repo-subdir> <tag> [open-ms]
    SCALE=1        NOWALL=1        # 1× capture, no wallpaper
    SEEDCFG=<file> # key=value lines written into the widget's [Configuration]; "#group<TAB><name>" picks the group
    PATCH=<file>   # "file<TAB>literal<TAB>replacement" applied to the COPIED package only (demo tab, etc.)
    STUBDIR=<dir>  # prepended to PATH inside the session (fixture binaries such as a stub tailscale)

Seeds and patches never touch the repo package or the installed copy; they exist so a published screenshot
can show demo inventory (fictional shares, places, peers) instead of whatever the machine really has.
See `plasma-weatherx/README.md` → Screenshots for a seeded example, `plasma-tailfin/` for `STUBDIR`.

