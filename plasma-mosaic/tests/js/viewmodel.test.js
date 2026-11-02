// Node tests for the vendored ViewModel.js (upstream semantics, Qt arg-mock).
// Run: node --test plasma-mosaic/tests/js/viewmodel.test.js
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, '../../contents/ui/lib/ViewModel.js'), 'utf8');
// .pragma library is a QML directive; strip it for plain-node evaluation
const js = src.replace(/^\.pragma library\s*/m, '');
const Model = new Function(js + '\nreturn {categoryKeys, appsFor, findApp, indexFor, bytes, appSize, pathSize, coverage, orderedPaths, skippedReasons};')();

class QtString extends String {
  // Qt semantics: each arg() call substitutes the lowest unfilled placeholder
  arg(value) {
    const s = String(this);
    return new QtString(s.includes('%1') ? s.replace('%1', String(value)) : s.replace('%2', String(value)));
  }
}
const units = { 'unit.B': 'B', 'unit.KiB': 'KiB', 'unit.MiB': 'MiB', 'unit.GiB': 'GiB', 'unit.TiB': 'TiB', 'unit.PiB': 'PiB' };
const strings = {
  t(key) { return new QtString(key === 'size.value' ? '%1 %2' : (units[key] || key)); },
};
const numbers = { formatNumber(n, digits) { return n.toFixed(digits === undefined ? 0 : digits); } };

test('appsFor sorts by mappedBytes desc then name, filters by query', () => {
  const apps = [
    { id: 'b', name: 'Brave', mappedBytes: 100 },
    { id: 'a', name: 'Ark', mappedBytes: 500 },
    { id: 'c', name: 'Chrome', mappedBytes: 500 },
  ];
  const sorted = Model.appsFor(apps, '');
  assert.deepEqual(sorted.map(a => a.id), ['a', 'c', 'b']);
  const filtered = Model.appsFor(apps, 'brave');
  assert.deepEqual(filtered.map(a => a.id), ['b']);
  const byId = Model.appsFor(apps, 'B'); // case-insensitive id match
  assert.deepEqual(byId.map(a => a.id), ['b']);
});

test('bytes formats with binary units and lower precision under 100', () => {
  assert.equal(String(Model.bytes(0, strings, numbers)), '0 B');
  assert.equal(String(Model.bytes(1536, strings, numbers)), '1.5 KiB');
  assert.equal(String(Model.bytes(15.1e9, strings, numbers)).startsWith('14.1'), true); // 15.1e9 / 1024^3 = 14.06 GiB -> 14.1
  assert.equal(String(Model.bytes(null, strings, numbers)), 'size.unknown');
});

test('appSize lower-bounds partial apps, handles unmapped', () => {
  const base = { status: 'complete', mappedBytes: 42, paths: [{ confidence: 'known', bytes: 42 }] };
  assert.equal(String(Model.appSize(base, strings, numbers)), '42 B');
  const partial = Object.assign({}, base, { status: 'partial' });
  assert.equal(String(Model.appSize(partial, strings, numbers)), 'size.lowerBound');
  const unmapped = { status: 'unmapped' };
  assert.equal(String(Model.appSize(unmapped, strings, numbers)), 'app.unmapped');
});

test('orderedPaths ranks known first, then bytes desc', () => {
  const paths = [
    { path: '/c', confidence: 'possible', bytes: 50 },
    { path: '/b', confidence: 'known', bytes: 10 },
    { path: '/a', confidence: 'known', bytes: 90 },
    { path: '/d', confidence: 'shared', bytes: 900 },
  ];
  assert.deepEqual(Model.orderedPaths(paths).map(p => p.path), ['/a', '/b', '/c', '/d']);
});

test('coverage counts mapped apps and excluded paths', () => {
  const apps = [
    { paths: [{ confidence: 'known' }, { confidence: 'possible' }] },
    { paths: [{ confidence: 'possible' }] },
  ];
  const result = Model.coverage(apps);
  assert.equal(result.mapped, 1);
  assert.equal(result.excluded, 2);
});

test('categoryKeys matches upstream display order', () => {
  assert.deepEqual(Model.categoryKeys, ['data', 'cache', 'config', 'state']);
});

test('skippedReasons filters zero counts and sorts', () => {
  const reasons = Model.skippedReasons({ permissions: 3, depth: 0, budget: 1 });
  assert.deepEqual(reasons, [
    { reason: 'budget', count: 1 },
    { reason: 'permissions', count: 3 },
  ]);
});
