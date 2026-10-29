# Finance plasmoid landscape research (2026-10-29)

Source: delegated research unit deleg_9d6aca00 task-0 (9 API calls, 17 repos
shallow-cloned + source-analyzed, endpoints probed from a real browser).
Full transcript: ~/.hermes/cache/delegation/live/deleg_9d6aca00/task-0.log
Artifacts (24h TTL): ~/.hermes/cache/scratch/plasmoid-research/ (clones + census.json)

## Census verdict

- **wolfe86/plasma-ticker-tape** (P6, active 2026-10-26) = state of the art:
  Canvas candlestick/line charts with wheel-zoom, drag-pan, crosshair,
  screener+alerts, econ calendar, journal. No portfolio, no macro dashboard.
  GitHub-only, not on KDE Store.
- **EmmanouelKontos/TickerLens** (P6, 2026-07-30) = closest overlap: watchlist
  + sparklines + portfolio (`cfg_portfolioJson` {SYM:{shares,cost}}) + ATH
  distance + earnings dates. No interactive chart, no macro. GitHub-only.
- Everything else is thin tickers or keyful (Finnhub/Alphaca/twelvedata).
- **Gap confirmed**: no plasmoid ships macro summary + portfolio + interactive
  per-stock charts + search in one popup. KDE Store has only keyful or
  one-symbol stock widgets — the investor-glance niche and the Store listing
  are both vacant.

## Yahoo endpoint matrix (browser-probed 2026-10-29)

| Endpoint | Status |
|---|---|
| v8/finance/chart/{sym} | OPEN, no crumb; meta carries near-full quote (dayHigh/Low, 52wk, currentTradingPeriod, fullday* pre/post, validRanges) |
| v8/finance/spark?symbols=A,B,C | OPEN, no crumb — multi-symbol batch in one call |
| v7/finance/spark | OPEN, no crumb (TickerLens ships it) |
| v1/finance/search?q=&quotesCount=8 | OPEN, no crumb — symbol/shortname/exchange/quoteType/score |
| v7/finance/quote | **CRUMB-GATED (401)** — avoid; chart meta + spark cover its fields |

Rate limiting is per-IP **+ TLS client fingerprint**: curl AND python-urllib
429 from this host even with Firefox UA; Qt XHR passes. Rules (wolfe86-proven):
batch via spark; poll 15–60s; on 429 double the interval; show a status row
when Yahoo refuses.

## Adopt in stocktick (post-user-verification backlog)

1. Batch watchlist + macro via one v8/spark call per refresh (perf + 429 hygiene).
2. 429 backoff doubling.
3. wolfe86 span table — fetch wider than shown: 1D→5d, 5D→1mo/15m, 1M→3mo/60m,
   6M→2y/1d, 1Y→2y/1d (pre-market inclusion).
4. Session pill from currentTradingPeriod + fullday* (replaces freshness heuristic).
5. VIX fear-line coloring (default 20).
6. Publish to KDE Store once named + blessed (vacant niche).

## Canvas charting verdict

Pure QtQuick Canvas proven at far greater complexity than ours (wolfe86
Detail.qml: candles+VWAP+volume+crosshair+zoom). org.kde.quickcharts ships
with plasma-workspace (static charts only — no crosshair) — Canvas remains
the right choice for interactive charts. Perf lesson: requestPaint() only on
changed inputs; never rebuild rows per refresh (95% CPU freeze precedent).
