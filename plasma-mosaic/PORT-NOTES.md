# plasma-mosaic — Port Notes & Engine Ledger

Port of [naolselemon/mosaic](https://github.com/naolselemon/mosaic) (Omarchy
shell plugin, MIT) to KDE Plasma 6, following the campaign conventions in
ROADMAP-KDE-PORTS.md.

## Engine ledger (byte-identical vendoring)

Vendored from upstream clone @ `9b3f4d78611b5714f2039be48e59922c1158301a`
(manifest version 0.1.1), verified sha256-identical on 2026-11-01:

| File (contents/lib/mosaic/) | sha256 |
|---|---|
| actions.py | f53c9d5e…61bd00e1 |
| installations.py | 59e00a92…19fcac0 |
| journal.py | 472cb9fe…5d7595b46 |
| mappings.py | 189adf2a…6762f9a2 |
| scanner.py | 602d8b3d…656f94e8 |
| updates.py | 3a4728b9…6846b8a05 |
| workspace.py | 5d0ffca3…d026bfa7a |
| en.json (i18n) | identical |

The ONLY changes vs upstream live in `tests/python/*` (PROJECT path adjusted to
the plasma package layout) — engine modules themselves are untouched.
Re-verify after any engine refresh: `sha256sum` both sides.

## Host layer (new code, no upstream counterpart)

`contents/lib/mosaic_host/mosaic_cli.py` replaces Omarchy's Service.qml IPC
(plasma5support dataengine = one process per call, one JSON line out):

- `accumulate()` mirrors upstream `Service.qml receive()` + `Protocol.js`
  replacePath/withPaths EXACTLY: in-place index replacement, ownership-identity
  verification, known-byte aggregation (`mappedBytes`/`categories` never travel
  in scanner events — they are recomputed from measured paths; possible/shared
  bytes are measured but excluded from totals, per upstream semantics).
- Snapshot cache `~/.local/state/omarchy/mosaic/plasma-snapshot.json` (0600,
  atomic tmp+rename) for instant popup opens; deep scans never clobber it.
- Single-flight lock (pid + /proc cmdline liveness) → `{"busy": true}`.
- Every scan journalizes via upstream `workspace {op:"record"}` (history is
  opt-in upstream — `historyEnabled` defaults false; enable via the settings op).
- `open` → vendored actions.py (FileManager1, rejects symlinked components);
  `copy` → klipper `setClipboardContents` over busctl (verified present on
  gdtower; both actions are user-visible — first live firing is install-day).

## v0.1 scope decisions (deliberate; revisit per roadmap)

1. **Standalone widget, not a driveway tab.** Driveway = mounted-storage
   management (disks/shares/cloud); Mosaic = per-app file attribution on the
   system drive. Different engines, different data domains — folding them in
   bloats both. One concern per widget (campaign pattern).
2. **No pacman attribution on Fedora.** `installations.py` degrades gracefully
   when `pacman-conf`/`/var/lib/pacman` are absent: native install sizes are
   simply unavailable; flatpak attribution (the dominant app channel on
   Bazzite) works. v0.2 candidate: rpm attribution as a ledgered host adaptor —
   do NOT patch the vendored engine in place.
3. **State paths keep the upstream `omarchy/mosaic` layout** so engine history/
   settings/mappings stay byte-compatible and the vendored ledger stays clean.
4. **updates.py vendored but unwired** (Omarchy plugin-update checker is
   meaningless under kpackagetool6). Kept for test-suite completeness.
5. **Synchronous scan via dataengine** (fire-once pattern). Scanner self-alarms
   at 35 s (overview) / 100 s (deep). Fallback if the dataengine proves to kill
   long-running commands: detach the scan behind the wrapper + poll
   `mosaic status` (lock-liveness already implemented).
6. **Deferred to v0.2** (see docs/mosaic-v01-popup-spec.md): dashboard with
   history/yearly insights, mappings editor, in-popup settings (v0.1 prefs →
   Plasma config dialog), shortcuts help page, progressive scan fill.

## Verification status (2026-11-01)

- Engine + host suites: **145/145 pass** (`/usr/bin/python3` 3.14.8, gdtower).
- Real-HOME E2E (read-only): 254 apps discovered, 22 known-mapped, 28.57 GB
  total (Brave 15.1 GB via flatpak namespace, Heroic 7.5 GB); aggregation
  invariant verified per-app; `limited` flag correctly marks lower bounds.
- Deep scan E2E: Brave 17.5 GB with subdirectory breakdown; overview cache
  preserved.
- Clipboard/open actions: arg-level verified only (klipper + FileManager1
  present on host); live firing deferred to install day (user-visible side
  effects).
- QML: pending UX spec (docs/mosaic-v01-popup-spec.md) → harness gates.

## QML lane + harness (2026-11-02)

- UX spec gate satisfied: docs/mosaic-v01-popup-spec.md (delegated designer pass).
- QML lane: 11 UI files + config (main.xml + config.qml) per spec — single-page
  drill-down Overview → App detail → Category, shared header/breadcrumb, no
  top-level tab bar; donut annular R74/r48 via vendored DonutGeometry; MosaicStore
  singleton carries all harness-drivable state (incl. expandedPath).
- check_qml.py: 0 errors (66 warnings = known checker false-positive class,
  identical to plasma-driveway's shipped files). qmllint: clean.
- Node: 7/7 (ViewModel semantics). Python: 145/145.
- Harness (tools/popup-harness/run-mosaic.sh, private XDG_RUNTIME_DIR isolation):
  SCALE=1 PASS — all 8 HARNESS probes, 6/6 distinct screenshots (chip, overview,
  search, app, expanded, category), journal clean, heartbeat alive
  (engine-side: mosaic_cli.py `_heartbeat` writes /tmp/plasma-mosaic-hb.json on
  every successful engine command; QML sync-XHR file writes are unreliable on
  Qt 6, so the store no longer writes it).
- SCALE=2: QML transitions PROVEN via injected probes (StackLayout index 2,
  CategoryPage visible, store consistent, no errors) but the harness rig stops
  submitting popup frames at 5120×2880 under llvmpipe — plasma-tailfin
  reproduces identically on the same rig, so this is an environment limitation,
  not a widget defect. Donut frame did render at 2× (overview paint present in
  both s2 runs before the stall). Host DPR is 1; per harness doctrine the gate
  is SCALE=1 + host DPR.
- QML defects found and fixed by the harness: bare `ScrollBar.vertical`/
  `ScrollBar.AsNeeded` attached usage (must be `PC3.`-qualified; kills applet
  load), `PC3.ButtonGroup.buttons` cannot take a Repeater's children (journal
  error storm + main-thread lag; exclusivity now derived from store state),
  PathCard undefined→bool visible bindings.
- Harness driver lessons: emit evidence before teardown (dbus-run-session
  teardown can wedge the driver tree); every blocking call (busctl/spectacle)
  needs its own timeout; QML console lands in the journal, not plasmashell
  stderr.
