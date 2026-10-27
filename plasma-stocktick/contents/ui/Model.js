// StockTick pure helpers — UI formatting + portfolio math. No I/O.
// Data fetch lives in contents/scripts/fetch-quotes.sh (single-line JSON out).
.pragma library

function fmtPrice(v) {
    if (v === null || v === undefined || isNaN(v)) return "—";
    return v >= 1000 ? v.toFixed(0) : v.toFixed(2);
}

function fmtPct(v) {
    if (v === null || v === undefined || isNaN(v)) return "—";
    return (v >= 0 ? "+" : "") + v.toFixed(2) + "%";
}

function fmtMoney(v) {
    if (v === null || v === undefined || isNaN(v)) return "—";
    const sign = v < 0 ? "-" : "";
    return sign + "$" + Math.abs(v).toLocaleString("en-US",
        {minimumFractionDigits: 2, maximumFractionDigits: 2});
}

// sym:QTY:COST per line ("AAPL:100:182.40") → [{sym, qty, cost}]
function parsePositions(text) {
    const out = [];
    String(text || "").split("\n").forEach(line => {
        const t = line.trim();
        if (!t || t.startsWith("#")) return;
        const p = t.split(":");
        if (p.length !== 3) return;
        const qty = parseFloat(p[1]), cost = parseFloat(p[2]);
        if (!p[0] || isNaN(qty) || isNaN(cost)) return;
        out.push({sym: p[0].trim().toUpperCase(), qty: qty, cost: cost});
    });
    return out;
}

// rows: parsePositions output; quotes: {SYM: {close, prevClose}}
// → {rows:[{sym,qty,last,mkt,dayPl,totPl}], totMkt, totDayPl, totCost, totPl}
function portfolio(rows, quotes) {
    const out = {rows: [], totMkt: 0, totCost: 0, totDayPl: 0, totPl: 0, ok: true};
    rows.forEach(r => {
        const q = quotes ? quotes[r.sym] : undefined;
        if (!q || !q.close) { out.ok = false; return; }
        const prev = q.prevClose || q.close;
        const mkt = q.close * r.qty;
        const dayPl = (q.close - prev) * r.qty;
        const totPl = (q.close - r.cost) * r.qty;
        out.rows.push({sym: r.sym, qty: r.qty, last: q.close, mkt: mkt,
                       dayPl: dayPl, totPl: totPl});
        out.totMkt += mkt; out.totCost += r.cost * r.qty;
        out.totDayPl += dayPl; out.totPl += totPl;
    });
    return out;
}

// spark: [close,...] → [{x: i/(n-1), y: (c-min)/(max-min)}] (guard flat/empty)
function normalizeSeries(spark) {
    const n = spark ? spark.length : 0;
    if (n < 2) return [];
    let min = Infinity, max = -Infinity;
    spark.forEach(c => { if (c < min) min = c; if (c > max) max = c; });
    if (max === min) return spark.map((c, i) => ({x: i / (n - 1), y: 0.5}));
    return spark.map((c, i) => ({x: i / (n - 1), y: (c - min) / (max - min)}));
}
