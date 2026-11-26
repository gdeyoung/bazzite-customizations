// StockTick Model tests — pure JS, run: node --test tests/model.test.js
import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const src = readFileSync(new URL("../contents/ui/Model.js", import.meta.url),
                         "utf8").replace(".pragma library", "");
const Model = new Function(src + "; return {fmtPrice, fmtPct, fmtMoney, parsePositions, portfolio, normalizeSeries};")();

test("fmtPrice/fmtPct/fmtMoney formats", () => {
  assert.equal(Model.fmtPrice(765.37), "765.37");
  assert.equal(Model.fmtPrice(1234.5), "1235");
  assert.equal(Model.fmtPrice(NaN), "—");
  assert.equal(Model.fmtPct(3.578), "+3.58%");
  assert.equal(Model.fmtPct(-1.2), "-1.20%");
  assert.equal(Model.fmtMoney(1939.1), "$1,939.10");
  assert.equal(Model.fmtMoney(-42.5), "-$42.50");
});

test("parsePositions accepts SYM:QTY:COST, skips junk/comments", () => {
  const rows = Model.parsePositions("AAPL:10:150.00\n# comment\n\nbad line\nMSFT:2:300.5\nx:1:nan");
  assert.deepEqual(rows.map(r => r.sym), ["AAPL", "MSFT"]);
  assert.equal(rows[0].qty, 10);
  assert.equal(rows[1].cost, 300.5);
});

test("portfolio math: mkt/day/total P&L + totals", () => {
  const quotes = {AAPL: {close: 200, prevClose: 190}};
  const pf = Model.portfolio(Model.parsePositions("AAPL:10:150"), quotes);
  assert.equal(pf.rows[0].mkt, 2000);
  assert.equal(pf.rows[0].dayPl, 100);   // (200-190)*10
  assert.equal(pf.rows[0].totPl, 500);   // (200-150)*10
  assert.equal(pf.totMkt, 2000);
  assert.equal(pf.totPl, 500);
  assert.equal(pf.ok, true);
});

test("portfolio flags missing symbols but keeps good rows", () => {
  const quotes = {AAPL: {close: 200, prevClose: 190}};
  const pf = Model.portfolio(Model.parsePositions("AAPL:1:100\nTSLA:1:200"), quotes);
  assert.equal(pf.rows.length, 1);
  assert.equal(pf.ok, false);
});

test("normalizeSeries guards: empty/flat series, normal case y in [0,1]", () => {
  assert.equal(Model.normalizeSeries([]).length, 0);
  assert.equal(Model.normalizeSeries([5, 5, 5]).length, 3);
  assert.equal(Model.normalizeSeries([5, 5, 5])[0].y, 0.5);
  const s = Model.normalizeSeries([10, 20, 15, 30]);
  assert.equal(s.length, 4);
  assert.equal(s[0].y, 0);
  assert.equal(s[3].y, 1);
  assert.ok(s.every(p => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1));
});
