#!/usr/bin/env bash
# StockTick probe: fetch quotes (Yahoo Finance chart API, keyless, no key),
# build sparkline + portfolio math, write state, print ONE strict JSON line
# (jq -c-era contract: single-line write, last-line read).
#
# Why Yahoo: Stooq was the first choice but now 404s its snapshot endpoint and
# serves a JS proof-of-work challenge on the daily CSV (verified 2026-10-26).
# Yahoo's v8 chart endpoint answers plain GETs from this network with both the
# live quote (meta) and the daily series in one call per symbol.
#
# Env:
#   STOCKTICK_STATE  state file (default ~/.cache/gdeyoung.stocktick/quotes.json)
# Args: <symbols,comma> <primary> <positions SYM:QTY:COST lines or "-">
set -euo pipefail

SYMS="${1:-SPY,QQQ,AAPL}"
PRIMARY="${2:-SPY}"
POSITIONS="${3:--}"
STATE="${STOCKTICK_STATE:-$HOME/.cache/gdeyoung.stocktick/quotes.json}"
mkdir -p "$(dirname "$STATE")"

/usr/bin/python3 - "$SYMS" "$PRIMARY" "$POSITIONS" "$STATE" <<'PY'
import json, os, sys, time, urllib.parse, urllib.request

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) plasma-stocktick/0.1"}

def chart(sym):
    url = ("https://query1.finance.yahoo.com/v8/finance/chart/"
           + urllib.parse.quote(sym, safe="")
           + "?range=3mo&interval=1d")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA),
                                timeout=10) as r:
        d = json.load(r)
    res = d["chart"]["result"][0]
    meta = res["meta"]
    closes = [c for c in (res["indicators"]["quote"][0].get("close") or [])
              if c is not None]
    return {"sym": meta.get("symbol", sym).upper(),
            "close": meta.get("regularMarketPrice"),
            "prevClose": (meta.get("previousClose")
                          or meta.get("chartPreviousClose")
                          or (closes[-2] if len(closes) >= 2 else None)),
            "spark": [round(c, 4) for c in closes[-31:]]}

syms, primary, positions, state = (sys.argv[i] for i in range(1, 5))
syms = [s.strip() for s in syms.split(",") if s.strip()]
primary = primary.strip() or (syms[0] if syms else "SPY")
all_syms = syms + [p for p in [primary.upper()] if p not in syms]

quotes, spark = {}, []
try:
    for s in all_syms:                      # sequential; N is small (watchlist)
        q = chart(s)
        quotes[q["sym"]] = {"close": q["close"], "prevClose": q["prevClose"],
                            "deltaPct": 0.0}
        if q["sym"] == primary.upper():
            spark = q["spark"]
except Exception as e:
    print(json.dumps({"ok": False, "error": "fetch: %s" % e},
                     separators=(",", ":")))
    sys.exit(0)

for s, q in quotes.items():
    prev = q.get("prevClose") or q["close"]
    q["deltaPct"] = round((q["close"] - prev) / prev * 100, 3) if prev else 0

pf = None
if positions and positions != "-":
    rows, ok = [], True
    for line in positions.splitlines():
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        p = t.split(":")
        if len(p) != 3:
            continue
        try:
            sym, qty, cost = p[0].strip().upper(), float(p[1]), float(p[2])
        except ValueError:
            continue
        q = quotes.get(sym)
        if not q:
            ok = False
            continue
        prev = q.get("prevClose") or q["close"]
        rows.append({"sym": sym, "qty": qty, "last": q["close"],
                     "mkt": round(q["close"] * qty, 2),
                     "dayPl": round((q["close"] - prev) * qty, 2),
                     "totPl": round((q["close"] - cost) * qty, 2)})
    if rows:
        pf = {"rows": rows, "ok": ok,
              "totMkt": round(sum(r["mkt"] for r in rows), 2),
              "totDayPl": round(sum(r["dayPl"] for r in rows), 2),
              "totPl": round(sum(r["totPl"] for r in rows), 2)}

doc = {"ok": True, "asof": int(time.time()), "primary": primary.upper(),
       "quotes": quotes, "spark": spark, "portfolio": pf}
line = json.dumps(doc, separators=(",", ":"))
tmp = state + ".tmp"
with open(tmp, "w") as fh:
    fh.write(line)
os.replace(tmp, state)
print(line)
PY
