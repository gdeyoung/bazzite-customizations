# 04 — Evidence Bank: Data-Dense Dashboards & Live-Updating Widget Surfaces

Fleet context: KDE Plasma 6 widgets + web portals (stock watchlist/portfolio, system monitor, Tailscale census, weather, backup status). Companion to the general web-UX bank (progressive disclosure levels, Hick/Fitts/Von Restorff, forms label placement, loading ladder <1s / 2–10s / >10s, WCAG 2.2, motion 100 / 200–300 / 400ms) — none of that is re-derived here. This file goes deeper into data-display and monitoring-surface mechanics.

**Citation scheme.** Every claim cites a source ID + tier, e.g. `[S12·T1]`. The register at the end maps IDs to full URLs. Tiers:
- **T1** primary/authoritative — standards (W3C/WAI), official design systems & tool docs (Grafana, Apple, KDE, GNOME, Microsoft, Carbon, Ant Design, Qt), tool authors' own texts (Tufte, Few), academic/health authorities.
- **T2** secondary — empirical UX research houses (NN/g), peer-reviewed-adjacent studies (Enders), established consultancies, vendor docs summarizing practice.
- **T3** tertiary — forums, individual blogs, unverified.
Verification labels: **VERIFIED** = text read at the source this session; **SNIPPET** = official-page text seen only via search-result snippet (JS-walled page); **COMPUTED** = arithmetic run here (WCAG formulas); **FLAGGED** = contested or unverified, treat as hypothesis.

---

## 1. Glanceability

### 1.1 What "glanceable" formally means
- Few's canonical definition (verified verbatim from the author's own PDF): *"A dashboard is a visual display of the most important information needed to achieve one or more objectives; consolidated and arranged on a single screen so the information can be monitored at a glance."* [S1·T1·VERIFIED]. NN/g's operational version: dashboards are "collections of data visualizations, presented in a single-page view that imparts at-a-glance information on which users can act quickly… their goal is not to facilitate exploration" [S8·T2·VERIFIED].
- **The "5-second rule"** — that a user should extract what matters in ~5 seconds — is widely attributed to Few's *Information Dashboard Design* (2006/2013). The exact "five seconds" phrasing could **not** be verified verbatim in the book text available this session [S2·T1·FLAGGED]; secondary sources state it plainly ("your dashboard should provide the relevant information in about 5 seconds" [S3·T3·SNIPPET]). Treat "≈5s to the verdict" as the community-consensus reading of Few's "at a glance," not as a lab-measured constant.
- False-premise correction: a glance test measures *monitoring* speed (is anything abnormal?), not *reading* speed (what exactly is the value?). Design for: verdict in one fixation, details on demand (see master-detail, §6).

### 1.2 Preattentive attributes — the <250ms channel
- The low-level visual system pops out certain attributes — hue, orientation, length, size, added marks — without serial search; a viewer "can tell at a glance whether the target is present or absent" [S7·T1·VERIFIED]. Standard literature timing: a single fixation, on the order of 200–250ms (Treisman & Gelade's feature-integration line, surveyed in S7) [S7·T1, timing FLAGGED-not-in-extract].
- Critical implication for dashboards: **single-attribute pop-out works; conjunctions do not.** A red cell among green ones pops out; "large AND red" requires serial attention [S7·T1·VERIFIED concept]. So encode *one* preattentive channel per alert dimension (color for status, weight/size for magnitude), and never rely on a color+size combination to be noticed in parallel.
- NN/g's dashboard-specific advice: use preattentive-friendly encodings (position/length/color intensity) for overviews; a Dundas call-center example is praised for using *shape* to distinguish categories and reserving intensity for secondary info [S8·T2·VERIFIED].

### 1.3 Layout: where the glance lands
- Eyetracking on 232 users: scanning starts with a horizontal pass across the **upper** content area, a second shorter horizontal pass, then a vertical scan down the **left edge** (F-pattern) [S9·T2·VERIFIED]. KDE's HIG says the same in design-system terms: place primary content/actions in the **top-leading** corner (top-left in LTR); users treat it as the first thing to focus on [S26·T1·VERIFIED].
- Few's book: dashboards used to "feature exceptional conditions, both good and bad"; ranking + brief textual verdicts are legitimate primary content, not a fallback [S2·T1·VERIFIED excerpt].

### 1.4 The glanceable unit = headline number + trend + verdict (matches standing preference)
- Pattern: each tile/row should answer three things in one fixation: *what is it now* (number), *which way is it moving* (sparkline/delta), *is that expected* (status vs threshold) [synthesis of S1 (monitor at a glance), S8 (act quickly), S12 (thresholds), S4 (sparkline+number pairing)].
- Grafana best practices frame it as: a dashboard should "tell a story or answer a question," and the USE method (Utilization/Saturation/Errors) picks *which* numbers earn tile status [S14·T1·VERIFIED].
- Apple HIG: "An effective chart highlights a few key pieces of information in a dataset, helping people gain insights and make decisions" [S16·T1·VERIFIED] — i.e., a chart (or tile) that shows everything highlights nothing.

**Do:** most important metric top-left; one preattentive channel per alert dimension; every tile carries its own micro-conclusion (verdict), not just raw values.
**Don't:** decoration that isn't data (Few's gauge/stoplight critique, S1/S2); encoding that requires conjunction search; hiding the verdict behind interaction.

---

## 2. Sparklines & Small Multiples

### 2.1 Definition and the micro/macro contract
- Tufte (verified verbatim): *"A sparkline is a small intense, simple, word-sized graphic with typographic resolution. Sparklines mean that graphics are no longer cartoonish special occasions with captions and boxes, but rather sparkline graphics can be everywhere a word or number can be: embedded in a sentence, table, headline, map, spreadsheet, graphic. Data graphics should have the resolution of typography."* [S4·T1·VERIFIED].
- The contract: a sparkline is read *as a word* (macro shape: up/down/volatile/choppy) while remaining data-dense (micro readings). It replaces/annotates a number when shape matters; it never replaces the number when precision matters. Tufte's own examples pair the sparkline with the current value and summary stats inline [S4, S5·T1·VERIFIED].

### 2.2 Sizing — concrete numbers
- Tufte's implementation guidance (from his own forum, verified): aim for the line **"the height of the text (try to aim for 0.1in or about 7pt), and also trying to bank to 45 degrees"** [S5·T1·VERIFIED]. Conversions: 0.1in ≈ 9.6px @96dpi; 7pt ≈ 9.3px. A worked example on the same page uses `AspectRatio -> 1/6` (height = width/6) [S5·T1·VERIFIED].
- Practical read-across for our widgets (Tufte's numbers are print-scale; screens are viewed farther away): data-band height ≈ the x-height-to-cap-height of the row's text, ~12–20px at our 17px base type; width 6:1 to 3:1 depending on volatility (wider = flatter = noisier trends look calmer; banking ~45° keeps slopes legible). Community distillation says the same: "Height ≈ x-height of surrounding text (~14–20px)" [S5a·T3·SNIPPET]. **No controlled study pins an upper pixel limit** — above ~2 lines of text height it stops being a sparkline and becomes a chart with axes needs (FLAGGED: judgment from Tufte's definition, no counter-evidence found).
- Don't: axis lines, tick marks, gridlines, or borders on sparklines (violates "typographic resolution"); ~60+ data points without aggregation at small widths turns into noise.

### 2.3 Last-value emphasis and range context
- End the sparkline with a **dot + the current value printed at full weight/color** at the right (Tufte's financial examples print the latest number; implementers on Tufte's site describe "red dot with red number" as the pattern [S5·T1·VERIFIED]). Rationale: the last point is the glance payload; un-emphasized it's just the rightmost pixel.
- **Baseline/reference band:** when "normal" exists (CPU temp, latency SLO, price range), shade the normal band behind the line (light 5–10% alpha fill); Tufte's medical sparkline examples show norms as a shaded band [S5·T1·VERIFIED "norms in yellow" implementation; concept T1]. Rules: y-range must cover the band (auto-scaling to data min/max erases the context that makes a trend interpretable).
- When a **number beats a sparkline**: precision tasks (exact price, PID count). When a **sparkline beats a number**: direction/volatility/shape tasks (is load spiking, is memory leaking). Best = both: number now + sparkline history, per Tufte's word-sized pairing [S4·T1·VERIFIED].

### 2.4 Small multiples
- Grids of identically-scaled mini-charts so the eye compares across series/hosts — Tufte's small-multiple concept (Envisioning Information); modern practice: Grafana repeated panels/rows with shared thresholds; the comparison only works if **scales, colors, and time windows are shared** across the grid [S14·T1 concept; consistency requirement is definitional].
- Per-row sparklines in tables are small multiples: only meaningful when all rows share y-scale or are normalized (% of own max); otherwise row A's mountain and row B's flatline mislead (FLAGGED: no formal study found; logical consequence of shared-scale requirement).

**Do:** dot + current value at the end; shaded normal-range band; shared scales across any sparkline grid; ~45° banking, 6:1-ish aspect; word-height sizing.
**Don't:** axes/ticks on sparklines; sparklines replacing the number when the number is the task; per-row sparklines with independent hidden scales.

---

## 3. Number Formatting for Scanning

### 3.1 Tabular (monospaced-width) numerals — the anti-jitter primitive
- The mechanism: proportional digits give every glyph a different advance width, so a live-updating value reflows horizontally several times a second; tabular figures are uniform-width so updates change nothing geometrically. MDN: `font-variant-numeric: tabular-nums` activates "the set of figures where numbers are all of the same size, allowing them to be easily aligned like in tables" [S17·T1·VERIFIED].
- Where it matters: any cell that repaints on a timer (prices, CPU%, clocks, deltas). Anti-pattern: centering live numbers with proportional digits — the number "swims."
- **QML-native equivalents (verified):** Qt Quick `Text` exposes `font.features : object` **since Qt 6.6** — set `font.features: ({ "tnum": 1 })` for OpenType tabular figures [S18·T1·VERIFIED]; C++ side, `QFont` OpenType feature API (`featureTags()`, `featureValue()`, `setFeature`) landed **Qt 6.7** [S19·T1·VERIFIED]. On Qt < 6.6, use a font whose default figures are tabular (most monospace UI faces) for numeric columns. Web portal: `font-variant-numeric: tabular-nums` [S17·T1].
- Right-align every numeric column (see §3.4) so the stable digit edge is the anchor even between width changes.

### 3.2 Precision discipline
- Grafana's shipped default is instructive (verified verbatim): "If you leave this field empty, Grafana automatically truncates the number of decimals based on the value. For example 1.1234 displays as 1.12 and 100.456 displays as 100." [S13·T1·VERIFIED]. Rule of thumb extracted: **~3 significant digits**, fewer as magnitude grows — enough for comparison decisions, no false precision.
- Column-consistent precision: mixed `9.1 / 10.03 / 8.766` in one column defeats magnitude comparison; fix decimals per column (CPU%: integer or 1 decimal; RAM: GiB with 1 decimal; price: currency-native 2).
- Grafana also exposes explicit per-field **Decimals** and **Unit** options as first-class panel settings — evidence that unit+precision control is a baseline monitoring-tool feature, not polish [S13·T1·VERIFIED].

### 3.3 Unit scaling (1.2K / 1.2M)
- Keep the *unitless-looking* magnitude scannable and push exact values to detail/tooltip: at >4 digits, compress to K/M/G with one decimal (`12.4K`, `1.2M`), keep the unit suffix always present (`12.4K req/s`) so K-vs-M misreads can't happen. Vendor normalization: Grafana units auto-scale (K/M) with the **Unit** standard option [S13·T1·VERIFIED]; Apple HIG charts guidance stresses tick/reference labels that "help people visually locate the position of important values" — same philosophy for numbers: label what the reader anchors on [S16·T1·VERIFIED]. (No official doc pins the exact >9,999 threshold; FLAGGED as convention — 4 digits max before suffixing.)

### 3.4 Alignment — right-align numbers, left-align text, align decimals
- Right-align numerics so magnitudes compare by place value; left-align identifiers/text; decimal-align when a column mixes precisions. Basis: accounting/table-design convention, restated across data-viz practice ("numbers in tables should be right-aligned… left-aligned numbers make comparing magnitudes harder") [S24a·T2/T3 community consensus, FLAGGED as convention — no controlled study found; expert consensus is unanimous in every source encountered].
- Never center live-updating numeric cells (jitter + breaks the right-edge anchor, §3.1).

### 3.5 Deltas: sign + arrow + color (redundant triple encoding)
- WCAG 1.4.1 (verified verbatim): *"Color is not used as the only visual means of conveying information"* — and the Understanding doc explicitly blesses redundancy: differences are acceptable when a second channel (shape or text) also carries the meaning, and even color-only distinctions pass only when relative-luminance contrast ≥ 3:1 [S20·T1·VERIFIED]. Material's dataviz guidance says it in one line: reinforce chart colors with other cues like icons; don't use color alone (official page text, seen via snippet) [S38·T1·SNIPPET].
- Concrete pattern for watchlist/monitor deltas: `▲ +2.4%` in green / `▼ −1.1%` in red / `● 0.0%` neutral — direction glyph + signed number + color, all three legible to the ~1-in-12 men with color-vision deficiency [S23·T1·VERIFIED "about 1 in 12 men"].
- Colorblind-safe pair check: our green #3fd18b vs red #f4405c differ by luminance ratio only **1.87:1** — hue carries most of the difference, so red/green is exactly the pair deuteranopes collapse; the glyph+sign redundancy is not optional. Amber #ffb02e vs green #3fd18b is **1.07:1** — nearly isoluminant: warn-vs-ok must also differ in shape/label (e.g., filled triangle vs dot, or WARN text chip) [COMPUTED, WCAG luminance formula, S21 method].

### 3.6 Delta color ≠ trend convention trap
- Finance exception (matters for the stock watchlist): in East Asian and some global finance conventions red=up/green=down; Western retail tools standardize green=up. Our fleet = Western personal tooling → green=up, but keep the arrow as the truth carrier (§3.5) so the color convention is decoration, not load-bearing [FLAGGED convention, no primary source — note in gaps].

**Do:** tnum on every ticking column; right-align numerics; ~3 significant digits, per-column fixed precision; K/M suffix >4 digits; ▲/▼ + explicit sign + color for deltas.
**Don't:** proportional digits on live values; center-aligned numbers; mixed precision in a column; color-only deltas.

---

## 4. Color for Status & Severity

### 4.1 Semantic bands — the traffic-light default, with numbers
- Grafana's shipped default thresholds (verified): **Base = green, 80 = red** (two steps; users add the amber step between) [S12·T1·VERIFIED]. Third-party Grafana guidance typically models ok <70 / warn 70–90 / crit >90 for percentages [T3 example, S12 ecosystem]. Convention: green base, amber warning band, red critical band — with **thresholds chosen from SLOs, not from the palette**.
- Grafana color-scheme list (verified) shows the canonical *ordinal* triads for value→color ramps: **Green-Yellow-Red, Red-Yellow-Green, Blue-Yellow-Red, Yellow-Red, Blue-Purple, Yellow-Blue**, plus single-shade and continuous-scheme options, with ramp selection by **Last/Min/Max** field value [S13·T1·VERIFIED].

### 4.2 Sequential vs diverging — when each
- Definitions (from the ColorBrewer ecosystem docs): **sequential** = ordered data progressing low→high; **diverging** = equal emphasis on a critical mid-range class and extremes at both ends [S25·T2·SNIPPET; tool: S24·T1 colorbrewer2.org]. Application: used-% (CPU/mem/disk) → sequential ramp, thresholds overlay status color; **deltas around zero → diverging** (red←0→green), zero itself neutral; temperature vs target → diverging around the target.

### 4.3 Accessibility minimums (dark surfaces)
- WCAG 1.4.11 Non-text Contrast (verified): visual information required to identify components and "parts of graphics required to understand the content" needs **≥3:1** against adjacent colors [S21·T1·VERIFIED]. Status-colored *text* still owes 4.5:1 (1.4.3).
- **Our palette, COMPUTED** (WCAG relative luminance):

| Foreground | #101216 near-black | #16181c | #1b1e23 | #232629 view | #2a2e35 card | #0b0c0f oled |
|---|---|---|---|---|---|---|
| pos #3fd18b | 9.56 | 9.06 | 8.52 | 7.75 | 6.95 | 9.97 |
| neg #f4405c | 5.12 | 4.85 | 4.56 | 4.15 | **3.72** | 5.34 |
| warn #ffb02e | 10.27 | 9.73 | 9.15 | 8.33 | 7.47 | 10.71 |
| info #3daee9 | 7.53 | 7.13 | 6.71 | 6.11 | 5.47 | 7.85 |

- Verdict: green and amber pass everything everywhere. **#f4405c is graphics-safe (≥3:1) on all tested darks but drops below 4.5:1 on card surfaces (#2a2e35 → 3.72, #232629 → 4.15)** — for small status *text* on cards, lighten toward **#ff6680** (4.84 on #2a2e35; 5.41 on #232629) or keep #f4405c for glyphs/bars only [COMPUTED].
- WCAG's own worked example (verified) uses *lightness* separation as the second channel: "a light green and a dark red differ both by hue and by lightness, so they would pass if the contrast ratio is at least 3:1" [S20·T1·VERIFIED]. Our pair fails that intent (1.87:1, §3.5) → lean on glyph+text redundancy, and/or pick a darker red / lighter green variant when a surface shows both.

### 4.4 Severity ordering & redundancy
- Encode severity as an **ordered** scale the eye can rank: ok < warn < crit with monotonic visual weight (e.g., green text < amber chip < red chip + bold). Grafana thresholds render stepped color on value text, cell background, line/region fills, and state-timeline regions — same semantic color reused across render targets [S12·T1·VERIFIED].
- Always pair status color with a **label or icon** (●/▲/✕, OK/WARN/CRIT, S/R in htop's convention — S sleeping, R running, D disk-sleep, Z zombie [S28·T1·VERIFIED]): 1-in-12 men [S23] + WCAG 1.4.1 [S20] make this mandatory, and htop's single-letter state column shows even TUI tools reserve a *text* channel for state.
- Dark-surface don't: pure saturated fills as cell backgrounds behind default text (kills 4.5:1); use tinted backgrounds (10–15% alpha) + colored bold text.

**Do:** thresholds from SLOs; green base / amber warn / red crit; sequential ramps for magnitude, diverging for ±deltas; ≥3:1 graphics, ≥4.5:1 status text (check cards!); icon+label redundancy always.
**Don't:** color-only status; red/green as the sole distinction (1.87:1 luminance separation); more than ~5 ordinal colors on one surface.

---

## 5. Live-Updating Surfaces

### 5.1 Refresh cadence — what the real tools ship
- Verified defaults: **btop `update_ms = 2000`, with the maintainer recommending ≥2000ms** "for better sample times for graphs" [S29·T1·VERIFIED]; **htop** update delay is set in tenths of a second, clamped 0.1s–10s (its interactive default is 1.5s; users rarely lower it) [S28·T1·VERIFIED for the clamp]; Grafana ships an auto-refresh interval menu for dashboards whose "time range includes the current time" and a "Refresh live dashboards" toggle for continuous updates; the fastest stock interval is 5s (community-documented default limit) [S15·T1·VERIFIED; S40·T3]. Windows Task Manager historically refreshes ≈1s (FLAGGED, not verified at a primary source this session).
- Working rule for our widgets: **1–5s polling reads as "live"; >10s reads as "snapshot"** (matches the fleet loading-ladder tiers); **<500ms full-table repaints read as twitchy** and defeat scanning — the sample-time argument from btop applies to our sparklines too (2s window → visible, meaningful slopes). Sub-second updates, when genuinely needed (audio meters, trade ticks), should be confined to a chart strip, not a table. [S15, S28, S29; the <500ms twitch threshold is FLAGGED judgment, no controlled study found.]
- Grafana's **"Now delay"** option exists precisely for live-data skew: "Override the `now` time by entering a time delay. Use this option to accommodate known delays in data aggregation to avoid null values" [S15·T1·VERIFIED] — i.e., mature tools treat *data latency* as a first-class display concern (see §8.3).

### 5.2 Change highlighting (flash/fade) — why and how
- Perception basis: **change blindness** — people routinely fail to notice even large visual changes unless attention is drawn to them; detection requires a transient cue or directed attention (flicker-paradigm research, Rensink et al.) [S37·T2·VERIFIED]. A table cell that silently changes from 41% to 97% between repaints is invisible unless the change itself emits a signal.
- Established implementation: enterprise grids ship first-class **cell-change flashing/highlighting** — ag-grid's `enableCellChangeFlash` flashes cells whose values changed (official docs, snippet-verified) and an "Animate slide cells" mode ghosts the previous value, "shown in a faded fashion and slides, giving a ghosting effect as the old value fades and slides away" [S39·T1·VERIFIED for fade/slide text]. Financial terminals flash green/red ticks on up/down prints — the same redundant-encoding rule as §3.5.
- Numbers: flash decay 300–800ms; our motion bank's 400ms class fits (use for the fade-out; don't loop). Don't flash the whole table on a repaint — flash only cells whose value crossed a meaningful threshold or changed direction; constant flashing = crying wolf (change-blindness corollary: universally-present transients stop being cues).

### 5.3 No layout jump — geometry stability under update
- Three primitives, in order of leverage: (1) **tabular numerals** so digit-count changes don't change width (§3.1); (2) **fixed/min column widths** sized to the widest expected value (content-fit *once*, at first render, not per tick — and reserve width for a leading `−`/▲ so sign flips don't reflow); (3) skeleton/placeholder rows pre-shaped like real rows (§8.1). The web-platform formalization of the underlying harm is Cumulative Layout Shift, but the principle is surface-independent: repainting data must not move unrelated pixels. [S17, S39 for the mechanism; CLS tie-in is web-specific and not re-derived here.]
- Row *reordering* on live sort is layout jump at the structural level: btop's default process sort is **"cpu lazy" — "sorts top process over time (easier to follow)"** rather than re-sorting every tick [S29·T1·VERIFIED]. For our sysmon: re-sort on a debounce (e.g., every 2–5s) or on user action, not every refresh.

### 5.4 Stale vs loading affordances
- Prefer **status + provenance over spinners** for background refresh: a spinner claims "work in progress" on a surface that is 95% populated; the correct signal is per-tile "last updated HH:MM:SS" plus a state change only for the stale part (gray-out + timestamp). Grafana/Kibana both implement the provenance half: the dashboard time picker "select[s] a time range and set[s] how often the dashboard data refreshes" [S36·T1·VERIFIED for Kibana], Grafana exposes per-dashboard auto-refresh + now-delay [S15·T1·VERIFIED]. (The gray-out-plus-timestamp pattern is industry-common but no controlled study was found — FLAGGED; the loading-ladder bank entry covers spinner-vs-skeleton-vs-bar for initial loads.)
- Optimistic UI in system tools: applies to *user-initiated state changes* (pause a process, mute an alert) — apply instantly, reconcile on confirm, roll back loudly on failure. For *read-side* monitoring data, optimism is wrong (fabricating metrics); use placeholder-dash + timestamp instead (§8). [FLAGGED: no primary source specific to system tools; consistent with NN/g progress-indicator guidance S10.]

---

## 6. Master-Detail & Row Patterns

### 6.1 Row-click → detail: the pattern's home turf
- Windows' official list/details guidance (verified): the pattern fits when you want to "locate and prioritize a large collection of content" and "allow the quick addition and removal of items… while working back-and-forth between contexts"; the list pane keeps a **selection visual** and "selecting a new item in the list updates the details pane" [S31·T1·VERIFIED]. The Windows dev blog adds the tradeoff: master-detail "is easy to understand and doesn't need a lot of explanation" for the user (snippet) [S32·T2·SNIPPET].
- **Pane vs modal:** a side pane/detail area preserves scan context (user compares rows against the open detail — the watchlist use case); a modal/overlay focuses a single item and its actions (KDE HIG: use OverlaySheet for "auxiliary views of read-only narrow scrollable content," dialogs for input) [S27·T1·VERIFIED]. In a Plasma widget where width is scarce, row → full-width overlay sheet/detail page is the KDE-native expression of master-detail; in the web portal, side-by-side is affordable ≥~1000px, stacking below that [S31 adaptive layout, VERIFIED concept].
- Fleet alignment: standing preference (row-click opens detail modal; per-item summaries on every row) matches this evidence exactly — per-row verdict + master-detail is not a stylistic choice, it's the pattern's documented purpose (prioritize a large collection).

### 6.2 Summary-first column ordering
- Put the **verdict/status column immediately after the identity column** (or as the leading column), because scanning starts at the left edge and runs down it (F-pattern left stem [S9·T2·VERIFIED]; KDE "top-leading = first focus" [S26·T1·VERIFIED]); the row's micro-conclusion must be inside the first fixation. Name → verdict → primary metric → delta → sparkline → detail fields.

### 6.3 Row hover affordances
- Reveal-on-hover actions save space but cost discoverability and are invisible to touch; persistent per-row buttons cost width and mis-click risk. Ant Design ships hover affordances as opt-in (`rowHoverable`, default true for visual highlight only) and puts actions in a persistent trailing column when needed [S35·T1·VERIFIED for the API]. Fitts cost (bank, not re-derived): hover-revealed buttons shrink target availability in time rather than space. Rule: **primary action = persistent (row click / single trailing button); secondary = hover or detail view**. For kill/terminate specifically, keep it in the detail view or a selection action bar (§7.3) — never hover-only for destructive ops.

### 6.4 Zebra vs rules vs whitespace
- The best direct evidence is Enders' three-study series (A List Apart): zebra striping produced **"no statistically significant improvement in accuracy — and very little statistically significant improvement in speed"**, though users *report liking it*; whether it helps depends on row count, row height, text density, whitespace, and stripe contrast [S11·T2·VERIFIED]. 
- Practical resolution: on dense dark tables prefer **horizontal hairline rules + comfortable row height + strong column alignment**, use zebra only where rules can't be drawn (wide-gap lists) or to support row-tracking in wide multi-column tables; never vertical column rules (compete with data ink; alignment/whitespace separates columns) [S11 + §1/§2 data-ink logic; vertical-rules point is expert consensus, FLAGGED no study].
- Sticky headers in scrollable tables/popups: keep column labels pinned when the body scrolls — shipped as first-class by Ant Design (`sticky` header + scroll) and Carbon's table anatomy [S35, S33·T1·VERIFIED].

**Do:** per-row verdict column left; row-click → detail (overlay on widget, pane on web ≥1000px); persistent primary action; rules+spacing over zebras on dark; sticky header on any scrolling body.
**Don't:** hover-only destructive actions; detail hidden behind a per-row "open" button that duplicates row-click; zebra as the only row-separation in wide tables with poor alignment.

---

## 7. Process/List Control Surfaces (Sysmon-Style)

### 7.1 Column sets — the reference implementations
- **htop** (verified from the man page): columns include PID, STATE (S/I/R/D/Z), M_VIRT (VIRT), M_RESIDENT (RES — "used physical memory"), M_SHARE (SHR), M_PRIV, PROCESSOR, PERCENT_CPU, PERCENT_MEM ("percentage of memory… based on the process's resident memory size"), plus full COMMAND; column set/order is user-configurable in the F2 Setup screen; F3 incremental search; `-s --sort-key COLUMN` sorts from CLI; "tasks related to processes (killing, renicing) can be done without entering their PIDs"; multiple processes can be tagged (Space) and acted on at once [S28·T1·VERIFIED].
- **btop** (verified): default sort `proc_sorting = "cpu lazy"` ("sorts top process over time (easier to follow)"), process filter (`-f/--filter`), tree view, "send any signal to selected process", pause the process list [S29·T1·VERIFIED].
- **Windows Task Manager** (verified from MS Learn): Processes/Details tabs list processes with resource usage, grouped by app/background; displayed columns are user-selectable via right-click header → "Select columns" (e.g., adding Threads); Details tab exposes fine-grained columns; wait-chain inspection for hung processes [S30·T1·VERIFIED].
- Convergent column set for our sysmon widget: **Name/ID → status/state glyph → CPU% → MEM% (+absolute RES) → the resource of record for this view** (disk/net/GPU) → uptime/age. Both htop and Task Manager sort by the resource column by default; htop exposes sort as a first-class key (F6/S) — sorting by the currently-viewed resource is the expected default [S28, S30·T1].

### 7.2 CPU% normalization — the Irix/Solaris fork (pick one, label it)
- htop man page (verified): PERCENT_CPU can range "to 100% which means the full capacity of the core it is running on. This is sometimes called 'Irix mode'" while PERCENT_NORM_CPU (NCPU%) "is normalized by CPU count. This is sometimes called 'Solaris mode'" [S28·T1·VERIFIED]. A 32-thread host can show a single-threaded spinner at 100% (Irix) or ~3% (Solaris). **Decision: normalize by CPU count (Solaris-style) for fleet scanning** (100% = whole box, comparable across hosts) and expose per-core in detail; a bare "CPU%" column that means different things per host is a false-comparison bug. Same logic for GPU% per device.

### 7.3 Search + filter + sort
- Sort indicator clarity: the W3C ARIA APG sortable-table reference (verified) makes each sortable header a **button**, sets `aria-sort` ("ascending"/"descending") on the *currently sorted* column only, styles hover = focus, and hides decorative sort glyphs from the accessible name [S22·T1·VERIFIED]. Visual rule: one sorted column at a time, arrow shows direction, the header is visibly clickable (entire header, not a tiny glyph — Fitts).
- Filter **chips** for bounded state dimensions (running/stopped, warn-only, "my hosts") vs **search field** for unbounded identifiers (name, PID, tag): Kibana's dashboard filtering ships exactly this split — query bar (KQL) + filter pills + controls + time range as parallel mechanisms [S36·T1·VERIFIED]; btop/htop ship substring filter for processes [S28, S29]. htop's incremental search (F3) shows search-in-table is a floor feature, not a luxury.
- Presets beat fiddling: btop's named presets, htop's saved layouts — for our widget, ship 2–3 filter presets (All / Problems only / Pinned) instead of a filter builder.

### 7.4 Bulk selection + action bar vs per-row buttons
- Carbon data table (verified): rows selectable via checkbox (single or multi), and "users can perform a single action or batch actions against selected items," with a **toolbar** reserving "global table actions such as… complex filters, exporting" [S33·T1·VERIFIED]; Ant Design ships the same as "Selection and operation" [S35·T1·VERIFIED]. htop's tag-multiple-then-act is the TUI ancestor (verified) [S28·T1].
- Rule: per-row buttons are fine for one non-destructive action; the moment there are ≥2 actions or a destructive one, move to selection + action bar (keeps rows slim, eliminates per-row mis-clicks on "Kill").

### 7.5 Kill/terminate confirmation
- What the tools actually do: htop lets you "kill without entering PIDs" from the list (F9 signal picker — a deliberate selection step, then signal choice = the confirmation); btop "send any signal" similarly requires two steps; Task Manager's End Task executes immediately with no dialog (FLAGGED — observed behavior, no primary doc found). 
- Evidence-based rule for us: **single, clearly-labeled destructive action on one row = immediate with visible undo/feedback; bulk or ambiguous-destructive (signal choice) = explicit confirm naming targets ("Kill 3 processes on host-03?")**. Destructive buttons never hover-revealed (§6.3). Material guidance (destructive actions confirm; not extracted this session) — treat the two-step pattern above as the verified evidence [S28, S29·T1].

### 7.6 Sparkline-per-row vs number-per-row
- No controlled study found on row-count thresholds. Grounded synthesis: a column of same-scale mini-sparklines is a small-multiple grid (§2.4) — it works while (a) scales are shared/normalized, (b) rows ≲ 20–30 (a full screen of 1-second-noise strips becomes texture), (c) the trend is the question (memory leak, thermal climb). At higher row counts or when the question is "which row is worst *now*", use number + status color + threshold flash (§5.2) and keep sparklines for the detail view. [Synthesis of S4/S5 (word-scale contract), S7 (conjunction limits), S29 (2s sampling); FLAGGED thresholds.]

---

## 8. Empty / Error / Stale for Background Refresh

### 8.1 Placeholder-dash rows ("—") vs skeletons
- Our pre-seeded dash-row practice is supported from two directions: **Grafana's shipped default for null/empty field values is a hyphen: "No value — Enter what Grafana should display if the field value is empty or null. The default value is a hyphen (-)"** [S13·T1·VERIFIED] — professional monitoring tools render missing as a deliberate glyph, not blank, and make it configurable; **NN/g's skeleton research**: skeletons (placeholders that "mimic the layout of the page") reduce perceived wait and are appropriate **under ~10s** waits, while >10s needs progress feedback with duration information [S10·T2·VERIFIED].
- Refinements the evidence implies: the dash must be *visibly not-a-value* (dimmed, centered-or-left per column alignment convention, tooltip "no data yet"); pre-seeded rows must match final row geometry (§5.3); and a skeleton/dash that persists past the expected refresh cycle must hand off to an error state — a placeholder older than 2× the refresh interval is a stuck loader, not data. (The timeout-handoff point is FLAGGED — NN/g doesn't test it here; it's the contrapositive of their >10s guidance.)

### 8.2 Partial failure (one source dead among many)
- Per-panel independence is the observability-tool norm: Grafana dashboards are panel collections with per-panel data sources and per-panel errors; Kibana lets you "inspect the data and requests behind a panel" individually [S36·T1·VERIFIED]. Rule: **a dead source fails its own tile** (inline error chip + retry + last-good timestamp, values grayed), never the dashboard. Don't blank siblings that are fine; don't show a global spinner over 8 live tiles because the 9th is down. [S36 structure; per-tile error styling is fleet convention consistent with §5.4 — FLAGGED as synthesis.]

### 8.3 Provenance stamps ("as of")
- The professional tools put the time window where you can't miss it: Kibana pins the global time filter "next to the query bar in the dashboard header… to select a time range and set how often the dashboard data refreshes," with panel-level custom time ranges also available [S36·T1·VERIFIED]; Grafana exposes timezone, refresh intervals, and now-delay as dashboard-level settings [S15·T1·VERIFIED]. For our widgets: one small "as of HH:MM:SS" (click → absolute range + source) on every live surface; gray-out + stale styling when age > threshold (e.g., 2–3× refresh interval). Fleet-library corroboration: our Kibana-dashboards notes (055/056) describe exactly this high-level events-over-time reading model; Kibana docs verified directly here.

### 8.4 Retry affordances
- Manual retry button on any tile in error state (auto-retry with backoff behind it); NN/g's error-message guidance is in the general bank — the monitoring-specific addition is that retry must target the *tile*, not the page [synthesis of S36 per-panel model + bank; FLAGGED as synthesis].

**Do:** dash-glyph for no-data (Grafana default); geometry-stable placeholders; per-tile failure + retry + last-good timestamp; "as of" stamp on every live surface; gray-out on staleness.
**Don't:** blank cells (read as zero); global spinner over mostly-live content; hiding age of data; failing the whole surface for one source.

---

## 9. Density & Type for Data

### 9.1 Row heights — concrete scale
- Carbon data table (verified) ships five densities with exact heights: **xs 24px "highly dense layouts… maximizing information", sm 32px "compact… comfortable readability", md 40px default, lg 48px, xl 64px for multi-line rows** [S33·T1·VERIFIED]. Ant Design maps the same ladder to `large | medium | small` sizes (default large) [S35·T1·VERIFIED].
- For our widgets at 17px base type: **36–44px process/table rows** (≈Carbon sm–md), 48–64px for list rows with title+subtitle; KDE HIG sizes rows via gridUnit multiples (18px) — 2×gridUnit = 36px lands exactly in the compact band [S26·T1·VERIFIED].

### 9.2 Spacing system (KDE-native, verified)
- KDE HIG spacing tokens: `smallSpacing` for directly-related items/controls in a logical group; `mediumSpacing` between toolbar items; `largeSpacing` between groups of controls or text, and as window-edge padding; **gridUnit = 18px** with fixed-size elements sized as gridUnit multiples; icons: small for menu/flat buttons, smallMedium for list items without subtitles, medium for list items with subtitles [S26·T1·VERIFIED]. Also: group by *reducing* spacing within and *increasing* spacing between groups; items that look grouped must be logically related [S26·T1·VERIFIED].

### 9.3 Lists vs tables vs trees (when our "table" should be a list)
- KDE HIG (verified): lists are "faster to visually scan and handle long text better" (mostly-textual content); **use a table when users need to "quickly compare the data across list items" — "put each piece of data in its own column"**; if a would-be table has only two columns, or sorting/reversing columns makes no sense, use a list instead; **"minimize the use of tree views, as they tend to be confusing"** — prefer a list with collapsible sections [S27·T1·VERIFIED]. GNOME HIG adds: give columns minimum **and maximum** widths for adaptive scaling; differentiate multiple text elements per row via font size/weight [S34·T1·VERIFIED].

### 9.4 Elision rules (truncation)
- Middle-elide identifiers/paths/hosts (`/var/log…syslog`, `dl-…-main`) so both the distinguishing start *and* end survive; end-elide prose. Qt-native: `Text.elide` (ElideNone/Left/Middle/Right) on Qt Quick Text [S18·T1·VERIFIED]; measure with TextMetrics for content-fit columns; pair every elided cell with a tooltip (Ant Design ships `ellipsis` columns with tooltip as a table feature [S35·T1·VERIFIED]). Middle-elision for paths specifically is long-standing platform convention (file managers) — no controlled study found; the invariant it protects (both anchors of the identifier visible) is logical, FLAGGED.

### 9.5 Tabular alignment in QML-native terms (implementation cheatsheet)
- `font.features: ({ tnum: 1 })` on Qt ≥6.6 Text/Labels for numeric columns [S18·T1·VERIFIED]; pre-6.6 → numeric-column font with tabular default; C++ `QFont` feature API ≥6.7 [S19·T1·VERIFIED].
- Right-anchor numeric cells (Layout alignment right + `horizontalAlignment: Text.AlignRight`); reserve width for sign/arrow glyph; `Text.ElideMiddle` for identifier columns [S18·T1·VERIFIED].
- Web portal: `font-variant-numeric: tabular-nums` + `text-align: right` [S17·T1·VERIFIED].

### 9.6 Line length in narrow columns
- Table cells are not reading paragraphs: wrap at word boundaries, cap at ~2 lines per cell, elide beyond with tooltip (§9.4); full prose belongs in the detail view. (Classic 45–75 CPL line-length guidance applies to body copy, not table cells — do not import it into narrow columns; FLAGGED synthesis, no table-specific study found.)

**Do:** 36–44px rows (2× Kirigami gridUnit); KDE spacing tokens; list-vs-table-vs-tree per S27; middle-elide identifiers + tooltip; tnum + right-align everywhere numeric.
**Don't:** trees where collapsible lists work (KDE: confusing); >2 wrapped lines in a cell; importing body-copy line-length rules into cells; sub-32px rows with 17px type.

---

## Source Register

| ID | Source | Tier | Verification |
|---|---|---|---|
| S1 | Few, S. "Dashboard Confusion" (Perceptual Edge/Intelligent Enterprise PDF) — https://www.perceptualedge.com/articles/ie/dashboard_confusion.pdf | T1 | VERIFIED (definition + gauge critique quotes) |
| S2 | Few, S. *Information Dashboard Design* (book; PDF mirror) — https://public.magendanz.com/Temp/Information%20Dashboard%20Design.pdf | T1 | VERIFIED (partial text: TOC, exception-ranking chapter) |
| S3 | Sisense, "4 Dashboard Design Principles" — https://www.sisense.com/blog/4-design-principles-creating-better-dashboards/ | T3 | SNIPPET (5-second paraphrase) |
| S4 | Tufte, E. "Sparkline theory and practice" — https://www.edwardtufte.com/notebook/sparkline-theory-and-practice-edward-tufte/ | T1 | VERIFIED (sparkline definition verbatim) |
| S5 | Tufte, E. "Sparklines: computer code implementation" — https://www.edwardtufte.com/notebook/sparklines-computer-code-implementation/ | T1 | VERIFIED (0.1in/7pt height, bank to 45°, AspectRatio 1/6, dot+number, norms band) |
| S5a | Gist distillation of Tufte principles — https://gist.github.com/w0rd-driven/62a2c8377a5dfad337116625d71b486e | T3 | SNIPPET ("height ≈ x-height, ~14–20px") |
| S7 | Healey, C. "Perception in Visualization" (NC State) — https://www.csc2.ncsu.edu/faculty/healey/PP/ | T1 | VERIFIED (preattentive pop-out, feature integration) |
| S8 | NN/g, "Dashboards: Making Charts and Graphs Easier to Understand" — https://www.nngroup.com/articles/dashboards-preattentive/ | T2 | VERIFIED (dashboard definition, operational-vs-analytical, shape+intensity example) |
| S9 | NN/g, "F-Shaped Pattern For Reading Web Content (Original Study)" — https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content-discovered/ | T2 | VERIFIED (232-user eyetracking, 2 horizontals + left stem) |
| S10 | NN/g, "Skeleton Screens 101" — https://www.nngroup.com/articles/skeleton-screens/ | T2 | VERIFIED (<10s skeleton, 2–10s spinner, >10s progress bar + duration) |
| S11 | Enders, J. "Zebra Striping: More Data for the Case" (A List Apart №267) — https://alistapart.com/article/zebrastripingmoredataforthecase/ | T2 | VERIFIED (no significant accuracy gain; conditional factors list) |
| S12 | Grafana docs, "Configure thresholds" — https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-thresholds/ | T1 | VERIFIED (defaults: base green, 80 red; render targets) |
| S13 | Grafana docs, "Configure standard options" (+ .md mirror) — https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-standard-options/ | T1 | VERIFIED (decimals auto-truncation 1.1234→1.12, No-value hyphen, Green-Yellow-Red scheme list, Unit) |
| S14 | Grafana docs, "Dashboard best practices" — https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/ | T1 | VERIFIED (tell a story/answer a question, USE method, sprawl) |
| S15 | Grafana docs, "Modify dashboard settings" — https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/modify-dashboard-settings/ | T1 | VERIFIED (auto-refresh intervals, Refresh live dashboards, Now delay, timezone) |
| S16 | Apple HIG, "Charts" — https://developer.apple.com/design/human-interface-guidelines/charts | T1 | VERIFIED (few key pieces; legend for non-position encodings; accessibility labels; ticks) |
| S17 | MDN, "font-variant-numeric" — https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/font-variant-numeric | T1 | VERIFIED (tabular-nums definition) |
| S18 | Qt 6 docs, "Text QML Type" — https://doc.qt.io/qt-6/qml-qtquick-text.html | T1 | VERIFIED (elide enum; `font.features : object` since 6.6) |
| S19 | Qt 6 docs, "QFont class" — https://doc.qt.io/qt-6/qfont.html | T1 | VERIFIED (OpenType feature API since 6.7: featureTags/featureValue/clearFeatures) |
| S20 | W3C WAI, "Understanding SC 1.4.1 Use of Color" (WCAG 2.2) — https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html | T1 | VERIFIED (SC text + light-green/dark-red 3:1 example) |
| S21 | W3C WAI, "Understanding SC 1.4.11 Non-text Contrast" — https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html | T1 | VERIFIED (3:1 for graphical objects & UI states) |
| S22 | W3C ARIA APG, "Sortable Table Example" — https://www.w3.org/WAI/ARIA/apg/patterns/table/examples/sortable-table/ | T1 | VERIFIED (aria-sort on current column only, header-as-button, hover=focus) |
| S23 | NIH National Eye Institute, "Color Blindness" — https://www.nei.nih.gov/eye-health-information/eye-conditions-and-diseases/color-blindness | T1 | VERIFIED ("about 1 in 12 men") |
| S24 | ColorBrewer 2.0 — https://colorbrewer2.org/ | T1 | Tool (scheme taxonomy) |
| S24a | Table-alignment practice: "Designing Effective Tables" (book.rfortherestofus.com/tables.html); Mission Log "Design Better Data Tables" — https://medium.com/mission-log/design-better-data-tables-430a30a00d8c | T2/T3 | SNIPPET (right-align numerics; don't center) |
| S25 | ggplot2 "scale_brewer" docs (sequential/diverging/qualitative definitions) — https://ggplot2.tidyverse.org/reference/scale_brewer.html | T2 | SNIPPET |
| S26 | KDE HIG, "Layout and navigation" — https://develop.kde.org/hig/layout_and_nav/ | T1 | VERIFIED (top-leading priority; gridUnit 18px; small/medium/largeSpacing; IconSizes; grouping by spacing) |
| S27 | KDE HIG, "Displaying content" — https://develop.kde.org/hig/displaying_content/ | T1 | VERIFIED (lists faster to scan; tables for cross-item compare; 2-column rule; minimize trees; OverlaySheet) |
| S28 | htop(1) man page (man7.org) — https://man7.org/linux/man-pages/man1/htop.1.html | T1 | VERIFIED (columns; Irix vs Solaris/NCPU%; delay clamp 0.1–10s; -s sort; F2 setup; F3 search; tag+act; kill without PIDs) |
| S29 | btop README — https://github.com/aristocratos/btop (raw: raw.githubusercontent.com/aristocratos/btop/main/README.md) | T1 | VERIFIED (update_ms 2000 + ≥2000ms advice; "cpu lazy" sort; filter; any signal; pause) |
| S30 | Microsoft Learn, "Troubleshoot processes by using Task Manager" — https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/support-tools-task-manager | T1 | VERIFIED (tabs; Select columns; wait chains) |
| S31 | Microsoft Learn, "List/details pattern" — https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/list-details | T1 | VERIFIED (when to use; selection visual; adaptive layout) |
| S32 | Windows Developer Blog, "Master the Master-Detail Pattern" — https://blogs.windows.com/windowsdeveloper/2017/05/01/master-master-detail-pattern/ | T2 | SNIPPET |
| S33 | Carbon Design System, "Data table" — https://www.carbondesignsystem.com/building-blocks/core/components/data-table/ | T1 | VERIFIED (batch actions; toolbar; sortable headers; zebra option; row heights xs24/sm32/md40/lg48/xl64) |
| S34 | GNOME HIG, "List & Column Views" — https://developer.gnome.org/hig/patterns/containers/list-column-views.html | T1 | VERIFIED (min/max column widths; typography hierarchy in rows; sorting headers) |
| S35 | Ant Design, "Table" — https://ant.design/components/table/ | T1 | VERIFIED (size large/medium/small; sticky header + scroll; ellipsis column w/ tooltip; row-selection-and-operation; word-wrap tokens) |
| S36 | Elastic docs, "Inspect and filter a dashboard" — https://www.elastic.co/docs/explore-analyze/dashboards/using | T1 | VERIFIED (header time picker + refresh frequency; filter pills; KQL; per-panel time ranges; panel inspect) |
| S37 | The Decision Lab, "Change Blindness" — https://thedecisionlab.com/reference-guide/psychology/change-blindness | T2 | VERIFIED (definition; flicker paradigm; attention requirement) |
| S38 | Material Design (m2), "Data visualization" — https://m2.material.io/design/communication/data-visualization.html | T1 | SNIPPET (JS-walled page; "don't use color alone… reinforce with icons") |
| S39 | ag-grid docs, "Change cell renderers" — https://www.ag-grid.com/javascript-data-grid/change-cell-renderers/ | T1 | VERIFIED (fade/slide ghosting of previous value; Highlight Changes) + SNIPPET (`enableCellChangeFlash` flashes changed cells) |
| S40 | Grafana community forum, auto-refresh default fastest interval 5s — https://community.grafana.com/t/dashboard-auto-refresh-settings/33106 | T3 | SNIPPET |

Contrast ratios in §4.3 computed locally with the WCAG relative-luminance formula (method per S21); no source needed beyond the standard.

---

## Gaps & Contested Numbers

1. **"5-second rule" phrasing** — attributed to Few's *Information Dashboard Design* everywhere, but verbatim text not located this session; Few's verified language is "monitored at a glance." Treat 5s as the consensus paraphrase [S1, S2, S3].
2. **Sparkline upper size limit** — Tufte gives print-scale numbers (0.1in/7pt data height, banking 45°, AR 1:6); no controlled study of on-screen pixel limits exists in what we found; the 12–20px read-across is interpretation.
3. **Right-aligning numerics** — unanimous across every vendor/expert source encountered, but no controlled experiment found (accounting convention lineage).
4. **K/M abbreviation threshold** — ">4 digits → suffix" is convention; no official design-system page pins it (Grafana/Kibana auto-scale, exact cutoffs undocumented).
5. **Sub-500ms "twitchy" threshold** — judgment; documented tool floors are 1–2s (btop/htop/Grafana 5s). No perception study on table-repaint cadence found.
6. **Sparklines-per-row ceiling (~20–30 rows)** — synthesized from small-multiple scale-sharing + preattentive conjunction limits; no direct study.
7. **Task Manager specifics** (~1s refresh; End Task with no confirmation) — common knowledge, not verified at a primary source; htop/btop two-step signal flows are the verified analogues.
8. **Red-up/green-down finance conventions (East Asia)** — unverified; relevant only if the watchlist ever localizes; arrows remain the load-bearing channel regardless (§3.5).
9. **Zebra striping** — Enders (2008) found no significant accuracy benefit but modest preference and untested boundary conditions (row count/height/density); modern dark-theme replication absent.
10. **Stale-state styling (gray-out + timestamp)** — timestamps and now-delay are documented tool features [S15, S36]; the gray-out affordance itself has no controlled evidence.
11. **Material data-viz guidance** — m2/m3 pages are JS-walled; cited from official-page search snippets only.
12. **Optimistic UI in system tools** — no primary source; extrapolated from NN/g progress guidance.

---

## Method

Discovery via 20+ targeted searches (4 batches); extraction via two extractors (engine fallback waterfall per the research skill), raw HTTP for JS-walled/W3C pages, direct .md/PDF fetches for Grafana docs and Few's PDFs; every hinge claim read at source and quoted above; palette contrast computed with WCAG formulas; contested numbers presented as ranges with tier labels; false premises corrected inline (5-second rule precision, §1.1; "no controlled study" markers throughout). Written incrementally (5 part files, assembled in order).

## Crosswalk — Standing Preferences → Strongest Evidence

| Standing preference | Supporting evidence |
|---|---|
| Glance briefings over flat lists | S1 (at-a-glance definition), S8 (act quickly), S7 (preattentive channel), §1.4 verdict triad |
| Per-item summary on every row | S1/S2 (exception ranking as legitimate content), S9+S26 (left-edge scan), §6.2 |
| Row-click → detail modal | S31 (list/details pattern), S27 (OverlaySheet for read-only detail), §6.1 pane-vs-modal |
| Primary content fits without scrolling | S1 ("single screen"), S27 (maximize content area), §5.3 (geometry stability) |
| 17px base type, content-fit columns | S26 (gridUnit 18px), S34 (min/max column widths), §9.1–9.2 density ladder |
| Tables wrap cells | S35 (word-wrap tokens), S34, §9.6 (≤2 lines + tooltip) |
