# plasma-sysmon v0.7 audit — evidence for redesign (2026-10-30)

Method: virtual harness (skill `devops/plasma-virtual-harness`), scale 1.0,
5120×2880 virtual screen. Sources: `shots/sysmon-s1.png` (Performance tab),
`shots/sysmon-procs-s1.png` (Processes tab, tab-switch injected at +9s).
Code: main.qml 443 (chip @370, popup root @438), Details.qml 664, CoreGrid 126,
Sparkline 103, SysSection 71, HistBars 52, Gauge 40 — 1,528 LOC.

## P0 — sizing (the big one)

- Popup opens **~230×160-190px** — Details.qml has NO `Layout.minimumWidth/
  Height` on the fullRepresentation (predates the sizing rules learned in the
  stocktick campaign). Popup height = `children[currentTab].implicitHeight`
  (StackLayout) → height jumps between tabs; no floor.
- Per stocktick-verified rules: popup design size comes from
  `Layout.minimumWidth/Height` alone; 960×640 is a proven comfortable size
  for this class of popup.

## Performance tab findings

1. **40–45% of the popup is whitespace.** Inter-section padding ×6 gaps ≈
   another 10%.
2. **Network section: one number ("4.3 KB/s"), no graph, no interface.**
   Disk: "92% full" only — no which disk. Both are 14px rows using <40% of
   width. Sparse = wasted space (user's core complaint).
3. **Header duplicates the chip** (CPU/NVMe temps) — redundant inside popup.
4. **Footer help text permanently consumes a row** ("click a section header
   to collapse — 180 sample history").
5. **32-core grid cells ~3px — decorative, unreadable.**
6. Typography: 3 text sizes in 190px height (9/8/7px); mixed alignment
   (header right, bodies left, percentages right); inconsistent units
   (24.0G vs 4.3 KB/s vs 8% vs 79°); legend in 7px text.

## Processes tab findings (the "can be improved a lot")

1. **Bottom ~40% of the popup is EMPTY** below the last process row.
2. **~16 rows visible, capped** — no scrollbar, no indication the list
   continues; a real host has hundreds of processes.
3. **No sort controls** (headers are plain labels), **no search/filter**.
4. **No kill/signal action, no per-process detail, no totals row.**
5. CPU%/MEM% **left-aligned** — decimals don't line up; PID column wastes
   width; per-row sparkline column ~30px — too small to read.

## What already works (keep)

- Chip: temps inline, legible at panel size, right-side placement good.
- Memory section density concept; per-row process sparklines as an accent;
  color hierarchy (white values / gray names); palette #3fd18b/#f4405c.
- Data layer: temps, load, mem breakdown, net, disk, procs(PID/CMD/CPU/MEM)
  all already flowing — the redesign is presentation, not plumbing.

## Redesign constraints

- Palette #3fd18b / #f4405c; dark surface; Kirigami units.
- Popup sizing via `Layout.minimumWidth/Height` (stocktick rule);
  no popupWidth/popupHeight freeze surprises (delete keys on size change,
  shell stopped).
- Canvas: logical coordinates only (no dpr math) — see skill canvas traps.
- Verification: harness at scale 1 AND host DPR 2 before presenting.
- omastocks reference patterns available: provenance stamps, per-block
  refresh cadence, proven tile-strip and chart-craft patterns
  (`reference-repos/omastocks/`).
