# StockTick v2 — panel stock chip + watchlist popup

Second-generation build (v1 died in-service: frozen state, collapsed chips).
v2 swaps the python probe for the weatherx-proven curl pipeline and models
the popup on the Omarchy `5d0tal1gat0r.stocks` layout.

- **Chip**: primary symbol + price + colored Δ% (hex colors — Kirigami
  semantic colors are undefined in compactRepresentation on Plasma 6.7).
- **Popup**: hero (selected symbol, price, Δ%, 3-month sparkline) above
  watchlist rows (sym | price | colored day-change | mini sparkline); click
  a row to select it as the hero. Footer shows source + refresh interval.
- **Data**: Yahoo Finance v8 chart API — keyless, one call per symbol returns
  quote + prevClose + 3-month daily series, fetched **in parallel**
  (7 symbols in 0.27 s). Stooq is dead from this network (snapshot 404 +
  PoW challenge — verified 2026-10-26); recorded so nobody retries it blind.
  If Yahoo later blocks unauthenticated calls, the probe is one script
  (`contents/scripts/fetch-quotes.sh`) to swap.
- **Plumbing**: identical to weatherx — one fire-once `connectSource()` per
  fetch, disconnect-on-data, single-line JSON contract. No state file; the
  probe is stateless (fetch → print → exit).
- **Files**: `main.qml` (chip + popup + hero), `StockRow.qml` (watchlist
  row delegate — own file for the one-handler-per-signal rule),
  `Model.js` (pure formatters + sparkline normalization), curl probe
  `contents/scripts/fetch-quotes.sh` (+x required — the executable
  dataengine silently refuses non-executable scripts).

## Config (KConfig XT)
`symbols` (comma list, Yahoo format, indices `^GSPC`), `primary` (chip+hero),
`refreshMin` (1–120). No portfolio fields in v2 — helpers remain in Model.js.

## Verified (2026-10-27)
- `tools/check_qml.py plasma-stocktick` → 2 files, 0 errors, 0 warnings.
- Live probe: 7-symbol watchlist single-line JSON in 0.27 s; fresh prices
  (MSFT 532.83, market open); spark arrays populated.
- Model.js unit tests 5/5 (formats, parser junk-filtering, P&L, missing
  symbol flag, series guards).

## Install / rollback
```
./install.sh                       # user-level, reversible
systemctl --user restart plasma-plasmashell.service   # only if ghosts
kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.stocktick  # rollback
```
Panel placement (Greg's Omarchy layout): StockTick immediately LEFT of the
centered clock, weatherx immediately right — see ROADMAP-KDE-PORTS.md.
