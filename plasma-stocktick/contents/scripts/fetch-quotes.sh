#!/usr/bin/env bash
# StockTick v2 probe — invoked by the executable dataengine (curl pipeline).
# Args: <symbols,comma> — outputs ONE strict JSON line:
# {"ok":true,"quotes":{"SYM":{"close":n,"prevClose":n,"deltaPct":n,"spark":[...]}}}
# One curl per symbol (parallel), Yahoo chart API, keyless. Spark = 31 closes.
set -euo pipefail
SYMS="${1:-MSFT}"
OUT="$(mktemp "${TMPDIR:-/tmp}/stocktick.XXXXXX")"
trap 'rm -f "$OUT".*' EXIT
export OUT

one() {
  local s="$1" enc u
  enc=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$s")
  u="https://query1.finance.yahoo.com/v8/finance/chart/${enc}?range=3mo&interval=1d"
  curl -fsS --max-time 12 -A "Mozilla/5.0 (X11; Linux x86_64) plasma-stocktick/2.0" \
       -o "$OUT.$s" "$u" || rm -f "$OUT.$s"
}

pids=""
for s in ${SYMS//,/ }; do one "$s" & pids="$pids $!"; done
for p in $pids; do wait "$p" 2>/dev/null || true; done

python3 - "$OUT" ${SYMS//,/ } <<'PY'
import json, os, sys
out = sys.argv[1]; syms = sys.argv[2:]
quotes = {}
for s in syms:
    path = f"{out}.{s}"
    if not os.path.exists(path):
        continue
    try:
        d = json.load(open(path))
        res = d["chart"]["result"][0]
        meta = res["meta"]
        closes = [c for c in (res["indicators"]["quote"][0].get("close") or []) if c is not None]
        prev = meta.get("previousClose") or (closes[-2] if len(closes) >= 2 else None) \
               or meta.get("chartPreviousClose")
        cur = meta.get("regularMarketPrice")
        if cur is None or prev is None:
            continue
        quotes[s.upper()] = {"close": cur, "prevClose": prev,
                             "deltaPct": round((cur - prev) / prev * 100, 2),
                             "spark": [round(c, 2) for c in closes[-31:]]}
    except Exception:
        continue
print(json.dumps({"ok": len(quotes) > 0, "quotes": quotes}, separators=(",", ":")))
PY
