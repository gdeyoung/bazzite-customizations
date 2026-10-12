# Plasma SysMon

Live system stats in the KDE Plasma 6 panel — a compact **M / C / N / D** letter+meter strip
that expands into a tabbed task-manager popup: performance charts, GPU load/VRAM/GTT,
per-volume disk gauges, a killable process table, and fastfetch-grade hardware inventory.

Ported from the author's own [Omarchy bar plugin](https://github.com/gdeyoung/omarchy-sysmon)
(Hyprland/Quickshell) to native Plasma 6 — same probes, same behavior, zero system mutations.
Built and verified on Bazzite (immutable Fedora, Plasma 6.7, Wayland, 5120×1440 @1.05×).

![bar](docs/panel-bar.png)

```
bar (compact):   ▎M  ▎C  ▎N  ▎D        ← click to open
                 └ hover for values
popup:           Performance · Disks · Processes · Hardware
```

## Screenshots

### The bar

One letter, one meter per stat — the numbers live in the hover tooltip. Zero noise until you click:

![bar widget — compact M C N D strip](docs/panel-bar.png)

### Performance tab

Memory with buffers/cache/swap breakdown, CPU total % with busiest-core overlay and per-core
grid, GPU load with power draw and VRAM/GTT meters, network rates. 180-sample ring buffers run
whether or not the popup is open, so it opens with minutes of warm history already drawn:

![Performance tab](docs/panel-performance.png)

### Disks tab

Read/write rate charts and IOPS up top; below, a fuel gauge for every mounted volume — aligned
table: usage bar, used/size, color-coded percentage, and the mount point (long paths elide from
the left so they always fit):

![Disks tab](docs/panel-disks.png)

### Processes tab

Top processes with aligned PID · COMMAND · CPU% · MEM% · kill columns — click a column header
to sort. Two-step kill: TERM first, and if the process survives the next refresh the button
becomes **Force kill (9)**. Only processes you own get a kill button:

![Processes tab](docs/panel-processes.png)

### Hardware tab

Fastfetch-grade machine inventory probed once at popup open — no root, no Python, no extra
dependencies. Vendor/product/board, BIOS, CPU, memory, GPU, displays, storage, network
controllers with kernel drivers, audio, battery, OS + kernel, uptime. Anything your hardware
doesn't expose just hides.

![Hardware tab](docs/panel-hardware.png)

## Bar

| Letter | Stat | Bar fill | Source |
|---|---|---|---|
| M | RAM used % | green/amber/red (70/90) | `/proc/meminfo` |
| C | CPU utilization | green/amber/red | `/proc/stat` jiffy deltas |
| N | ↓/↑ rate | blue, log-scale activity | `/sys/class/net/*/statistics` deltas |
| D | whole-disk used % | green/amber/red | `df` + `lsblk` |

Left-click opens the detail popup. Hover for a tooltip with the numbers.
`barMode: values` in the widget settings restores full readouts
(`M 10.5/30.5G  C 12%  N ↓1.2M↑240K  D 44G/930G`).

## Popup

Four tabs, each self-sized to fit its content — no scrolling inside a tab, and the popup
grows/shrinks when you collapse sections or switch tabs:

- **Header** — CPU/GPU/NVMe temperatures, threshold-colored.
- **Performance** — M/C/G/N sections (Network & Disk collapsed by default), sparklines,
  per-core grid, gauges.
- **Disks** — R/W charts + IOPS + aligned volume table.
- **Processes** — aligned columns, click-header sort, two-step kill.
- **Hardware** — one-shot unprivileged inventory.

Every clickable — tabs, section headers, sort headers, kill buttons — takes a pointing-hand
cursor and highlights on hover. Section headers collapse on click. Refresh interval is
configurable (1–10 s, default 2 s).

## Install

```bash
git clone https://github.com/gdeyoung/bazzite-customizations
cd bazzite-customizations/plasma-sysmon
./install.sh
```

No sudo, no compiling, no layering — installs to
`~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.sysmon` and survives Bazzite/ostree
updates. Then: right-click panel → **Enter Edit Mode** → **Add Widgets** → search
**SysMon** → drag to the panel.

Remove any time: `kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.sysmon` and restart
plasmashell.

## How it works

Pure QML + three shell probes — no compiled code, no daemons:

- `sysmon.sh` — one JSON line per tick from `/proc` + `/sys` (RAM, CPU jiffy deltas, network
  counters, disk stats/volumes, GPU sysfs, temps). ~250 ms per run, verified.
- `procprobe.sh` — top processes by CPU (`ps -eo pid,user,comm,pcpu,pmem`).
- `sysinfo-probe.sh` — one-shot hardware inventory for the Hardware tab.
- QML computes rates/deltas and keeps 180-sample ring buffers; the popup draws from the same
  buffers, so history is warm the moment it opens.

Runs via Plasma's `executable` dataengine (`org.kde.plasma.plasma5support`) — the
QML-accessible way to schedule shell probes from a pure-QML applet in Plasma 6.

## Why (design notes)

- **User-level only** — immutable OS (Bazzite) means nothing touches `/usr`; the widget lives
  in `$HOME` and survives ostree updates undamaged.
- **Aligned tables, not floating text** — the Disks and Processes tabs are real tables with
  fixed columns; long mount paths elide from the left instead of overlapping the bars.
- **Self-sizing popup** — popup height binds to the visible tab's content height. Earlier
  builds sized the scroll area by the tallest tab, which made every tab scroll — that bug is
  gone by construction.
- **Probe contract tested** — the JSON the probes emit is validated field-by-field (32 fields,
  monotonic counters, cross-checked against direct `/proc` reads). One real bug this caught:
  `lsblk -no PKNAME` without `-d` returned multi-line output on partitioned NVMe, producing
  malformed JSON that QML's `JSON.parse` silently discarded — the widget ran with no data.
  Fixed (`lsblk -dno PKNAME` + guarded read); the same fix landed upstream in the Omarchy
  plugin.

## Lineage

Forked conceptually from the author's
[omarchy-sysmon](https://github.com/gdeyoung/omarchy-sysmon), which forked
[vm.sysmem](https://github.com/jhonoryza/omarchy-sysmem) by jhonoryza (MIT). Same idea,
same probes — rewritten for Plasma 6 (PlasmoidItem, PlasmaComponents, Kirigami, KConfig XT).

## License

MIT — see the repo [LICENSE](../LICENSE). Probes carry their upstream MIT lineage.
