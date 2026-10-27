# StockTick — panel stock chip + watchlist + portfolio popup

First KDE-native plugin in the suite (no Omarchy source — designed for
gdtower's centered-bar layout). **Code-complete, verified against the live
API; not installed.**

- **Chip**: primary symbol + price + colored Δ% (theme positive/negative).
- **Popup**: hero row (primary, price, Δ%, 30-day sparkline), watchlist rows,
  optional portfolio section (positions `SYM:QTY:COST` → market value, day
  P/L, total P/L, totals), as-of footer with refresh interval.
- **Data**: Yahoo Finance v8 chart API — keyless, one call per symbol returns
  quote + prevClose + 3-month daily series. **Stooq was the first choice and
  is dead from this network** (snapshot 404, daily CSV behind a JS
  proof-of-work challenge — verified 2026-10-26); recorded so nobody retries
  it blind. If Yahoo later blocks unauthenticated calls, the probe is one
  function (`chart()` in `contents/scripts/fetch-quotes.sh`) to swap.
- **Single-line JSON contract** everywhere: compact state write, last-line
  stdout read (`~/.cache/gdeyoung.stocktick/quotes.json`).

## Config (KConfig XT)
`symbols` (comma list, Yahoo format, indices `^GSPC`), `primary` (chip+hero),
`positions` (optional, one per line `SYM:QTY:COST`), `refreshMin` (1–120).

## Verified (2026-10-26, no install)
- `tools/check_qml.py plasma-stocktick` → 3 files, 0 errors, 0 warnings.
- Live probe: `SPY,QQQ,AAPL` → single-line JSON; SPY 765.37 / prev 738.93 /
  +3.578%; 31-point sparkline ending at the close; state file == stdout.
- Portfolio math live: AAPL:10:150.00 → mkt 3439.10, dayPl +108.90,
  totPl +1939.10; totals consistent; Model.js unit tests (formats, parser
  junk-filtering, P&L, missing-symbol flag, series guards).
- Popup geometry + chip render: install-day (desktop-containment compile test,
  then panel).

## Install day
```
./install.sh                       # or per ROADMAP punch list
systemctl --user restart plasma-plasmashell.service
# Add Widgets → StockTick; check /tmp/plasma-stocktick-hb.json advances
```
Rollback: `kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.stocktick`.

Suggested panel placement (Greg's Omarchy layout): StockTick immediately LEFT
of the centered timepiece clock, weatherx immediately right of it — see
ROADMAP-KDE-PORTS.md punch list.
