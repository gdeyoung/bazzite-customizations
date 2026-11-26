# Plasma Mosaic

A read-only **application-storage explorer** for the KDE Plasma 6 panel: where each
desktop app keeps its config, data, cache and state — measured sizes, ownership
confidence (known / possible / shared), per-path evidence, subdirectory breakdowns
and deeper per-app scans. Ported from
[naolselemon/mosaic](https://github.com/naolselemon/mosaic) (Omarchy/Quickshell)
to native Plasma 6. The python engine is vendored **byte-identical** (see
PORT-NOTES.md ledger); only the shell plumbing and QML layer are new. User-level
only: no sudo, no compiling, survives Bazzite/ostree updates.

```
panel chip:      ◈ 28.6 GB      ← Mosaic mark + total mapped bytes (dim while
                                  scanning; "not scanned yet" before first scan)
popup:           Overview · Categories · App details (drill-down) · Rescan
```

## What runs what

The plasmoid shells out to the mosaic CLI (`contents/scripts/mosaic` →
`contents/lib/mosaic_host/mosaic_cli.py` + vendored engine in
`contents/lib/mosaic/`) via Plasma's `executable` dataengine
(`org.kde.plasma.plasma5support`):

| Purpose | Command |
|---|---|
| Overview scan | `mosaic scan` (single-flight, ~1–25 s; snapshot cached to XDG state) |
| Cached snapshot | `mosaic snapshot` (instant popup open with last scan) |
| Chip status | `mosaic status` |
| Deeper scan | `mosaic deep <desktop-id>` |
| Dashboard/history/mutations | `mosaic workspace '<json>'` (upstream workspace.py ops) |
| Open folder | `mosaic open <path>` → vendored actions.py → org.freedesktop.FileManager1 |
| Copy path | `mosaic copy <path>` → org.kde.klipper.setClipboardContents |

Read-only by design: the engine never writes app files; the only writes are the
private plugin state under `~/.local/state/omarchy/mosaic/` (0700, same layout as
upstream, so history/settings/mappings survive and stay compatible).

## State

`BUILD` (engine + CLI + tests complete; QML in progress) — see PORT-NOTES.md and
docs/mosaic-v01-popup-spec.md. Nothing is installed by the build process; see the
repo ROADMAP-KDE-PORTS.md install punch list.

## Tests

```
cd plasma-mosaic
export TMPDIR=/var/home/<user>/.hermes/cache/scratch   # symlink-free; engine rejects symlinked paths
export PYTHONPATH=tests/python                          # sibling test imports
/usr/bin/python3 -m unittest discover -s tests/python -p 'test_*.py'
```

145 tests: 134 vendored from upstream (engine) + 11 host-layer (accumulator
mirrors upstream Protocol.js semantics; snapshot IO; path validation).
