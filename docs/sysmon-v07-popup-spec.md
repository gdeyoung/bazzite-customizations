# SysMon v0.7 — Popup UX Design Spec (4-tab redesign)

Target: Plasma 6.7 panel plasmoid `com.gdeyoung.plasma.sysmon`, dark surface,
Noto Sans, Kirigami.Units. Verified at scale 1.0 and DPR 2 in the virtual
harness (skill `devops/plasma-virtual-harness`) **before** the user sees it.
Evidence base: `docs/sysmon-v07-audit.md` + harness shots `sysmon-s1.png` /
`sysmon-procs-s1.png`. Scope: **popup (fullRepresentation) + probe deltas
only** — the panel chip stays untouched (audit: it works).

Corrected diagnosis (post-review 2026-10-30 — the audit's vision-based
geometry was miscalibrated on a downscaled screenshot; source-verified
facts below supersede it): the popup is real width ~540–612px
(`Layout.preferredWidth` 34GU, min 30GU) with height self-tracking the
active tab (StackLayout trick) — sizing EXISTS and works, but the popup
resizes on every tab switch and the width under-serves a 4-tab manager.
Stands from the audit: Network/Disk sections are sparse collapsed single
lines; footer help row burns a line; 32-core grid unreadable; three font
sizes in the 7–9px band; inconsistent units. Processes — the root defect
is the probe: `ps --sort=-pcpu | head -14` emits a CPU-biased 14-row
snapshot, so MEM sort re-sorts a biased subset (misleading) and mem-hungry
idle processes are invisible; plus no scrollbar, no search, no totals, and
the probe's `user`/`state` fields are captured but never displayed. User:
"a lot of wasted space… the process manager can be improved a lot."

Already implemented and KEPT as-is (mechanics not re-specced as new):
sortable CPU%/MEM% headers (bold + highlighted when active, click to
switch, always descending); per-row kill pill + conditional confirm bar
with TERM → Force-kill(9) escalation and cancel; right-aligned
CPU%/MEM%/PID numerics; header temp chips; memory-breakdown density; color
hierarchy; palette. v0.7 changes their presentation, never their behavior.

## Borrowed patterns (cited inline)

- **plasma-systemmonitor siblings** — semantic palette `#3fd18b`/`#f4405c`
  (keeps the widget native to its panel), KSysGuard process-table conventions
  (PID/USER/CPU%/MEM columns, click-sort headers, kill-by-signal).
- **htop** — default CPU% desc sort, dense single-line rows, per-core color
  grid, full-list model (never a top-N snapshot).
- **stocktick DESIGN-v4** (this repo, `plasma-stocktick/DESIGN-v4.md`) —
  fixed 960×640 frame; no modal dialogs (popup dies on focus loss) →
  confirm-in-place for kill; tabular figures everywhere; search
  replaces-the-list-in-place; fixed-width table columns, right-aligned
  numerics, elide-LEFT for mount paths; one QML file per tab.
- **omastocks PriceChart** (`reference-repos/omastocks/`) — gridline
  restraint (3 faint hairlines, labels at right edge, axis width = widest
  label via FontMetrics), 12% y-range headroom, hover readout pinned not
  cursor-following, provenance/“as of” stamps per block.
- **Google Finance rows** — 24px rows with hairlines for dense data;
  row click selects, trailing action stays one target away.
- **Linear** — restraint: nothing moves that carries data; no number
  animations on a 2s cadence (it would strobe).

────────────────────────────────────────────────────────────────────────────────
A. FRAME & ZONE MATH (all logical px; the canvas is session-scaled already)
────────────────────────────────────────────────────────────────────────────────

**Design frame: 960 × 640.** Justified: (1) stocktick shipped and
harness-verified exactly this size on this host class
(`plasma-stocktick/docs/popup-sizing-plasma67.md` — source-verified clamp
algorithm); (2) a real process manager needs ~18 visible rows + toolbar +
sticky header + totals = ≥520px of table alone; a 720×520 frame would show
~12 rows and squeeze 32-core cells to ~16px; (3) fits both verification
screens — scale-1 1920×1080 (95% clamp = 1824×1026) and QT_SCALE_FACTOR=2 on
5120×2880 (logical 2560×1440); (4) ≤ half of the user's 5120×1440 screen.

**Sizing decision — FIXED frame, replacing per-tab self-sizing** (this is
the audit's open question, now decided): today Details.qml sets
`Layout.preferredWidth` 34GU (~612px) + minimums, main.qml adds minimums
again at the instantiation site, and height self-tracks
`children[currentTab].implicitHeight` — functional, but the popup RESIZES
on every tab switch and the width starves Processes and the core grid.
v0.7: one fixed frame for all tabs (a popup that grows/shrinks per tab
feels unstable — stocktick precedent), sized by exactly the harness-proven
stocktick pattern, nothing else:

```qml
// Details.qml root — the ONLY sizing hints in the package
Item {
    Layout.minimumWidth: 960
    Layout.minimumHeight: 640
    // no preferred*, no implicit*, no width:/height: literals
}
```

Delete the attached Layout props at the `fullRepresentation:` instantiation
in main.qml, the `Layout.preferred*` bindings, and the
`children[currentTab].implicitHeight` self-tracking height in Details.qml
(pages get fillHeight). If a size change “doesn’t take”: popupWidth/
popupHeight are frozen in applet config — stop plasmashell, delete both
keys from the applet group in appletsrc, restart (runbook in the sizing
doc §1.2).

All pages fill the same fixed frame (StackLayout pages get
`Layout.fillWidth/Height: true`) — the tallest-child scroll trap dies with
the fixed frame; keep the explicit fill so it stays dead.

**Zone ledger** (content = 960 − 2×16 margins = **928 wide**):

```
┌ 960 × 640 ─────────────────────────────────────────────────────┐
│ 16 │ HEADER  32   "SysMon" … [CPU 79°][GPU 41°][NVMe 48°] ● as of 15:22:41
│    │ TABBAR  36   Performance · Disks · Processes · Hardware
│    │ ── gap 8 ──                                                 │
│    │ PAGES  532   (per-tab zone math below)                      │
│ 16 │                                                               │
└──────────────────────────────────────────────────────────────────┘
640 = 12(top) + 32 + 8 + 36 + 8 + 532 + 12(bottom)
```

Performance tab, 928 × 532 split 568 | 16 gutter | 344:

```
LEFT 568                          RIGHT 344
┌ CPU card 300 ─────────────┐   ┌ GPU card 168 (conditional) ─┐
│ header 22 · hero 26       │   ├──────── 12 gap ─────────────┤
│ core grid 2×(56+3) = 115  │   ┌ NET card 176 ───────────────┐
│ legend 10 · spark 72      │   ├──────── 12 gap ─────────────┤
├──────── 12 gap ───────────┤   ┌ DISK card 176 ──────────────┐
┌ MEMORY card 220 ──────────┐   └ (no GPU → NET/DISK grow) ───┘
│ header 22 · hero 26       │
│ stack bar 14 · legend 14  │   core cell = (568−2×14 −15×3)/16
│ spark 60 (+swap row 18)   │                = 30 w × 56 h
└───────────────────────────┘
```

Processes tab, 928 × 532: toolbar 36 · column header 26 ·
list 442 (= 18.4 rows @ 24) · totals/confirm 28.

**Spacing system** — 4px base rhythm, expressed in Kirigami tokens
(reference values on this host class: `gridUnit≈20, smallSpacing SS≈4,
largeSpacing LS≈8`; log actuals to the journal on first harness run):
page margins 16 (4·SS) · card padding 12 (3·SS) · card gap 12 ·
intra-card gap 4–8 (SS, 2·SS) · hairlines 1px @ textColor 10% ·
card fill white @ 4–5%, radius 8, hover white @ 7%.
Raw-px literals are allowed ONLY for: the 960/640 frame, table column
widths, row heights (24/26/28/32), and type sizes — alignment must not
drift with theme spacing.

**Typography scale** (Noto Sans via Kirigami.Theme family; explicit
pixelSize — Theme.smallFont inside the old narrow popup produced the
too-small, inconsistent sizes; floor is 10px; ALL numerics get
`font.features: {"tnum": 1}`, graceful
fallback on older Qt — host is 6.7.5, verified supported):

| role        | px | weight   | use                                        |
|-------------|----|----------|--------------------------------------------|
| hero        | 24 | semibold | CPU%, MEM used, GPU%, NET↓ rate            |
| value       | 14 | semibold | card right-values, disk %, totals Σ        |
| body        | 11 | regular  | table NAME/USER, HwRow values              |
| micro       | 10 | regular  | CAPS +0.6 tracking: labels, col headers,   |
|             |    |          | legends, provenance, per-iface rows        |

**Color** — two tiers, both already in the codebase:
- semantic (state): ok `#3fd18b` · warn `#e5c07b` (≥70% / ≥70° / ≥15%cpu) ·
  crit `#f4405c` (≥90% / ≥85° / ≥60%cpu). `levelColor()` switches to these.
- series (identity, unchanged): blue `#7aa2f7` (net↓, mem, disk R, used),
  cyan `#7dcfff` (net↑), violet `#bb9af7` (busiest core, cache, VRAM),
  amber `#e5c07b` (GPU). Color is never the sole encoding — every colored
  datum also carries its number, sign, or position.
- neutrals: text `Kirigami.Theme.textColor`, secondary `disabledTextColor`,
  hairline textColor@10%, card white@4%, hover white@7%.

**Units policy** (single helpers in main.qml, all tabs reuse):
rates `4.3 MB/s` / `118 KB/s` (space, /s, 1 decimal <10, int above) ·
sizes `18.4 GB` prose, `18.4G` dense rows · pct integer `92%` ·
temps `79°C` (chips keep compact `79°`) · load 2 decimals · RSS `1.2G/340M`.

────────────────────────────────────────────────────────────────────────────────
B. SHELL (Details.qml — header, tabs, provenance)
────────────────────────────────────────────────────────────────────────────────

Header 32: **“SysMon”** 13 semibold left. Right cluster (right-aligned row):
temp pills (KEEP — audit keep-item; the only temps in the popup, restyled:
micro-caps label + value tnum, pill white@4%, text by threshold
warn/crit/ok, conditional per sensor ≥0, order CPU·GPU·NVMe), then the
**provenance stamp** (omastocks borrow, replaces the dead footer help row):
`● as of 15:22:41` — green dot live; `◐ stale · 15:18:02` amber when the
probe has missed >3 ticks. No other footer anywhere.

TabBar: keep PC3.TabBar (native), 4 tabs, `lastTab` persists to config.
StackLayout below, pages fillHeight. Popup-open work stays deferred via the
existing ~150ms Timer pattern (open-then-work rule).

────────────────────────────────────────────────────────────────────────────────
C. PERFORMANCE TAB (tabs/PerfTab.qml)
────────────────────────────────────────────────────────────────────────────────

Two columns as zoned above. SysSection/collapsing is RETIRED here — the
frame fits everything; the collapse hint footer dies with it. Cards are
SectionCard atoms (flat fill, 12 pad, micro-caps header, right value).

**CPU card** (568×300):
- header: `CPU` + right `load 3.05 · 2.79 · 2.55` (value 14 tnum).
- hero: `38%` 24 + right `busiest core 92%` (micro label, value 14).
- **core grid v2**: 16 per row × 2, cell 30×56, per-core hue walk (keep),
  fill bottom-up like today, and — the fix for the unreadable grid — the
  core’s integer % drawn INSIDE the cell at 10px tnum when cell ≥26px wide
  (fallback: no numbers below 26px). Rainbow legend strip `1 … 32` kept.
- spark 72: avg (green #3fd18b) + busiest (violet) overlay, 0–100 fixed,
  legend micro `avg · busiest`.

**MEMORY card** (568×220) — density concept kept, upgraded:
- header: `MEMORY` + right `swap 3.5G · 6%` (conditional).
- hero: `18.4 GB` 24 + `/ 31.3 GB` 14 muted + right `59%` 14 colored.
- **stacked bar** 14px rounded: used #7aa2f7 · buff #bb9af7@.55 ·
  cache #bb9af7@.3 · avail textColor@.08.
- legend micro row: `used 18.4 · buff 0.9 · cache 11.0 · avail 9.8` (labels
  muted, values white tnum).
- spark 60 (ramPct, blue, fixed 0–100). Swap micro-bar 6px when used>0.

**GPU card** (344×168, conditional on gpuBusy≥0 || gpuTemp≥0 as today):
header `GPU` + right power `19.8 W` · hero `12%` 20 + `VRAM 8.2/24G` micro ·
spark 56 amber · VRAM+GTT Gauge pair (existing atom) at 6px bars, micro
labels. Hidden → NET and DISK grow equally (ColumnLayout fillHeight).

**NETWORK card** (344×176) — the fix for “one number, no graph”:
header `NETWORK` · hero row `↓ 4.3 MB/s` 20 + `↑ 118 KB/s` 14 ·
per-interface micro rows, top 2 by activity: `wlan0  ↓4.2M  ↑0.1M` ·
spark 64 dual-line autoScale (blue↓/cyan↑), legend micro `down · up`.

**DISK card** (344×176) — the fix for “92% full, which disk?”:
header `DISK · nvme0n1` (device name from disk_dev — names the disk) ·
hero `92%` 20 colored + `876G / 953G` 12 · usage bar 8px ·
rates micro row `R 12M/s · W 84M/s · 310/89 iops` ·
spark 64 dual (R blue / W #f4405c).

Every section now = hero + graph + detail row. No bare numbers anywhere.

────────────────────────────────────────────────────────────────────────────────
D. PROCESSES TAB (tabs/ProcsTab.qml) — the real manager
────────────────────────────────────────────────────────────────────────────────

```
┌ 928 ────────────────────────────────────────────────────────────────────┐
│ [ 🔍 Filter · name, user, pid              ✕ ]        showing 18 / 412  │ 36
│ NAME ◂fill▸               USER  S    PID  CPU%▾  MEM%   RSS   1m  kill │ 26
│ plasmashell                gdey  888488  9.0   0.8  1.2G  ▁▂▃▄▅  …     │
│ brave                      gdey  14251   6.2   1.8  612M  ▂▃▂▃▂        │ 24px rows,
│ …18.4 visible, clipped partial row = continuation affordance            │ hairlines,
│                                                                         │ ListView +
│ Σ CPU 412.3% · Σ MEM 63.4% · Σ RSS 18.2G        (confirm bar appears    │ 28
│                                                 between list+totals)    │
└─────────────────────────────────────────────────────────────────────────┘
```

**Toolbar 36** — search is always visible (deliberate deviation from the
stocktick “search behind Add” rule: that rule is about *add* flows; here
finding one process among 400+ IS the job). PC3.TextField, width 240,
placeholder `Filter · name, user, pid`, trailing ✕ clears, Esc clears.
Live filter, no debounce (data is local). Right: `showing N / M` micro.
No refresh/pause buttons — keep chrome minimal.

**Columns** (fixed widths, shared `procCols` object consumed by BOTH header
and delegate so they cannot drift; all numerics right-aligned tnum):

| col    | w    | align | content                                          |
|--------|------|-------|--------------------------------------------------|
| NAME   | fill | left  | comm 11 white, elide right; PC3.ToolTip = full args |
| USER   | 84   | left  | ALREADY in the probe, never displayed — surface it; muted, elide |
| S      | 24   | ctr   | state letter R/S/D/Z/T (also already in probe); D=warn, Z=crit, else muted; tooltip spells it out |
| PID    | 60   | right | tnum muted (right-aligned today — carry over unchanged) |
| CPU%   | 60   | right | tnum; ≥60 crit, ≥15 warn, else text (1 decimal)  |
| MEM%   | 60   | right | tnum 1 decimal                                   |
| RSS    | 68   | right | tnum compact G/M (NEW probe field rss_kb — absolute memory) |
| 1m     | 88   | right | per-PID CPU spark, 30 samples @2s (widened)      |
| kill   | 28   | ctr   | always-visible `kill` pill — existing mechanic, restyled |

Fixed columns sum 472 → NAME gets ~456. The numeric right-alignment and
elide rules are already correct in the code — carry them over verbatim.

**Sort**: KEEP the existing mechanic — click a header to make it the sort
column, always descending, bold + fg highlight when active (details in
Details.qml 406–421 today). Two deltas only: (1) apply the SAME pattern to
NAME / USER / PID / RSS (mechanic unchanged, more columns);
(2) discoverability — add a ▾ arrow beside the active header (bold-alone
was illegible as an affordance). Tiebreak PID asc. Note: MEM sort is
misleading today ONLY because the probe pre-sorts by CPU and caps at 14 —
the probe fix below is what makes it meaningful, not new sort UI.

**Scroll**: ListView (NOT Repeater-in-ScrollView), fixed rowHeight 24,
clip, PC3.ScrollBar.vertical AsNeeded. Column header (26) and totals (28)
live OUTSIDE the flick — sticky by construction. ~18 rows visible + a
clipped partial row so continuation is obvious.

**Rows**: 24px, hairline bottom, hover white@5%, click = select
(#3fd18b@10% fill + 2px left rail). **Kill flow KEPT verbatim from the
current code** (Details.qml 453–528): always-visible per-row kill pill
(28×24, red-tint pill, PointingHand) → click sets killTarget → conditional
confirm bar appears between list and totals: `Kill cfsync (5373)?
[TERM] [Force kill (9) after first try] [Cancel]` — same TERM→9 escalation
and auto-clear-when-pid-vanishes behavior, restyled to a fixed 28px so its
appearance can’t reflow the fixed frame. One addition: surface the
executable engine’s exit code in the bar (`✗ no permission` on EPERM for
root procs) instead of failing silently. Popup focus-loss forbids modal
dialogs — keep confirm-in-place.

**Totals row**: `showing N / M` left; right `Σ CPU 412.3% · Σ MEM 63.4% ·
Σ RSS 18.2G` computed over the FULL filtered set (audit: “no totals”).

**Model/data** (probe delta in Appendix): full process list, refreshed
every 2s ONLY while `currentTab===2 && root.expanded` (today it’s a
one-shot snapshot that goes stale!). On each tick: sort+filter → array
reset, then **restore ListView.contentY** (fixed row height makes this
exact) so scrolling survives ticks. Per-PID CPU history lives in a
root-level JS map pid→comma-packed string (string-packed series — array
roles in ListModel are a proven-dead transport); delegate Canvas reads it,
draws logical coords only, requestPaint only on its own role change.
Skeleton rows (24px bars, pulse 0.15↔0.35) until first fetch; `no matches
for “xyz”` muted row on empty filter.

────────────────────────────────────────────────────────────────────────────────
E. DISKS TAB (tabs/DisksTab.qml)
────────────────────────────────────────────────────────────────────────────────

Header strip 28: `Volumes · 4 mounted` left + right `nvme0n1 · R 12M/s ·
W 84M/s · 310/89 iops · NVMe 48°` (aggregate from perf data — one line,
names the device).

Volume table (rows 32, hairlines; keeps today’s aligned columns, widened):
[usage bar 300][used / size 130 right][pct 48 right colored][fs 64 NEW][
mount fill, elide-LEFT so tails show]. Bar colors via levelColor. Swap row
appended when swapUsed>0.

Per-disk IO section (NEW — probe delta): one row per whole disk (40px):
`nvme0n1  R 12 MB/s · W 84 MB/s · 310/89 iops` + inline dual spark 200×28
(blue R / red W). If the per-disk probe delta slips, this section renders
the aggregate only — the tab still ships.

────────────────────────────────────────────────────────────────────────────────
F. HARDWARE TAB (tabs/HwTab.qml)
────────────────────────────────────────────────────────────────────────────────

Same HwRow data, re-flowed from one long column into a **2-column card
grid** (456 | 16 | 456): IDENTITY (board, BIOS, OS, kernel, uptime — the
ticking uptime logic moves here with its `hwLoadedAt` Connections handler,
one-handler rule preserved) · CPU (model, cores/threads, GHz, L3) ·
MEMORY (total, type, speed) · GPU + DISPLAYS · STORAGE + NET · DEVICES
(USB/PCI/Bluetooth/Audio). HwRow atom moves to ui/ shared atoms. Skeleton
cards until hwinfo lands (one-shot fetch at applet start — usually warm).

────────────────────────────────────────────────────────────────────────────────
G. STATES & MOTION
────────────────────────────────────────────────────────────────────────────────

Restraint (Linear): no number animations — tabular figures already prevent
jitter, and a 2s cadence would strobe. Hover fades 120ms only. Tab switch:
PC3 default. Loading = shape-matched skeletons (proc rows, hw cards), each
hydrating independently. Unavailable sensors (<0): value `—`, card hidden
only for GPU (existing rule). Stale probe: header stamp `◐ stale` amber
after 3 missed ticks; last values stay. Empty filter: muted no-match row.

────────────────────────────────────────────────────────────────────────────────
STRUCTURE TREE (one file per tab; every file < 300 lines; one handler per
signal per file; run tools/check_qml.py before every install)
────────────────────────────────────────────────────────────────────────────────

```
contents/ui/
  main.qml          chip untouched; fullRep: Details (NO layout hints here);
                   + proc tick timer (tab/expanded-gated), fmt helpers, config
  Details.qml       ~120: sizing (ONLY Layout.minimum 960/640), header+temps+
                   provenance, TabBar, StackLayout pages fillHeight
  ui/Atoms.qml      SectionCard, TempPill, MicroLabel, ValueText, Hair,
                   SkeletonRow, HwRow (shared, id-injection named `ctx` not `root`)
  tabs/PerfTab.qml  ~260: 2-col layout, CPU/MEM/GPU/NET/DISK cards
  tabs/ProcsTab.qml ~280: toolbar, sticky header, ListView, totals/confirm
  tabs/DisksTab.qml ~140: volumes table + per-disk IO
  tabs/HwTab.qml    ~160: 2-col hw card grid + uptime
  CoreGrid.qml      v2: numbered cells, perRow 16, min-cell fallback
  Sparkline.qml     unchanged (works; logical coords)
  HistBars.qml      unchanged (Disks fallback)
  Gauge.qml         unchanged
  SysSection.qml    RETIRED (delete; collapse dies with the fixed frame)
contents/scripts/
  procprobe.sh      v2 (appendix)
  sysmon.sh         +disks[] per-disk IO, +fstype in vols
```

APPENDIX — probe deltas & plumbing the design depends on
────────────────────────────────────────────────────────────────────────────────

1. **procprobe.sh v2** — THE root fix (today `ps --sort=-pcpu | head -14`
   pre-sorts by CPU and caps: MEM sort re-sorts that biased subset and
   mem-hungry idle processes are invisible). Primary shape — full list:
   `ps -eo pid,user,comm,pcpu,pmem,rss_kb,state,args --no-headers
   --sort=-pcpu | head -600` (args = rest-of-line, truncated 120 chars;
   JSON-escape `\ " ` and control chars in awk gsub — args carry quotes).
   Emit `{"procs":[[pid,user,comm,pcpu,pmem,rss_kb,state,args],...]}` —
   `user`/`state` already flow today, v2 just finally displays them;
   `rss_kb` and `args` are the only new fields. One strict JSON line;
   validate with scripts/validate_probe.py before blaming QML.
   **Fallback if the cost-probe trips** (parse+sort >8ms, risk 2): union
   of top-40-by-CPU ∪ top-40-by-MEM (~≤80 rows) PLUS exact totals computed
   in awk over the FULL ps set — `{"n":412,"cpu":412.3,"mem":63.4,
   "rss_kb":19530000}` — so the totals row stays honest and “showing N / M”
   states the cap instead of lying.
2. **sysmon.sh**: add `"disks":[{"n":"nvme0n1","rs":sect,"ws":sect,
   "ri":n,"wi":n},…]` from /proc/diskstats whole disks only (exclude
   names ending in a digit = partitions, plus loop*/ram*/dm-*); add
   `fstype` to vols (df -T). QML computes rates from cumulative counters
   exactly like the existing disk_dev path.
3. Config keys: `lastTab` (persist currentTab).
4. Popup sizing: minimum-only single site (§A); freeze-key runbook.
5. ListView model = plain array reset + contentY restore; per-PID sparks
   from root-level string-packed map; model ids exposed as root property
   aliases (file-local id trap); `Plasmoid` stays root-file-only.
6. Numerics: `font.features: {"tnum": 1}`; `Units.smallRadius` is
   undefined → use `smallSpacing / 2`; fixed-width text cells align via
   `horizontalAlignment`, never `Layout.horizontalAlignment`.

RISKS & MITIGATIONS
────────────────────────────────────────────────────────────────────────────────

1. **Mechanism switch (preferred + self-tracking height → minimum-only
   fixed frame) appears ignored** → popupWidth/popupHeight freeze-key
   runbook (stop shell, delete both keys, restart); journal the resolved
   item size on every open (HARNESSGeometry channel). Geometry is gate #1:
   960×640±2 AND byte-identical across all four tabs — the height-jump bug
   is dead only if the number never moves between tabs.
2. **500-row JSON @2s ≈ 60–100KB** → cap 600 rows, args truncated 120;
   tick gated on tab-visible + popup-open; journal-probe the parse+sort
   cost; if >8ms, degrade to the top-40∪top-40 + awk-totals probe shape
   (appendix 1) — UI code is identical for both shapes apart from the
   totals source.
3. **Model reset kills scroll/selection** → contentY restore + fixed 24px
   rows; selection tracked by PID (survives reorder); verify mid-scroll
   tick in harness (scroll, wait 4s, contentY unchanged ±1 row).
4. **Per-row Canvas at DPR 2** → logical coords only, string-packed
   series, paint only on own-role change; DPR-2 harness run is mandatory.
5. **Kill of root/privileged proc fails silently** → surface executable
   engine exit code in the confirm row (`✗ no permission`); never
   auto-escalate TERM→KILL.
6. **Column drift header vs delegates** → single shared procCols object.
7. **Nested flick traps** → ListView owns scrolling; no ScrollView wrapper;
   column header/totals outside the flick.
8. **First-paint reflow** → seed fixed-height skeleton rows synchronously
   in Component.onCompleted (stocktick verified: first layout pass = final).
9. **ps args break the JSON line** → awk escaping + validate_probe.py gate.
10. **Executable engine removal in future Plasma** → already the widget’s
    data path (plasma5support); kill inherits the risk; no new dependency.

VERIFICATION GATE (harness, scale 1 AND QT_SCALE_FACTOR=2 @5120×2880)
────────────────────────────────────────────────────────────────────────────────

1. Geometry: popup content 960×640±2 both runs, IDENTICAL across all four
   tab-variants (journal probe — proves the height-jump fix).
2. Whitespace: PIL ink-bounding-box ≥ 82% of content area per tab. Measure
   the pre-change baseline in the same harness run for the delta — do NOT
   cite the audit’s 40–45% figure (it came from the miscalibrated frame).
   Brightness gate before any pixel claim.
3. Processes behaviors (tab-variant screenshot trick + journal probes):
   model count >100 on this host; filter narrows; sort header toggle works
   across the widened column set; plant `sleep 613`, filter `sleep`, TERM
   it via the existing confirm flow, row gone ≤2 ticks; plant a 2GB RSS
   hog (`python3 -c 'a=bytearray(2_000_000_000); import time;
   time.sleep(600)'`), sort MEM% desc → hog at/near top with RSS ~1.9G —
   THE proof the probe cap is dead and MEM sort is meaningful; totals
   ΣCPU/ΣMEM/ΣRSS match a parallel `ps` capture in the run log.
4. Kill pill hit cells: magenta-glow patch, measure content-vs-cell containment.
5. Core grid: right-edge core #32 number legible at DPR 2 (no canvas clip).
6. Journal clean (console.error probes only), check_qml.py 0/0, all files
   <300 lines. Commit only after all gates pass; install per
   plasma-plasmoid-development deploy loop.
```
