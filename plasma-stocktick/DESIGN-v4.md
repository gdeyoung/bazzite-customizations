# StockTick v4 — UX Design Spec (chip + popup redesign)

Target: Plasma 6.7 panel plasmoid, dark bar (bg #24272C), 3200 logical px @ DPR 1.6,
Noto Sans, Kirigami.Units (gridUnit 22, smallSpacing 4, largeSpacing 8).
Diagnosis driving this spec (from screenshots): the chip is the *smallest, weakest*
element on the bar — clock dominates by scale, weather by icon; the chip is plain
inline text with a loud red percentage and no shape. The popup is a 440px list.

Borrowed patterns (cited inline): Apple Stocks (pinned crosshair readout, price-first
hierarchy, tab restraint), Yahoo Finance (span chips, dashed prev-close baseline,
search→detail flow), TradingView (gridline restraint, crosshair), Google Finance
(hover row actions), Robinhood (portfolio header chips, sparkline cards), Linear
(neutral surfaces, 4px rhythm, animated tab underline), plasma-systemmonitor
(#3fd18b/#f4405c — keeps the chip visually native to this panel's sibling widgets).

────────────────────────────────────────────────────────────────────────────────
A. CHIP  (compactRepresentation)
────────────────────────────────────────────────────────────────────────────────
Go from one cramped line to a two-line lockup that rhymes with the clock's
structure (big datum over small context) and gains a graphic element like the
weather moon. Height budget = full panel height h; content vertically centered.

  ┌────────────────────────────────────────────────┐
  │  531.04        ▁▂▃▂▃▄▅▆▅▆▇▆                    │  ← line 1: price, ~0.40h px,
  │  MSFT   ▼ −0.30%                                │  ← line 2: ~0.24h px
  └────────────────────────────────────────────────┘
   (wireframe is relative; sparkline sits right of price, vertically centered
    across both lines, ~64 × (h−10) px)

Hierarchy (price is the headline, not the ticker — the user picked the ticker,
so identity is context, not news):
 1. PRICE — semibold, Kirigami.Theme.textColor, ~0.40·h px, tabular figures
    (font.features "tnum"; falls back gracefully) so 60s ticks don't jitter.
 2. TICKER — small caps, +0.6px letterspacing, disabledTextColor (~0.24·h).
 3. DELTA — same size as ticker, bold, colored + arrow glyph ▲▼ (shape encodes
    direction on top of color — colorblind-safe redundancy), sign always shown.
 4. SPARKLINE — 1.5px polyline, colored by day direction, 0.15-alpha fill to
    baseline, no axes/grid. It's a texture, not a chart.

Mini-sparkline in chip: **YES** — one fetch (selected symbol, range=1d,
interval=15m, ~26 pts) piggybacks on the 60s refresh; it's the single cheapest
move from "text label" to "composed widget". Rules: drawn only when ≥5 points;
otherwise its width collapses to 0 (never a blank gap); redraws only on data
arrival. MouseWheel over chip cycles watchlist symbols (optional, config-gated).

Hover: full-chip rounded rect, white 6% overlay fade-in 120ms, pointing-hand
cursor. Click: toggles popup (whole chip, single target). No long-press menu.
Loading: "—" for price, ticker always shown. Offline: keep last price, delta
dims to disabledTextColor. Icon-free by design — the sparkline is the icon.

────────────────────────────────────────────────────────────────────────────────
B. POPUP IA  (fullRepresentation)
────────────────────────────────────────────────────────────────────────────────
Fixed frame 960 × 640 logical px (Layout.preferredWidth/Height on the root;
Layout.minimum 720 × 520; shell clamps at 95% of screen). Fixed, not per-tab
self-sizing: a popup that grows/shrinks per tab feels unstable (Linear/Apple
restraint); each tab adapts inside the frame.

Two levels, no modal dialogs (popup dies on focus loss — dialogs would close it):
  Level 1 — tab shell            Level 2 — stock detail (pushed over tabs)
  ┌────────────────────────────┐  ┌────────────────────────────┐
  │ MARKETS WATCHLIST PORTFOLIO│  │ ‹ Back   MSFT · Microsoft  │
  │ ──────▔▔▔▔                  │  │ (detail owns the full frame│
  │ (tab content, fills rest)   │  │  incl. footer row)        │
  ├────────────────────────────┤  │                            │
  │ ● OPEN · as of 11:57 · ⟳   │  └────────────────────────────┘
  └────────────────────────────┘

Tabs (3, top, text-only with animated underline — TradingView top-tab pattern):
  MARKETS — default tab and the glance view. First paint: 6 skeleton cards.
  WATCHLIST — full list + search. First paint: rows from the always-running
              60s watchlist fetch (no wait), sparklines hydrate in place.
  PORTFOLIO — holdings + totals. First paint: totals from cached prices +
              positions from ~/.config JSON; recomputes as ticks land.
Last-used tab persists across opens (config key `lastTab`).

Navigation model: any symbol anywhere (markets card, watchlist row, portfolio
row, search result) is one click from its detail view — detail is the universal
drill-in, never a tab. Back = chevron in detail header or Esc; both slide the
detail away (180ms) and restore the tab exactly as left.

Footer strip (always visible on level 1): session pill + "as of HH:MM" (local
time) + manual refresh button. Session pill states: ● OPEN (green dot) /
◐ PRE-MARKET / ◗ AFTER HOURS / ○ CLOSED (muted). Derived from ^GSPC chart meta
(tradingPeriods + regularMarketTime), displayed in local time.

Per-tab QML files (chip / shell / one file per tab / detail) — small components
only; keeps the one-handler-per-signal rule achievable and avoids the
600-line-file corruption class.

────────────────────────────────────────────────────────────────────────────────
C. MARKETS TAB
────────────────────────────────────────────────────────────────────────────────
Recommended set — 6 cards, 3×2 grid, one row "risk assets", one row
"macro/fear" (a glance needs both; gold/oil stay out to keep the grid whole):

  Row 1: ^GSPC S&P 500 · ^IXIC Nasdaq · ^DJI Dow 30
  Row 2: ^TNX 10-Yr Yield · ^VIX Volatility · BTC-USD Bitcoin

  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
  │ S&P 500        │ │ NASDAQ         │ │ DOW 30         │
  │ 6,411.11  ▲+0.4%│ │ 21,003.2  ▼−0.3%│ │ 44,120  ▲+0.2% │
  │ ▁▂▃▄▃▄▅▆▅▆ ▁▂▃  │ │ ▆▅▄▃▃▂▂▃▂▁▁▂▁  │ │ ▂▃▃▄▄▅▅▆▆▆▇▇   │
  └────────────────┘ └────────────────┘ └────────────────┘
  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
  │ 10-YR YIELD    │ │ VIX            │ │ BITCOIN        │
  │ 4.35%  ▲+3.2bp │ │ 17.84   ▼−1.2% │ │ $92,431 ▲+1.1% │
  │ (spark)        │ │ (spark)        │ │ (spark)        │
  └────────────────┘ └────────────────┘ └────────────────┘

Card anatomy (Robinhood/Yahoo "markets" tiles): micro-caps label → value 22px
semibold tabular → delta line (arrow + %) in semantic color → sparkline
60×28px canvas (range=1d, interval=30m). ^TNX special-cased: value shown as
yield% (index/10), delta in basis points — "4.35% ▲+3.2bp" reads as macro, not
as a stock price. Color rule: raw up/down for ALL six (never invert VIX/TNX —
users decode green=up universally; Yahoo/TradingView agree).
Card: white 5% fill, radius 8, no border; hover → 8% + click → detail view.
Skeletons on first paint; per-card error state = label + "unavailable" (other
cards unaffected). Fetched only while popup is open (pause on close).

────────────────────────────────────────────────────────────────────────────────
D. STOCK DETAIL VIEW
────────────────────────────────────────────────────────────────────────────────
  ┌──────────────────────────────────────────────────────────────────────┐
  │ ‹   MSFT · Microsoft Corp.          ● OPEN   AFTER 528.10 ▼−0.55%     │
  │     531.04  ▼ −1.58 (−0.30%)                                        │
  │     [1D][5D][1M][3M][6M][1Y][5Y]      ◂ segmented, selected = filled  │
  │ ┌──────────────────────────────────────────────────────────────────┐ │
  │ │ - - - - - - - - dashed prev-close baseline - - - - - - - - - - - │ │
  │ │          ╱╲    ╱╲   hover: vertical hairline + dot, readout      │ │
  │ │      ╱╲╱  ╲__╱    ╲╱╲   pinned TOP-RIGHT (Apple Stocks):        │ │
  │ │  ╱__╱                 "Oct 28 · 3:47 PM   529.90"              │ │
  │ │ 10:00      12:00      14:00      16:00   (3–5 date ticks)       │ │
  │ └──────────────────────────────────────────────────────────────────┘ │
  │ OPEN 431.50 │ HIGH 433.90 │ LOW 430.12 │ PREV 431.60 │ VOL 42.3M │   │
  │ DAY RANGE 430.12 ▮──────────●─── 433.90 (marker = current)          │
  └──────────────────────────────────────────────────────────────────────┘

Header: back chevron; symbol bold 20px + name 12px secondary; price 28px
semibold; delta "−1.58 (−0.30%)" with arrow in semantic color, computed from
prev session close *inside the fetched series* (chartPreviousClose is
range-relative — a 3M fetch yields a 3M delta; worst silent-wrong class).
Session chip: OPEN / PRE (4:00–9:30 ET) / AFTER (16:00–20:00 ET) / CLOSED with
"as of" last-trade time; when PRE/AFTER, show a second muted after-hours line
(AFTER xxx ▼x.xx%) — regular-session delta stays primary (Yahoo rule).
Crypto: chip reads "24H" — no session states, delta over rolling 24h.

Span selector: segmented control, 7 spans — 1D·5m, 5D·30m, 1M·1h, 3M·1d,
6M·1d, 1Y·1d, 5Y·1wk (one chart fetch per change; ignore stale responses;
no double-fetch while in-flight; selected span persists in config). Selecting
a span redraws the chart in place — the chart IS the view takeover.

Chart (Canvas polyline): 2px line colored by SPAN direction (first→last of the
span, not day delta — Yahoo behavior); gradient fill under line 0.18→0 alpha;
dashed horizontal baseline at the span's starting close (1D = prev close) so
up/down is legible before reading numbers; 3 faint horizontal gridlines with
right-edge price labels (max/mid/min, textColor @12%); 3–5 date ticks bottom.
Crosshair: hover → nearest-point snap, vertical hairline + 4px dot, readout
pinned top-right (date · time · price) — pinned, not cursor-following: less
jitter, trivial in Canvas, and leaves the line unobstructed.

Key stats row: six flat cells (Open / High / Low / Prev close / Volume / Day
range). Volume compact (42.3M / 1.2B). Day range = lo—hi numerals + 80px
micro-bar with a marker at current position (the one flourish; earns its
pixels by answering "where in the day are we"). 52W range replaces Day range
when span ≥ 1M.

States: loading = skeleton band with pulsing chart-height block; error = muted
"Couldn't load chart" + Retry (refetch same span); empty (delisted/bad symbol)
= error state with "Remove from watchlist" action if applicable.

────────────────────────────────────────────────────────────────────────────────
E. WATCHLIST TAB
────────────────────────────────────────────────────────────────────────────────
  ┌──────────────────────────────────────────────────────────────────────┐
  │ [ 🔍 Search stocks & crypto…                    ]   sort: ▾ Δ%        │
  │──────────────────────────────────────────────────────────────────────│
  │ ▎▁▂▃▄▅▆  MSFT  Microsoft        │ 531.04 │ −1.58 │ [▼−0.30%]        ✕ │
  │ ▎▂▃▄▅▆▇  ESTC  Elastic          │ 231.55 │ +4.10 │ [▲+1.80%]        ✕ │
  │ ▎▆▅▆▇▆▇  BTC-USD Bitcoin        │ 92,431 │ +998  │ [▲+1.09%]        ✕ │
  │ ▎…       ETH-USD Ethereum       │  3,122 │ −18.2 │ [▼−0.58%]        ✕ │
  │          XRP-USD  ·  VOO  ·  SCHD …            + Add symbol          │
  └──────────────────────────────────────────────────────────────────────┘

Row anatomy (Google Finance): 48px-tall flat rows, hairline separators
(textColor 10%); 48×20 sparkline (hydrates in place from the 60s fetch's
1d series) → SYMBOL bold 14 → name 12 secondary elided → price tabular →
Δ$ plain colored text → Δ% pill badge. Chip's current symbol gets a 3px accent
left rail. Click row = detail. Hover reveals trailing ✕ (remove, with 3s
undo toast — never a confirm dialog). Drag handle (⋮⋮ on hover) reorders;
manual order persists (config `symbols` order IS the order).

Sort: dropdown cycles Manual / Δ% desc / Δ$ desc / A–Z; choice persists.
List scrolls internally beyond ~11 rows (frame height stays fixed).

Search (Yahoo /v1/finance/search, keyless): field lives at top of THIS tab —
search is about finding symbols, not a global command bar. Debounce 300ms,
min 2 chars, cancel in-flight on new keystroke, cap 8 results, fetch only
while popup open. While query is active the results replace the list in-place:
each result = symbol + name + type tag (EQUITY/ETF/CRYPTO/INDEX chip) + last
price/Δ (lazy-fetched for visible rows only). Click result = detail view;
trailing "+" = add to watchlist → row morphs into a watchlist row in place
(no dialog, no toast-spam). Empty query = normal list. No results = one muted
row "No matches for 'xyz'". Esc clears.

────────────────────────────────────────────────────────────────────────────────
F. PORTFOLIO TAB
────────────────────────────────────────────────────────────────────────────────
  With positions:
  ┌──────────────────────────────────────────────────────────────────────┐
  │ TOTAL VALUE      DAY CHANGE        OVERALL P/L                        │
  │ $48,211.40       ▼ −$312.08 (−0.64%) ▲ +$6,412 (+15.3%)               │
  │                                        vs $41,799.40 invested    [+ Add]│
  │──────────────────────────────────────────────────────────────────────│
  │ SYM    QTY  COST   PRICE    VALUE      DAY        TOTAL P/L           │
  │ MSFT    12  398.20  531.04  6,372.48  −63.84 ▼   +1,594 ▲ +33.3%   ✎ │
  │ VOO    20  402.10  501.22 10,024.40  −120.40 ▼   +982 ▲ +4.9%     ✎ │
  │ BTC  0.25  61,200  92,431 23,107.75  −127.88 ▼  +7,808 ▲ +50.9%    ✎ │
  └──────────────────────────────────────────────────────────────────────┘

Totals header (Robinhood pattern): three labeled stat clusters — value 22px
semibold; day change and overall P/L in semantic color with arrows; invested
basis as a muted subline. Recomputes from live watchlist prices on every tick.

Table: flat rows, right-aligned tabular numerics, fixed column widths (no
fillWidth floaters — aligned columns are the whole point of a table), header
row in micro-caps that sorts on click (sym/qty/value/day/total). Row click =
detail; hover reveals ✎ edit. Values: currency prefix only in totals, unit
$/% headers carry the unit context in rows; negative P/L in parens? NO —
explicit − sign + color + arrow (triple redundancy, minus parens is fine).

Add/edit flow — inline, zero dialogs: "+ Add" appends ONE blank editable row
at top: symbol field (wired to the same debounced search, type-tag chips),
qty, cost basis per unit, then Add/Cancel. Edit = same row expanding in place
under the position (fields prefilled) + Remove; Remove turns into a red
"Remove position?" confirm-in-place button for 3s (focus-loss means no modal
confirmations, and no accidental data loss either). Autosave each committed
edit to ~/.config/plasma-stocktick/portfolio.json —
{ "version":1, "positions":[{"symbol":"MSFT","qty":12,"cost":398.20}] }
Write atomically (temp+rename); tolerate missing/corrupt file as empty state.

Empty state (first run): centered quiet block — "Track your portfolio" /
"Add a position to see total value, day change and P/L here." / primary
button "+ Add position" (same inline row flow). No illustration, no shame.

────────────────────────────────────────────────────────────────────────────────
G. VISUAL LANGUAGE
────────────────────────────────────────────────────────────────────────────────
Color tokens — FIXED HEX, not Kirigami semantic tokens (verified: positive/
negativeText resolve undefined in compact reps on 6.7; the pair below is
systemmonitor's, so the chip stays native to this panel's siblings):
  up     #3fd18b   down   #f4405c   (identical alpha rules both directions)
  text         Kirigami.Theme.textColor
  secondary    Kirigami.Theme.disabledTextColor
  hairline     textColor @ 10%      card fill   white @ 5%   hover  white @ 8%
  card radius 8 · chip pill radius = smallSpacing/2 (smallRadius is undefined)
Colorblind safety: green/red pair is weak alone — every colored datum also
carries a sign (+/−), an arrow glyph (▲▼), or a position, so color is
redundant, never sole encoding. Chart line color doubles as the only saturated
color in detail view; no second accent hue anywhere.

Delta badge — ONE symmetric treatment (fixes v3's up=ghost/down=screamer
asymmetry): tinted pill fill semantic color @16% alpha, semantic text, bold,
no border; same alpha up and down. Chip/markets cards use plain colored
arrow+text (no pill) to keep the bar light; pills live in dense lists.

Type scale (Noto Sans, all numerics tabular): detail price 28 / card value 22
/ totals value 22 / symbol 14 semibold / body 13 / secondary 12 / micro-label
10 caps +0.6px tracking. Chip scale is proportional to panel height (A).

Spacing rhythm: multiples of 4 (smallSpacing). Popup side margins 20, tab bar
underline 2px, card padding 12/16, list row height 48, hairlines 1px.

Surface grammar: cards = Markets tiles only (scannable tiles); Watchlist and
Portfolio = flat rows + hairlines (dense data, faster scan); Detail = flat
with a single hero chart zone. One grammar per context, never mixed.

────────────────────────────────────────────────────────────────────────────────
H. MOTION & FEEDBACK
────────────────────────────────────────────────────────────────────────────────
Restrained everywhere (Linear): nothing moves that carries data; no number
roll-ups, no layout shifts on tick.
  · Price tick — 400ms background pulse (white @6% fading out) behind the
    changed value cell/row; value itself never animates (tabular figures
    already prevent jitter).
  · Tab switch — content: 120ms fade + 8px upward slide of incoming page;
    underline: 150ms eased slide between tabs.
  · Detail push/back — 180ms horizontal slide (drill-in from right, back to
    left). Span change — chart redraws with 250ms progressive left-to-right
    draw (animate a clip width, repaint Canvas); direction color recomputes.
  · Hover — 120ms fill fade on rows/cards; badges and text never animate.
Skeletons (shape-matched, never spinners): markets = 6 card-sized rounded
rects; watchlist = row-height bars; chart = full chart-band block; detail
stats = six small bars. All pulse opacity 0.15↔0.35, 1.2s loop. Hydration
replaces each skeleton independently as its own fetch lands (no all-or-nothing).
Feedback states per surface: loading = skeleton; error = muted message + Retry
(markets: per-card; chart: in-chart; search: inline row); offline = keep last
values, session pill shows ○ and footer gains "reconnecting…"; market closed =
chart shows last session + header chip "CLOSED · last close 531.04".

────────────────────────────────────────────────────────────────────────────────
APPENDIX — data & plumbing decisions the design depends on
────────────────────────────────────────────────────────────────────────────────
Fetch matrix (all keyless Yahoo chart/v8 + search/v1, QML XHR, UA header kept):
  chip (always, 60s): selected symbol range=1d interval=15m → price, day Δ, spark
  watchlist (always, 60s): each symbol range=1d interval=30m → quote + row spark
  markets (popup open only): 6 index/symbols range=1d interval=30m
  detail (on open + span change): one chart fetch per span (mapping in D);
    day-Δ always recomputed from prev session close inside the series
  search (popup open only): debounced 300ms, ≥2 chars, cancel in-flight
Session model: stocks honor PRE/REGULAR/AFTER/CLOSED from tradingPeriods meta;
crypto = "24H" always. All timestamps displayed in local time, session logic ET.
Config keys added: lastTab, chartSpan, sortMode, portfolioPath. Watchlist order
= existing `symbols` string order. Popup sizing via Layout.preferredWidth/Height
on the fullRepresentation root only (width/height literals are ignored; if a
size change "doesn't take", popupWidth/popupHeight are frozen in applet config —
delete keys with shell stopped). StackLayout pages must bind height to the
current page (tallest-child trap). One QML file per tab/section; one handler
per signal per file; run check_qml.py before install.
