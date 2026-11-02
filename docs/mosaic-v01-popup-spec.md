# Mosaic v0.1 — Popup UX Design Spec (chip + drill-down popup)

Target: Plasma 6.7 panel plasmoid `com.gdeyoung.plasma.mosaic`, dark surface,
Noto Sans, Kirigami.Units. Verified at scale 1.0 and DPR 2 in the virtual
harness (skill `devops/plasma-virtual-harness`) **before** the user sees it.
Evidence base: upstream Omarchy Mosaic IA (`reference-repos/mosaic/qml/Panel.qml`,
`lib/ViewModel.js`, `lib/en.json`), host-CLI snapshot contract
(`plasma-mosaic/contents/lib/mosaic_host/mosaic_cli.py`), real E2E scan
(254 apps / 22 known-mapped / 28.6 GB; Brave 15.1 GB, Heroic 7.5 GB, Chrome
2.9 GB), fleet Plasma UX rules (skill `devops/plasma-plasmoid-development`),
`docs/sysmon-v07-popup-spec.md`. Scope: **chip (compact) + popup
(fullRepresentation), v0.1** — dashboard, history/yearly insights, mappings
editor, in-popup settings, shortcuts help page are **deferred to v0.2**
(v0.1 prefs go to a Plasma KConfigXT config dialog: hero accent color,
show-donut toggle).

North-star behaviors from upstream that this spec preserves verbatim:
donut + 4-color category coding; evidence-forward path cards; confidence
honesty (possible/shared measured-but-excluded, always visually separated);
`≥ N` lower-bound semantics whenever `meta.limited` or per-app `partial`.

## Borrowed patterns (cited inline)

- **Omarchy Mosaic upstream** (`reference-repos/mosaic/`) — IA (Overview →
  App detail → Category explorer), terminology (Mapped / Measuring… /
  Rescan / Cancel / Back / Close / Search applications… / Config / Data /
  Cache / State), `≥ N` semantics, evidence disclosures, status chips.
- **stocktick DESIGN-v4** (`plasma-stocktick/DESIGN-v4.md`) — fixed 960×640
  frame; no modal dialogs (popup dies on focus loss) → confirm/feedback
  in place; fixed-width columns, right-aligned tabular numerics,
  elide-LEFT for paths; search replaces the list in place.
- **sysmon v0.7** (`docs/sysmon-v07-popup-spec.md`, shipped+harness-proven
  on this host class) — 960×640 manager frame + its type scale; verified
  popup palette (green `#3fd18b`, red `#f4405c`, text via
  `Kirigami.Theme.textColor`); canvas LOGICAL coordinates only, labels as
  Text items outside the canvas; single-flight actions.
- **omastocks PriceChart** (`reference-repos/omastocks/`) — provenance /
  "as of" stamps per block; restrained hairlines.
- **Google Finance rows** — dense rows with hairlines; row click selects,
  trailing action one target away.
- **Linear** — nothing moves that carries data: no animated counters when
  a rescan swaps numbers (a 1–25 s cadence would strobe).

────────────────────────────────────────────────────────────────────────────────
A. FRAME DECISION — fixed 960 × 640, single-page drill-down (no top tab bar)
────────────────────────────────────────────────────────────────────────────────────────

**Fixed frame, not self-sizing.** Fleet precedent: manager-class popups are
fixed (sysmon 960×640, stocktick fixed); a popup that grows per view feels
unstable and re-clamps on every drill. 960×640 reuses the harness-proven
stocktick/sysmon sizing, carries the shared 960×640 type scale below, and
fits both verification screens (1920×1080 @1.0; 5120×2880 @QT_SCALE_FACTOR=2
→ logical 2560×1440). Hard cap `Math.min(640, Screen.height − 96)` on height
(and same clamp for width) for short panels; below ~700 logical px height
the app list simply shows fewer rows — nothing reflows.

```qml
// MosaicPopup.qml root — the ONLY sizing hints in the package
Item {
    Layout.minimumWidth: 960
    Layout.minimumHeight: 640
    // no preferred*, no implicit*, no width:/height: literals
}
```
Delete any attached Layout props at the `fullRepresentation:` site in
main.qml. If a size change "doesn't take": popupWidth/popupHeight are frozen
in appletsrc — stop plasmashell, delete both keys, restart (runbook:
`plasma-stocktick/docs/popup-sizing-plasma67.md` §1.2).

**Structure — drill-down stack, like upstream, NOT a top-level tab bar.**
Three views in a StackLayout, one visible at a time, with a header
breadcrumb: `Overview` → `App: <name>` → `Category: <name>`. Rationale:
the user's mental model is "where did my disk go" — a directed drill, not
parallel workspaces; back is one Esc/‹ away; each view gets the full 928px
content width. The only tab-like control is a 4-segment category switcher
*inside* the Category view (upstream does the same).

Zone ledger (content = 960 − 2×16 = **928 wide**):

```
┌ 960 × 640 ──────────────────────────────────────────────────────────────┐
│ 12 │ HEADER 40   ‹ Mosaic · [view breadcrumb] · as of 15:22   [Rescan]  │
│    │ ── gap 8 ──                                                        │
│ 16 │ PAGES 568   Overview | AppDetail | Category  (StackLayout,         │
│    │             all pages fillWidth/fillHeight the fixed frame)        │
└─────────────────────────────────────────────────────────────────────────┘
640 = 12 + 40 + 8 + 568 + 12
```

Header (40): back button ‹ (hidden on Overview) · view title (section 14) ·
state chip (Measuring… w/ 14px spinner, or last-error dot) · right-aligned
`as of HH:MM` (micro-caps 11) · Rescan button (primary, becomes Cancel
while scanning). One header, all three views — breadcrumb replaces page
titles; no per-view headers.

────────────────────────────────────────────────────────────────────────────────
B. TYPE SCALE & PALETTE (one scale, swept across ALL files)
────────────────────────────────────────────────────────────────────────────────────────

Scale (sysmon 960×640 scale, verbatim): **hero 24 / section titles 14 /
values 13 / body 12 / micro-caps 11** (micro-caps = ALL CAPS, +40 tracking,
secondary color). Tabular figures (`font.family` tabular / `tuning
hinting`) everywhere a number can change.

Palette — semantic Kirigami colors resolve UNDEFINED in popups (verified,
sysmon lesson), so colors are literal hex:

| Role | Value | Notes |
|---|---|---|
| text | `Kirigami.Theme.textColor` | resolves fine |
| secondary | `Kirigami.Theme.disabledTextColor` | captions, micro-caps |
| positive / complete | `#3fd18b` | fleet green (sysmon) |
| negative / failed | `#f4405c` | fleet red (sysmon) |
| partial / warning | `#ffd23f` | status-only, never a category |
| surface | `Kirigami.Theme.backgroundColor` | cards: +6% overlay |
| hairline | text @ 12% alpha | row separators |

**Category colors** (never reused by status semantics): **Config `#58a6ff`**
(blue) · **Data `#2dd4bf` (teal)** · **Cache `#f2a03d` (amber)** ·
**State `#c792ea` (violet)**. Blue/teal/amber/violet occupies a hue band
clear of the green/yellow/red status triad; ordering is fixed
(Config → Data → Cache → State) everywhere for muscle memory. Colorblind:
green/red excluded by construction; weakest pair is blue↔teal under
tritanopia — mitigated because color is never the sole channel (legend
order, text labels, bar position, dot+label chips). Verification gate:
harness pass with colorblind-simulation screenshot before merge.

Spacing: `Kirigami.Units.smallSpacing` (and `/2` for hairline gaps;
`smallRadius` is undefined — use `Units.smallSpacing`). PC3 unversioned:
`import org.kde.plasma.components as PC3`.

────────────────────────────────────────────────────────────────────────────────
C. CHIP (compact representation)
────────────────────────────────────────────────────────────────────────────────────────

Lockup: `[mosaic mark 16×16] [6] [total]` — glyph from
`contents/icons/mosaic.svg`, monochrome `Kirigami.Theme.textColor`;
total = `formatBytes(summary.bytes)` **with `≥` prefix when
`meta.limited`** (e.g. `≥ 28.6 GB`). Vertical panel: one horizontal row,
glyph+8+text, height = panel thickness, vertically centered.

States: (1) **never scanned** — glyph only + `not scanned` in micro-caps 11
(elide-right if the panel is tight; min lockup is glyph alone);
(2) **idle** — `28.6 GB` body 12, tabular; (3) **scanning** — 14px
BusyIndicator replaces the glyph, total dims to 60% and keeps its last
value (never blanks — that would read as data loss); (4) **error** — total
keeps last-good value, glyph gets a 3px `#f4405c` status dot (bottom-right).

Sizing — all four TOGETHER (fleet rule): `width` +
`implicitWidth` = 8 + 16 + 6 + textWidth + 10, plus
`Layout.preferredWidth` = implicitWidth and `Layout.minimumWidth` = 48
(glyph-only floor). Chip owns its click: MouseArea → `root.expanded =
!root.expanded`. On expand, defer heavy work ~150 ms via Timer so the
popup paints first.

────────────────────────────────────────────────────────────────────────────────
D. OVERVIEW (default view) — hero + donut left, searchable app list right
────────────────────────────────────────────────────────────────────────────────────────

Split 928 = **LEFT 384 | gutter 16 | RIGHT 528**.

LEFT 384×568 ledger:

```
┌ Hero card 104 ─────────────────────────────────┐
│ 28.6 GB   (hero 24; "≥" same size, accent)     │
│ MAPPED · 22 OF 254 APPS   (micro-caps 11)      │
│ [22 complete] [3 partial]  (status chips)      │
├──────── 12 gap ────────────────────────────────┤
┌ Categories card 320 ───────────────────────────┐
│ CATEGORIES BY SIZE        (section 14)         │
│ donut canvas 164×164 + center label overlay    │
│ legend 4 × 24 rows (dot·name·bytes·%)          │
├──────── 12 gap ────────────────────────────────┤
┌ Meta card 120 ─────────────────────────────────┐
│ as of 15:22:41 · full scan    (micro-caps 11)  │
│ coverage bar: paths 187/214 · warnings (n) ▸   │
└────────────────────────────────────────────────┘
```

**Hero.** Total = `summary.bytes` known-confidence bytes ONLY (possible/
shared are never in totals — contract semantics). `meta.limited` → `≥`
prefix + one-line note in Meta card: "Some paths were skipped; totals are
lower bounds." Partial apps count shown as chip; per-app `partial` does
NOT lower-bound the global total (only their own rows).

**Donut — KEEP (upstream visual language), not a bar.** One Canvas, fixed
164×164, `canvasSize`/`onPaint` resync imperative pattern; **logical
coordinates only** (never ×devicePixelRatio); floor'd ints. Ring: outer
R=74, inner r=48 (thickness 26), center (82,82); 4 annular sectors drawn
as path arcs (outer arc + inner arc reversed — no thick-stroke arcs), 2°
background-colored separators, start −90° (12 o'clock), clockwise, fixed
category order. Center overlay = Text items stacked over the canvas
(NEVER canvas text): total bytes (value 13) + `MAPPED` micro-caps 11.
Hover/tap an arc OR its legend row → center swaps to
`<Category> · 2.1 GB · 34%` for the hover duration; click → Category view
pre-selecting that category. Empty snapshot (all zeros) → donut hollow,
center reads `not scanned`. `showDonut=false` (config) → canvas hidden,
legend rows grow into the freed space; nothing else moves.

**Legend rows** (24px, hairline between): 8px category dot · name (body
12) · bytes (value 13, right, tabular) · % of total (11, secondary).
Rows are the arc's accessible/clickable twin (keyboard: see §H).

**Meta card.** `as of` stamp; coverage = `meta.paths.completed/total` as a
3px positive-colored bar; `meta.warnings` count in a disclosure ▸ that
expands in place (≤3 lines, secondary text). No history in v0.1.

RIGHT 528×568: **search row 36** + gap 8 + **app list 524**.

```
[ 🔍 Search applications…          ] [254]  ← PC3 TextField + count chip
┌ list 524, rows 36, scrollbar lane reserved 10 ────────────┐
│ [icon 20] Name…………… [▓▓▓▓▓▓▓░░░]   15.1 GB  ● │
└───────────────────────────────────────────────────────────┘
```

App row (36px, Google-Finance hairline): icon 20 · name (body 12,
elide-RIGHT) · **stacked category bar**: track 120px × 8px, x-proportional
segments of that app's config/data/cache/state bytes, bar total scaled so
the LARGEST app (Brave 15.1 GB) fills the track — instant size ranking
without reading numbers · mappedBytes (value 13, right, tabular) · status
dot (green/partial-yellow/unmapped-gray). Row click/Enter → App detail.
List = ListView, sorted desc by mappedBytes, delegate recycling, fixed
rowHeight 36 — 254 rows scroll in a reserved scrollbar lane; primary
readout (hero+donut+top-14 apps) is visible WITHOUT scrolling.

Search: case-insensitive substring on name, 120 ms debounce, updates the
count chip; matches replace the list in place (stocktick pattern); no
match → in-list empty state "No applications match ‘q’" + Clear. Type-ahead
never triggers a scan.

────────────────────────────────────────────────────────────────────────────────
E. APP DETAIL — hero + evidence-forward path cards
────────────────────────────────────────────────────────────────────────────────────────

Frame header shows `‹ App: Brave`. Content 928×568:

```
┌ Hero 88 ──────────────────────────────────────────────────────┐
│ [icon 40]  Brave                       ≥ 15.1 GB  (hero 24)   │
│           [partial] [State 8.2 GB · Cache 5.1 GB · …]        │
│                          [Deeper scan] [Open folder] [⧉ path]│
└──────────────────────────────────────────────────────────────┘
  gap 8
┌ Path cards (scroll, lane reserved) ──────────────────────────┐
│ ▮ ~/.config/BraveSoftware      13.6 GB   [complete]    ▸     │
│   └ expanded: evidence + skipped + top-12 subdirs            │
│ ── divider: MEASURED, EXCLUDED FROM TOTALS ──                │
│ ▯ ~/.local/share/…possible…       812 MB  [possible]   ▸     │
└──────────────────────────────────────────────────────────────┘
```

Hero: badge `partial` (yellow) or `≥` prefix when the app's own status is
partial — per-app lower bound. Category chips summarize the four category
bytes (dot + short name + value 13). Actions right-aligned, one target
apart: **Deeper scan** (per-app; button → 14px spinner + `Measuring…`;
single-flight — a second click is a no-op with inline note "Scan already
running"; on completion the card breakdowns populate, no counter
animation) · **Open folder** (host CLI `xdg-open`; never a modal; if it
fails → inline red note) · **Copy path** (clipboard + the card's copy
button flips to `Copied ✓` for 1.5 s — no toast dialogs, popup dies on
focus loss).

**Path cards** (collapsed 56px): 10px category dot · label — path
(body 12 for label, path 11 secondary below, elide-LEFT from the start so
the tail stays visible — fleet table rule) · bytes (value 13 right) —
`unknown` in secondary when `bytes:null` · status chip (complete/partial/
failed/possible/shared as outlined chip + status dot). Order: known-
confidence paths first (desc bytes); then a labeled divider **"MEASURED,
EXCLUDED FROM TOTALS"** (micro-caps 11) and the possible/shared cards —
confidence honesty, exactly upstream. Possible/shared cards render at 60%
opacity and never sum into any total.

**Evidence disclosure** (accordion — one card open at a time, so the
scan-line stays stable): expands the card in place (≤220px) into three
blocks: (1) **Why here** — `evidence` string verbatim (body 12, secondary);
(2) **Skipped** — `skippedCounts` as micro-chips `permission denied ×3`;
(3) **Breakdown** — top-12 largest subdirectories, fixed-width columns
(name elide-LEFT / bytes right tabular / status dot), header row with
`direct: 4.2 GB · 12,304 files` from `directBytes`/`directFiles`. Present
only after a deep scan; before that the disclosure shows "Run a deeper
scan to break this path down." `reason`/`source` render as a micro-caps
line under Why here when present.

────────────────────────────────────────────────────────────────────────────────
F. CATEGORY VIEW — ranked proportional bar-list (treemap deferred to v0.2)
────────────────────────────────────────────────────────────────────────────────────────

**Decision: ranked bar-list, NOT a treemap, in v0.1.** Rationale: a
readable treemap needs squarified-rect layout code, variable-height tile
text, and still produces unreadable slivers for small apps (bottom of 254
apps ≈ KB scale); it is keyboard/screen-reader hostile and is the single
riskiest custom geometry in the widget. A ranked list preserves the
proportional-perception goal (bar length = share), reuses the Overview row
component (component economy), is fully keyboard-navigable, and degrades
gracefully. The treemap stays a v0.2 candidate behind the same data.

Frame header: `‹ Category: Cache`. Content 928×568:

```
[ Config · Data · Cache · State ]   ← PC3 segmented, 32px, fixed order
┌ Summary 28: 2.9 GB cache · 10% of mapped   (values 13) ┐
  gap 8
┌ Ranked list 492, rows 40, scrollbar lane reserved ─────┐
│ [icon] Chrome      ████████████░░░░  1.4 GB  · 48%     │
└────────────────────────────────────────────────────────┘
```

Rows (40px): icon · name (body 12) · **proportional bar** — full-width
track (928−32−icon−numerics ≈ 640px) × 10px, fill = app's bytes in this
category ÷ max in category (largest app fills the track), single category
color; · bytes (value 13 right tabular) · share % (11 secondary). All
apps with >0 in the category, desc; zero-byte apps omitted (they'd be
invisible bars anyway). Row click/Enter → App detail (hero's category
chips give the cross-category context). Segment switcher keeps scroll
position per category (ViewModel state), Left/Right cycles segments.

────────────────────────────────────────────────────────────────────────────────
G. DATA, STATES & FLOWS (ViewModel singleton — upstream `lib/ViewModel.js` pattern)
────────────────────────────────────────────────────────────────────────────────────────

QML singleton `MosaicStore`: `snapshot`, `viewStack` (["overview"] /
push "app:<id>" / "cat:<name>"), `scanState` (idle|running|error),
`searchQuery`, `formatBytes()` (units GB/MB/KB, 1 decimal, tabular-safe;
`≥ ` prefix flag), `categoryColor(name)`.

- **Open = instant**: load the cached snapshot file synchronously at
  Component.onCompleted (43 ms measured) — popup paints with data, never
  a skeleton. Rescan is ALWAYS explicit (header button / Ctrl+R); the
  first-ever open (no cache) shows the empty state with a primary
  **Scan applications** button.
- **Rescan (single-flight)**: trigger returns `{busy:true}` if already
  running → UI no-ops + inline note "Scan already running" (3 s fade);
  header button becomes Cancel (cancels cleanly; snapshot stays last-good).
  During scan: header state chip `Measuring…` + spinner; list stays
  interactive (dim 0%, NO modal veil); on completion numbers swap in
  place with no animation (Linear rule), `as of` updates.
- **Error**: red dot in header + last-error message in the Meta card;
  data stays last-good; Retry re-triggers rescan. Never a dialog.
- **Chip ↔ popup sync**: both read MosaicStore.scanState — chip spinner
  and header Cancel are the same state.

────────────────────────────────────────────────────────────────────────────────
H. KEYBOARD & ACCESSIBILITY
────────────────────────────────────────────────────────────────────────────────────────

Global (popup root, one handler per signal per component per file):
**↑/↓** move list/category-segment focus · **Enter** open focused app /
activate focused arc-legend row · **←** back one view (same as ‹ and
Backspace) · **Esc** pop one view; on Overview, close popup · **Ctrl+R**
rescan (Cancel while running) · **/** focus search (Overview) · **E**
toggle evidence on the focused path card · **←/→** in Category view cycle
segments. Focus: visible Kirigami-style focus ring on rows/segments;
rows carry `Accessible.name` = "Brave, 15.1 gigabytes, complete";
arcs are reachable via their legend twins (arcs themselves aren't focus
items — 26px ring targets are too thin). All interactive targets ≥ 24px.

────────────────────────────────────────────────────────────────────────────────
I. FILE MAP & RULES OF ENGAGEMENT
────────────────────────────────────────────────────────────────────────────────────────

```
contents/ui/main.qml          root; cfg alias exposed HERE (popup QML has no
                              Plasmoid context property); compact/full wiring
contents/ui/Chip.qml          compact representation (§C)
contents/ui/MosaicPopup.qml   fixed frame + header + StackLayout nav (§A)
contents/ui/OverviewPage.qml  §D   contents/ui/DonutCanvas.qml  §D canvas
contents/ui/AppDetailPage.qml §E   contents/ui/PathCard.qml     §E
contents/ui/CategoryPage.qml  §F   contents/ui/AppRow.qml       §D/§F rows
contents/ui/MosaicStore.qml   singleton (§G) + StatChip.qml
contents/config/main.xml      KConfigXT: heroAccentColor, showDonut
```

Fleet rules baked in: PC3 unversioned import; `Kirigami.Units.smallSpacing`
(and /2); no `smallRadius`; canvas = logical px + imperative canvasSize
resync + Text labels outside the canvas; popup QML gets no Plasmoid
context — `cfg` alias on main.qml root; no modal dialogs anywhere; popup
opens instantly from cache, all scans explicit + single-flight.

────────────────────────────────────────────────────────────────────────────────
J. RISKS & OPEN QUESTIONS
────────────────────────────────────────────────────────────────────────────────────────

1. **Frozen popup keys** — first-run size may write popupWidth/popupHeight;
   if the frame ever changes, delete both appletsrc keys (runbook §A).
2. **Donut canvas on DPR 2** — logical-only coords + canvasSize resync is
   the proven sysmon recipe, but annular sectors are new geometry; harness
   gate at DPR 2 before merge.
3. **Colorblind blue↔teal** — weakest pair under tritanopia; carried by
   labels/order/position, but the simulation-screenshot gate is mandatory,
   not optional. If it fails: shift Data to `#2ee6a8` (greener) or Config
   to `#7fb7ff` and re-verify.
4. **Treemap deferral** — Greg loves upstream's tiles; v0.1 ships the
   ranked list. Flag explicitly in the PR so the omission reads as a
   staged decision, not a loss.
5. **254-row ListView** — delegate must stay flat (no per-row Loaders);
   if frame drops appear in the harness, virtualize evidence disclosures
   (Loader on expand only).
6. **`xdg-open` from the popup** — runs via the host CLI's action lane;
   if it steals focus the popup closes — acceptable (folder opens), but
   verify it doesn't error silently.
7. **Open Q1**: exact hero accent color default — `Kirigami.Theme.textColor`
   vs highlight color (config default = highlight; cheap to change).
8. **Open Q2**: should the Overview list group unmapped apps (232 of 254)
   under a collapsible "Not yet mapped ▸" section instead of interleaving
   them as 0-byte rows? v0.1: interleave at 0 B (simplest honest view);
   revisit after dogfooding.
