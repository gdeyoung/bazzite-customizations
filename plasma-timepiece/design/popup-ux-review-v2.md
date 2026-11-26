# Time Piece — Popup + Chip UX Review & Redesign Spec (v2)

Corrective UX pass over the Plasma 6 port that shipped 2026-10-30. Evidence base:
`contents/ui/PanelPopup.qml` (657 lines), `contents/ui/main.qml` (280 lines),
`contents/ui/TimerPill.qml`, `contents/ui/Model.js`, `contents/config/main.xml`,
and the two scale-1 harness shots (`tp-popup-s1-us.png`, `tp-chip-s1-b.png`,
popup renders ~420×530 px at 1x). Method: single-context design review (code +
screenshots); no live-browser pass — native QML surface, text-only review.

Design constants adopted fleet-wide (sysmon v0.8, decided today): **hero 24 /
title 14 / body 12 / micro 11 (caps + letterSpacing)**. This spec maps every
timepiece text to that scale.

---

## A. Critique, prioritized

### P0 — layout/UX defects

**P0-1. ~44px dead band under the date hero.**
`PanelPopup.qml` L136–150: the "Back to today" `Act` always occupies
`height: heroDate.height` (~40px at GU*2.2) even when `enabled: false` (the
default state — you're on the current month). It is the single largest vertical
gap in the popup and sits between the two sections that most need grouping
(date header, world clocks). Shot: visible as an empty band under "October 30"
before the ET/CT row.

**P0-2. Width floor breaks the width authority and every left edge.**
L94–96: `contentWidth = max(gridColumn.implicitWidth, GU*24) + largeSpacing*4`.
The grid is ~344px but `GU*24` ≈ 420 dominates, so the popup is ~76px wider
than its content. The grid centers inside that slack while the world-clock row,
year bar, and timer section span the full width — three different content
margins in one column. Shot: world-clock row "hugging the left edge" while the
grid floats centered; the whole column reads off-axis. (The comment at L90-93
says "the month grid defines the natural width" — the floor contradicts it.)

**P0-3. Hierarchy inversion: static date outranks live timer; viewed month is labeled below the grid.**
(a) Date hero is `GU*2.2` bold (~35–40px) — the largest text in the widget —
while the live mm:ss readout is 24px (L514). The date is ambient (already in
the chip + tooltip); the readout is the state the user acts on. Shot: visual
weight "October 30" ≫ "10:00" ≫ everything. Also off the fleet scale (no 35px
tier exists).
(b) The month being *viewed* is labeled in a row **below** the 6-row grid
(L331–361), with ‹ › pills pinned to the popup's far edges ~180px from the
label. Stepping to November changes nothing at the top (still says
"October 30") and the only confirmation is a small label under the grid. Shot:
"arrows excessively far from the label, reading as disconnected."

**P0-4. Chip: no internal hierarchy, oversized default, latent multi-line misalignment.**
`main.qml` L243–274. The whole date+time string is ONE `Text` at
`Kirigami.Theme.defaultFont` (L255–260) — date and time carry identical
weight/color. Default format `dddd, [UM] [OD] h:mm AP` (main.xml L6) renders
"Friday, OCT 30th 8:54 PM" ≈ 24 chars ≈ 150–200px wide in a 3-chip center
group. Shot: "all three strings same size and weight, no hierarchy — the time
is not emphasized," near-zero edge padding. Latent bug: the timer suffix
anchors `verticalCenter` (L261–270); with any multi-line custom format
(displayText contains `\n`) the one-line suffix floats between the two lines —
shot shows the same mid-gap/baseline-mismatch symptom next to a stacked clock.

### P1 — significant confusion / polish-visible defects

**P1-5. Timer header: tabs vertically misaligned + idle label duplication.**
L398–441: header `Item` height = `sectionTitle.implicitHeight` (~13px) but the
tab Row is ~24px tall anchored right with no `verticalCenter` — it overflows
the item's bottom, rendering lower than the title. Shot: "stray tiny TIMER
label floats at far left, vertically misaligned with the tab buttons." Also,
idle on the TIMER tab prints "TIMER" as the section title AND "TIMER" as the
selected tab — the same word twice in one row.

**P1-6. Hidden week-start toggle on the "W" header.**
L253–266: the "W" column header is a click target (`run:
applet.toggleWeekStart`) with no visual affordance, hover state, or tooltip.
Pure recall, zero discoverability. Settings already expose weekStartDay
(config.qml L184–188) — the hidden control adds a second, invisible path.

**P1-7. Primary verbs don't read as primary.**
`TimerPill.qml` L19–36: `prominent` only recolors the *text* (toneColor);
border stays hairline, fill stays transparent until hover. Shot: START is
"dark with blue text" — weaker than the selected TIMER tab next to it, which
has border + fill + colored text. The most important control in the section
has the least surface.

**P1-8. World-clock row: density and grouping.**
L155–189: a left-aligned `Flow` at the full popup width; labels at `smallPx`
(~10px, below fleet micro 11) with ls1, times at defaultPx. Reads as one
run-on string "ET 10:11 PM CT 9:11 PM …"; the row's left edge aligns with
nothing (see P0-2). Hard requirement (ET/CT/MT/PT) survives; presentation
doesn't scale visually.

**P1-9. Year-progress labels collide with the track; asymmetric insets.**
L219–238: track inset `leftMargin: GU*2, rightMargin: GU*1.5` (asymmetric),
"2026" left / "83%" right at the same baseline as a vertically-centered track
— labels sit hard against the track ends with no gap, and the track aligns
with nothing else in the column. Shot: "labels visually collide with the
bar's endpoints."

### P2 — polish

- **P2-10.** Week column over-wide (`GU*1.6` ≈ 29px for ≤2 digits) and center
  alignment + letterSpacing makes the "W" optically off-axis vs the numbers
  (shot: "W header not aligned with the numbers below it").
- **P2-11.** Hero glyph `󰃭` at `GU*2` — nerd-font dependency, carries no
  information the adjacent text doesn't. Drop it and the dependency.
- **P2-12.** Uniform `smallSpacing*2` (~8px) between ALL major sections
  (L114) — no section rhythm; the popup reads as one continuous strip.
- **P2-13.** Weekday header bold at smallPx caps ls1 — heavy for a caption
  tier; fleet micro is regular.
- **P2-14.** Month label fixed `width: GU*8` with centered text (L340) —
  unnecessary now the label moves into a nav unit (see B4).
- **P2-15.** Dead code: `moveYear()` (L61) has no caller. Remove with the
  redesign or leave; flag only.

---

## B. Redesign spec

Guiding decision: **the timer readout is the only hero (24px).** Date is
title tier. Everything explanatory is micro caps. One content width — the
grid's — for every section. Nav moves above the grid where every calendar a
user has ever used puts it.

### B0. Tokens (top of PanelPopup.qml)

```qml
// Fleet type scale (sysmon v0.8, 2026-10-30): literal px on purpose —
// cross-widget consistency beats per-theme font scaling here. Popup geometry
// still scales via Kirigami.Units.
readonly property int heroPx: 24   // bold        — timer/pomodoro readout ONLY
readonly property int titlePx: 14  // DemiBold    — header date
readonly property int bodyPx: 12   // regular/bold — day numbers, zone times
readonly property int microPx: 11  // caps + ls   — every label/caption/pill

readonly property int padH: Kirigami.Units.largeSpacing * 2        // 16 @1x
readonly property int padV: Kirigami.Units.largeSpacing * 1.5      // 12 @1x
readonly property int sectionGap: Kirigami.Units.largeSpacing * 2  // 16 @1x
readonly property int innerGap: Kirigami.Units.smallSpacing * 2    // 8 @1x
```
Delete `smallPx`/`defaultPx` aliases; replace all uses per B2–B6.

Typography map (complete):

| Element | Tier | Weight | ls | Case |
|---|---|---|---|---|
| Timer/pomo readout | hero 24 | bold | 1 | — |
| Header date "Friday, October 30" | title 14 | DemiBold | 0 | sentence |
| Day numbers | body 12 | bold only today | 0 | — |
| Zone times | body 12 | bold | 0 | — |
| Zone labels | micro 11 | regular | 1 | caps |
| Year progress "83% OF 2026" | micro 11 | regular | 1 | caps |
| Weekday header | micro 11 | regular | 1 | caps |
| Week numbers / "W" | micro 11 | regular | 0 | — |
| Month label "NOVEMBER 2026" | micro 11 | regular | 1.5 | caps |
| TODAY pill | micro 11 | bold | 1 | caps |
| Section titles ("TIMER · RUNNING") | micro 11 | regular | 2 | caps |
| Tabs, TimerPill labels | micro 11 | bold | 1 | caps |
| Pomo summary | micro 11 | regular | 1 | caps |

Chip stays on `Kirigami.Theme.defaultFont`/`smallFont` deliberately: it sits
between the stock-ticker and weather chips; panel-surface consistency is with
its neighbors, popup-surface consistency with the fleet scale. Documented
exception.

### B1. Popup frame

- **Width authority (fixes P0-2):** delete the `GU*24` floor.
  `contentWidth = gridColumn.implicitWidth + padH * 2` (~376px @1x; call it
  ~380). Grid, world-clock cells, year track, phase bar, rail, and verb rows
  all span the same content width — one left edge, one right edge.
- `Layout.preferred/maximumWidth: contentWidth` (keep the pattern).
- `Layout.preferred/minimumHeight: contentColumn.implicitHeight + padV * 2`
  (~450px total, down from ~530).
- `contentColumn`: `x: padH; width: scroll.width - padH * 2;
  spacing: sectionGap` (16px between major blocks — fixes P2-12). Internal
  sub-columns keep their own 2–8px spacings.
- Flickable: keep (bounds, clip, interactive-when-overflowing) — the safety
  net for huge theme fonts.

### B2. Header block (replaces hero Row + dead Act + year Item; fixes P0-1, P0-3a, P1-9, P2-11)

Two elements, total height ~25px:

1. Row: `Text` "Friday, October 30" — `Qt.formatDate(applet.now, "dddd, MMMM d")`,
   titlePx, `font.weight: Font.DemiBold`, fg, LEFT-aligned, baseline-anchored
   to (2). Right-anchored: `Text` `"83% OF 2026"` microPx caps ls1 muted
   (`yearProgressPercent`), baseline-aligned to the date.
2. 4px below: year track — `Rectangle` full content width, height 3, radius
   1.5, `trackFill`, with accent fill `width: parent.width * yearProgress`;
   keep the 160ms width Behavior. No insets, no flanking labels (the % label
   moved into the row above).

Borrow: the year-rule-as-divider concept, track colors, fill animation.
Replace: glyph+35px hero → 14px title; flanking labels → one right-aligned
caption; symmetric full-width track. Remove: the "Back to today" Act entirely
(replaced by B4's TODAY pill).

### B3. World clocks (fixes P1-8)

Keep `ZoneClocks` engine, `TZ_HUES` label pass, bold fg times, "—" fallback
(≤60s after open / on zone failure) — all borrowed verbatim.

Replace the `Flow` with equal-width cells:
- `Row { width: parent.width; Repeater { model: applet.worldClocks; delegate:
  Item { width: parent.width / applet.worldClocks.length; height: 30 } } }`
- Cell (stacked, centered): zone label microPx caps ls1, hue-colored
  (Palette.TZ_HUES[index], muted past index 4) on top; 2px gap; zone time
  bodyPx bold fg below. Both centered horizontally in the cell.
- Four cells → 4 equal columns aligned to the grid's content edges; five
  zones (config cap) still fit: cell ≈ 69px, "10:11 PM" at 12 bold ≈ 58px.
- Row hidden when `worldClocks.length === 0` (unchanged).

### B4. Calendar (fixes P0-3b, P1-6, P2-10/13/14)

Keep entirely: `Model.monthGrid` six-row grid, UTC walking, ISO week numbers,
today = 1px accent outline + bold digits ("lit-up block shouts over a grid
this quiet" — correct call), weekend muted, out-of-month 0.35 alpha,
`cellWidth: GU*2.4`, `cellHeight: GU*1.6`, 2px inter-cell spacing.

Restructure around it:

- **Nav row ABOVE the grid** (height 28): a centered unit
  `[‹ 28×24] 8px [NOVEMBER 2026] 8px [› 28×24]` as one Row anchored
  `horizontalCenter`. Month label: `Qt.formatDate(..., "MMMM yyyy")`
  uppercased, microPx caps ls1.5, fg, no fixed width. ‹/› stay TimerPills
  (`moveMonth(∓1)`), explicit `width: 28; height: 24`.
- **TODAY pill**: microPx bold caps ls1 accent text + hairline border +
  `Qt.alpha(accent, 0.18)` fill (same idiom as a selected tab), ~24px tall,
  `anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter`,
  `visible: viewYear !== now-year || viewMonth !== now-month`, `run:
  goToToday`. Replaces the dead band AND the below-grid month row.
- **Weekday header**: microPx *regular* (not bold) caps ls1 muted, cells
  centered as now. **Remove the click-to-toggle Act from "W"** (settings
  remain the one path; config.qml exposes it).
- **Week column**: `weekColumnWidth: GU*1.2` (~22px), numbers AND the "W"
  label right-aligned with `rightPadding: 4` (kills the optical off-axis
  center); muted microPx, no letterSpacing on the digits.
- Gutter between week column and day cells: keep `smallSpacing * 2`.

Order inside the block: nav row → 4px → weekday header → 2px → 6 week rows.

### B5. Divider

`Rectangle { width: parent.width; height: 1; color: Qt.alpha(fg, 0.12) }` as
its own row in contentColumn between calendar and timer (the 16px sectionGap
on each side provides the air). Gives the timer section a floor without
boxing it in a card.

### B6. Timer section (fixes P1-5, P1-7)

Keep the whole state machine verbatim: `idleOnly`, `phaseColor`,
`phaseTotalMin`, `remainingMs`, `phaseFraction`, all visibility rules from
design/timer-ux-spec.md §4, the 6px phase dot + pulse, phase bar 3px, cycle
rail (4 segments, full content width), pomo summary line, verbs Row and every
state's verb set. Borrowed as-is.

Changes:

1. **Header** — `Item { height: 24 }`, both children
   `anchors.verticalCenter: parent.verticalCenter` (fixes the overflow).
   - Idle: tabs Row anchored LEFT (no section title at all — the tabs ARE the
     label; kills the TIMER/TIMER duplication). Tabs: height 24, microPx bold
     caps ls1; selected = accent text + accent border +
     `Qt.alpha(accent, 0.18)` fill; unselected = fg text + hairline border
     (current tab styling, borrowed).
   - Non-idle: title Text left (microPx caps ls2, phase-colored when
     pomodoro, muted for manual states) + 6px dot 4px after it; tabs hidden.
2. **Readout**: heroPx 24 bold ls1 (was `GU*1.5` — same 24px, now the literal
   token). It is now the largest text in the popup (the date dropped to 14).
3. **Steppers**: keep flanking fixed slots `width: GU*3.2`, `spacing:
   smallSpacing*3` to the readout, visibility/dimming rules unchanged.
4. **Verbs** — TimerPill gains a real primary treatment (fixes P1-7):
   `prominent: true` ⇒ persistent `color: Qt.alpha(toneColor, 0.18)` fill +
   `border.color: toneColor` (not just on hover) + toneColor bold text.
   Ghost verbs unchanged (hairline border, fg text, hover fill). Primary
   verb == selected-tab idiom: one "this is active/choose me" language.
5. **TimerPill.qml**: `font.pixelSize: 11` literal (replaces `GU*0.62`),
   microPx bold ls1; min height stays `max(text + 2*smallSpacing, GU*1.5)`.
6. Phase bar / rail / summary: `width: parent.width` (now grid-aligned).

### B7. Chip (main.qml + main.xml; fixes P0-4)

Keep: single-Text display driven by `clockFormat` (the port's premise —
format freedom survives), hover highlight, suffix content (" · mm:ss" /
" · F mm:ss" / " · done"), urgent color on done, opacity 0.75, smallFont
suffix, full-area MouseArea.

Change:
1. **Default format**: `ddd [UM] [OD] · h:mm AP` → "Fri OCT 30th · 8:54 PM"
   (20 chars vs 24; drops the full weekday name and comma, adds a `·`
   separator the suffix already uses). Existing installs keep their stored
   value — changing the default only affects fresh ones; note for the owner
   to update the setting if they want the shorter chip.
2. **Suffix alignment**: `anchors.verticalCenter` →
   `anchors.baseline: <dateTextId>.baseline` — correct for single-line
   formats (the default), first-line-aligned and predictable for custom
   multi-line ones (documented behavior, see D).
3. **Padding**: `implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 4`
   (2 units per side, was 3 total).

---

## C. Structure tree (new PanelPopup.qml)

```
Item panel
├─ tokens: heroPx/titlePx/bodyPx/microPx, padH/padV, sectionGap/innerGap,
│  palette colors (keep), labelLocale (keep), view/viewMonth, timerTab,
│  timerDisplayMs, cell metrics (cellW GU*2.4, cellH GU*1.6, weekCol GU*1.2)
├─ contentWidth = gridColumn.implicitWidth + padH*2        // no floor
├─ Layout.preferred/maximumWidth: contentWidth
├─ Layout.preferred/minimumHeight: contentColumn.implicitHeight + padV*2
└─ Flickable scroll (fill, clip, StopAtBounds, interactive on overflow)
   └─ Column contentColumn { x: padH; width: scroll.width - padH*2; spacing: sectionGap }
      ├─ headerBlock (Column, spacing 4)
      │  ├─ Row: Text dateTitle(titlePx DemiBold fg, left)
      │  │        Text yearPct(microPx caps ls1 muted, right, baseline≈dateTitle)
      │  └─ Rectangle yearTrack (3px, full width, trackFill)
      │     └─ Rectangle fill (accent, width≈frac, Behavior 160ms)
      ├─ worldClocks Row (width: parent.width, visible: zones>0)   // replaces Flow
      │  └─ Repeater → Item cell (w: parent.width/n, h: 30)
      │     ├─ Text zoneLabel (microPx caps ls1, TZ hue, centered)
      │     └─ Text zoneTime (bodyPx bold fg, centered, 2px below)
      ├─ ZoneClocks (visible:false — unchanged engine)
      ├─ calendarBlock (Column, spacing 2–4)
      │  ├─ navRow (Item, h: 28)
      │  │  ├─ Row (horizontalCenter, spacing 8): ‹ pill(28×24) · monthLabel(microPx
      │  │  │   caps ls1.5) · › pill(28×24)
      │  │  └─ TODAY pill (right-anchored, visible: view≠today, run: goToToday)
      │  ├─ headerRow: Text "W" (microPx muted, right-align+4) · gutter(8) ·
      │  │   7× Text weekday (microPx regular caps ls1 muted, centered)   // no Act
      │  └─ Repeater 6× weekRow: Text week# (microPx muted, right-align+4) ·
      │      gutter(8) · 7× dayCell (Rect GU*2.4×GU*1.6, radius, today:
      │      1px accent border + bold; day text bodyPx; weekend muted; out 0.35)
      ├─ divider Rectangle (1px, alpha(fg,0.12), full width)
      └─ timerSection (Column, spacing: smallSpacing)   // state machine verbatim
         ├─ headerRow (Item h:24, both v-centered)
         │  ├─ idle: tabs Row LEFT — [TIMER][POMODORO] (24px, microPx bold ls1,
         │  │        selected: accent text+border+0.18 fill)
         │  └─ active: Text title (microPx caps ls2, phaseColor/muted) + dot 6px
         ├─ heroRow (centered, spacing smallSpacing*3): −5M pill(GU*3.2 slot)
         │  │   · Text readout (heroPx bold ls1) · +5M pill
         ├─ phaseBar (3px full width; fill=frac; Behaviors 300ms/color 250ms)
         ├─ cycleRail (4 segments, full width, pomodoro runs only)
         ├─ pomoSummary (microPx caps ls1 muted, idle+pomo tab only)
         └─ verbsRow (centered, spacing 8): 1–2 TimerPills per state;
            prominent = toneColor text+border+0.18 fill
```

Chip (main.qml): `Row [ Text display (defaultFont, hover→highlight) ·
Text suffix (smallFont, 0.75, baseline-anchored, urgent when done) ]`,
padding smallSpacing*2 per side, default format `ddd [UM] [OD] · h:mm AP`.

---

## D. Risks & edge cases

1. **DST, zone row**: ZoneClocks polls each zone every 60s — around a 2am
   flip the row can be ≤60s stale and briefly mixed-convention across
   ET/CT/MT/PT. Accept (existing behavior); unchanged.
2. **DST label truth**: labels are user-set strings; `MT:America/Phoenix`
   will read MT but not spring forward (MST year-round). Config semantics,
   not a UI bug; document in README if it bites.
3. **Manual timer / pomodoro vs DST & reboots**: endsAt is absolute epoch-ms
   (persisted) — immune to clock shifts and plasmashell restarts by design.
   Unchanged.
4. **Removing the hidden "W" toggle**: muscle-memory users lose it; the
   settings dialog (config.qml L184–188) keeps weekStartDay. One path beats
   two when one is invisible.
5. **TODAY pill replaces the dead band**: must appear the instant
   viewYear/viewMonth ≠ now (reuse the old Act's `enabled` expression as
   `visible`). Verify the popup doesn't change height when it appears (it's
   inside the fixed 28px nav row — no reflow).
6. **Fixed-px fonts vs theme scaling**: users with large theme fonts get
   24/14/12/11 text in GU-scaled (larger) cells — airier grid, not clipped;
   the Flickable catches extreme cases. Accepted per the fleet-consistency
   decision (sysmon v0.8 precedent).
7. **Width floor removal**: popup narrows ~420→~380. Widest timer strings
   ("POMODORO · LONG BREAK · 4 OF 4" at micro 11 ls2 ≈ 240px) and the
   verb/tab rows fit inside ~344px content. Nothing else consumed the floor
   (checked: only contentColumn children inherit width).
8. **Multi-line custom chip formats**: suffix baseline-aligns to the FIRST
   line (QML cannot target a Text's internal line). Documented behavior;
   default format is single-line.
9. **Zone label overflow**: labels cap at 14 chars (Model.parseWorldClocks);
   at micro 11 a 14-char label + time in a ~69px cell (5-zone case) can
   exceed the cell — ET/CT/MT/PT (default, 4 zones) measure ~78px worst-case
   vs 86px cell. If longer custom labels matter later, elide the label Text;
   do not shrink the time.
10. **Pomodoro phase flip while popup open**: title color crossfades
    (existing ColorAnimation), bar/rail widths animate; SKIP→ and checkFires
    share the transition table — unchanged, retest SKIP at 00:00.
11. **ISO week numbers under Sunday-start (US default)**: rows are
    Thursday-anchored (Model.js L253–274) — numbers are correct ISO; a row
    can straddle two ISO weeks. Existing, deliberate; unchanged.
12. **Nerd-font glyph removal**: header no longer depends on the 󰃭 glyph
    being installed — one fewer font dependency (improvement, listed for the
    changelog).
13. **Default-format change scope**: kcfg defaults apply to fresh configs
    only; the current install keeps "dddd, [UM] [OD] h:mm AP" until the
    setting is edited. Call this out in the commit message.
14. **Nav-row relocation**: month nav above the grid deviates from the
    Omarchy original (below). Intentional — matches every mainstream
    calendar; note in README's porting-differences section if one exists.

## E. Implementation checklist

- [ ] B0 tokens added; smallPx/defaultPx uses replaced file-wide
- [ ] P0-1 dead Act deleted; P1-6 W-click Act deleted
- [ ] contentWidth floor removed (P0-2); contentColumn x/width/spacing set
- [ ] Header block built (P0-3a); glyph dropped (P2-11)
- [ ] World-clock Flow → equal-width stacked cells (P1-8)
- [ ] Year labels merged into header row; track full-width (P1-9)
- [ ] Nav row + TODAY pill above grid; below-grid row deleted (P0-3b, P2-14)
- [ ] Timer header height 24 + v-center; idle title removed (P1-5)
- [ ] TimerPill: microPx literal; prominent fill+border (P1-7)
- [ ] Divider before timer section (B5)
- [ ] Chip: default format, baseline anchor, padding (P0-4)
- [ ] Manual test: all 9 timer/pomo states, month step ±, TODAY appears,
      zone failure "—", 1x + 125% font scale, popup height stable on state
      changes
