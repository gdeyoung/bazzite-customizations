# plasma-timemachine — a KDE Plasma 6 plasmoid

Backup status chip for the Plasma 6 panel: status glyph (OK / stale / running
pulse / failed) + last-backup age, expanding into a **five-tab Time Machine
panel** — **Status · Snapshots · Health · Recovery · Settings** — over a
self-hosted, **unencrypted rsync time machine** on your own NAS or server,
plus local btrfs snapshots. Plain files, browsable, no keys to lose.

Plasma 6 port of [gdeyoung/omarchy-timemachine](https://github.com/gdeyoung/omarchy-timemachine)
(v0.5.4, commit `519df33`, 2026-10-19). The Omarchy six-tab layout folds
"Backups" (off-box rsync trees) into **Snapshots** as a REMOTE BACKUPS
section — same data, one fewer tab.

## Why

Backups you can't inspect aren't backups. The chip makes backup state
impossible to ignore; the popup keeps restore paths one click away. The
bundled engine is the upstream one — every backup is a full directory tree
hardlinked against the previous, browsable and recoverable with plain
`ssh`/`scp`, from any machine, with zero tooling.

## What's in the box

```
metadata.json                     # Plasma/Applet manifest (KPlugin Id com.gdeyoung.plasma.timemachine)
contents/ui/main.qml              # applet root: chip + probe plumbing + actions
contents/ui/Details.qml           # popup root: header, 5-tab bar, self-sizing page stack
contents/ui/StatusTab.qml         # verdict, stat cards, backup-size chart (SizeBars), actions
contents/ui/SnapshotsTab.qml      # local snapper day-groups + REMOTE BACKUPS section
contents/ui/HealthTab.qml         # drill / verify / healthcheck / target disk / drift rows
contents/ui/RecoveryTab.qml       # plaintext emergency card + restore-a-file flow
contents/ui/SettingsTab.qml       # engine conf summary + Back up now / drill / refresh
contents/ui/SizeBars.qml          # bar chart (ported near-verbatim)
contents/ui/{ActionPill,StatePill,DayGroup}.qml
contents/ui/TmHelpers.js          # formatting/day-grouping helpers (pure JS)
contents/config/main.xml          # KConfig XT keys
contents/config/config.qml        # settings page
contents/scripts/                 # the ENGINE — ported byte-identical (sha256-pinned in tests/)
install.sh                        # user-level install (parameterized)
tests/pin.test.mjs                # node --test suite (port pins + live engine contracts)
tests/engine-sha256.json          # verbatim-port ledger vs upstream 519df33
```

## The engine (`contents/scripts/`) — ported VERBATIM

All shell is byte-identical to upstream `519df33` (the test suite pins the
sha256 of every engine file; any local edit breaks `node --test`). The engine
is shell-only and shell-agnostic — nothing in it knows about Quickshell or
Plasma.

- `tm-probe.sh` — one JSON line for the chip: reads state stamps
  (`last-backup.json`, `history.jsonl`, `drill/verify/health-last.json`) +
  `systemctl --user` for run state and next timer fire. Cheap, local-only,
  never blocks the bar. Thresholds (stale/fail hours) flow as argv.
- `tm-backups.sh` — remote backup-tree listing for the Snapshots tab
  (popup-open only; derives host/dest at runtime from the stamp).
- `tm-snapper.sh` — local btrfs/snapper snapshot listing (popup-open only).
- `tm-snapshots.sh` — deprecated one-release shim over `tm-backups.sh`.
- `bin/tm-backup.sh` — rsync `-aH --no-D --link-dest` backup + retention +
  weekly sentinel sha256 verify. Stages into a hidden unique dir, publishes
  by rename, refuses existing destinations; only a clean run advances
  `latest` and the success stamp.
- `bin/tm-restore.sh` — `--list / --latest / --backup ID / --files GLOB /
  --drill`; restores stage to a scratch dir, **never write live state**.
- `bin/tm-health.sh` — healthcheck + optional failure notification.
- `bin/tm-conf.sh` — the ONLY thing that ever writes the conf (validated
  `init/get/set/json/test/install/uninstall --yes`).
- `bin/tm-common.sh` — conf loader (env > conf > default).
- `bin/timemachine.conf.example` — every conf key, placeholder values.

Configuration lives in `~/.config/timemachine.conf` (chmod 600). Keys:
`TM_HOST` (required, `[user@]host`), `TM_DEST` (required, remote path),
`TM_SSH_PORT`, `TM_LABEL`, `TM_STATE_DIR`, `TM_EXCLUDES`, `TM_SCHEDULE`
(`HH:MM` list), `TM_UNIT`, `TM_RETENTION_DAILY/WEEKLY/MONTHLY`,
`TM_VERIFY_DOW`, `TM_SENTINELS` (colon list), `TM_MAX_AGE_H`,
`TM_NOTIFY_CMD`, `TM_PRE_HOOK`, `TM_POST_HOOK`, `TM_DRIFT_FILE`.

**Engine prerequisites:** bash, `python3` (probe/conf JSON), `ssh` +
`rsync` (backups/restores), `snapper` (optional — local Snapshots tab),
key-based SSH to the target (`ssh-copy-id`). No sudo anywhere; systemd user
units for the timer.

## Plasmoid configuration keys (Plasma config dialog)

| Key | Default | Meaning |
|---|---|---|
| `refreshSeconds` | 15 | chip refresh interval (5–60 s) |
| `staleHours` | 26 | stale threshold (probe argv) |
| `failHours` | 72 | failed threshold (probe argv; > stale) |
| `historyDays` | 14 | history window (informational) |
| `snapshotRows` | 10 | rows per expanded day group (5–50) |
| `confPath` | `~/.config/timemachine.conf` | engine conf path (parameter — no LAN specifics shipped) |

The plasmoid never writes the engine conf: all writes go through
`bin/tm-conf.sh` (terminal), or the engine's own systemd paths.

## Install

```sh
./install.sh                       # default id com.gdeyoung.plasma.timemachine
./install.sh com.gdeyoung.plasma.timemachine.dev   # or a custom id
```

User-level only: copies to `~/.local/share/plasma/plasmoids/<id>` and
restarts `plasma-plasmashell.service`. Then right-click panel → Enter Edit
Mode → Add Widgets → search "TimeMachine" → drag to panel.

First run on a host without `~/.config/timemachine.conf`: the chip shows
`--`/NO BACKUP. Set up the engine:

```sh
cp contents/scripts/bin/timemachine.conf.example ~/.config/timemachine.conf  # edit TM_HOST/TM_DEST
# or: contents/scripts/bin/tm-conf.sh init && contents/scripts/bin/tm-conf.sh set TM_HOST user@nas.example …
contents/scripts/bin/tm-conf.sh test       # reachability + free space
contents/scripts/bin/tm-conf.sh install    # systemd user timer
```

## Rollback / uninstall

```sh
kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.timemachine && systemctl --user restart plasma-plasmashell.service
contents/scripts/bin/tm-conf.sh uninstall --yes   # optional: engine timer units (backups untouched)
```

Removing the plasmoid never touches backups or conf.

## Verification (this repo, static — host has no tm engine configured)

- `tools/check_qml.py plasma-timemachine` → exit 0 (11 QML files, 0 errors).
- `bash -n` on all 10 shell scripts → clean.
- `node --test tests/pin.test.mjs` → 24 tests: verbatim-engine sha256 ledger,
  Plasma-port structure pins, live probe/conf/backups/snapper JSON contracts
  on this unconfigured host, scratch-fixture engine behavior (stubbed
  ssh/rsync, tmpdir only — no network, no state writes outside `/tmp`).
- `tm-probe.sh` smoke run here → valid no-state JSON (`state: "never"`).
- Engine-dependent behavior (real backup, restore drill, timer install) NOT
  executed on this host — deferred to install day.

## Install-day verify plan

1. `./install.sh`; add widget to panel; chip shows `--` (unconfigured) with
   tooltip "not configured".
2. Configure engine conf (`tm-conf.sh init/set` or the example file), then
   `tm-conf.sh test` → reachable, free GB reported.
3. Chip flips to a state glyph + age after the first probe tick (≤15 s);
   `journalctl --user -u plasma-plasmashell.service` shows no QML errors
   naming `timemachine` files.
4. Open popup: Status tab renders verdict + cards; Snapshots tab lists local
   snapper groups (if snapper present) and remote backups after fetch;
   Health tab all rows; Recovery shows copyable commands; Settings shows
   the conf summary matching `tm-conf.sh json`.
5. Actions: RUN DRILL completes (PASS) on a configured target; BACK UP NOW
   starts the service (watch the chip pulse, then age reset).
6. Popup self-sizes per tab (no scrollbar on Status at default font); tab
   switch keeps height tracking the visible page.
7. Config round-trip: change `refreshSeconds` in the config dialog → probe
   tick rate changes; restore default.

## Security & trust (inherited from upstream)

Endpoints/credentials live only in your local conf (600) — the repo carries
zero hostnames, IPs or keys (enforced by test). QML never writes files; the
UI is non-destructive (no delete, no overwrite; restore stages to scratch,
merge is a deliberate act; snapshot rollback stays a boot-menu/terminal
action). Clipboard text travels base64 over stdin, never on argv.

## Dev

```sh
../../tools/check_qml.py .          # static QML checks
node --test tests/pin.test.mjs      # 24 pins incl. verbatim-engine ledger
```

Chart idiom adapted from `gdeyoung.sysmon` (HistBars, MIT) via upstream.
SizeBars ported near-verbatim; container QML rewritten for Plasma 6
(PlasmoidItem, plasma5support DataSource, Kirigami theme colors).

## License

MIT — see [LICENSE](LICENSE). Upstream: github.com/gdeyoung/omarchy-timemachine.
