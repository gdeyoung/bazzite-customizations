# Plasma Tailfin

Tailscale tailnet status in the KDE Plasma 6 panel — a compact chip with the
Tailscale dot-mark glyph (state-colored: active / crossed-out when down /
warning badge for needs-login or health issues) and an **online/total** peer
count, opening a device-list popup: this-device identity, exit-node banner,
health warnings, and every machine with name, connection state (green/dim dot),
subnet routes, and Tailscale IPs/DNS name. Offline machines collapse behind a
count by default.

Ported from the author's own [omarchy-tailfin](https://github.com/gdeyoung/omarchy-tailfin)
(Hyprland/Quickshell, `gdeyoung.tailfin`) to native Plasma 6 — same Model.js
logic, same data source, read-only, zero system mutations.

```
chip:   ▪▪▪  12/40      ← Tailscale mark + online/total; click to open
popup:  this-device name · self IP · dns
        ▸ exit node: <host>          (when one is active)
        ⚠ health warnings            (when tailscale reports any)
        ● tower            exit      ← green=online, dim=offline
          100.x.y.z · dns.name
          routes: 0.0.0.0/0, ::/0
        ● nasbox
          100.x.y.z · dns.name
          routes: 192.168.50.0/24
        3 offline — hidden           (click settings to show them)
```

## Provenance

- Source: [github.com/gdeyoung/omarchy-tailfin](https://github.com/gdeyoung/omarchy-tailfin),
  local snapshot commit `05fdbd7`.
- `contents/ui/Model.js` is ported **VERBATIM** (sha256
  `f31483eb3ca8b0b0bdcd6a006b8562bc57d0aff20d6191a5db546cea3eb20c12`,
  byte-identical to the Omarchy plugin's Model.js; a root-level `Model.js`
  mirror exists only so `node --test` can require it — a test asserts the two
  never drift).
- The Omarchy plugin's watched `Process` running `tailscale status --json`
  (Service.qml) becomes Plasma's `executable` dataengine
  (`org.kde.plasma.plasma5support`) polling the same read-only command on an
  interval.
- Panel.qml's four-tab layout is re-expressed as a single self-sizing device
  list — see **Differences** for what was deliberately left out.
- Upstream lineage: omarchy-tailfin is itself a fork of Omarchy's first-party
  `omarchy.tailscale` panel (MIT).

## Differences vs the Omarchy panel (deliberate scope)

The Omarchy panel is a full Tailscale client. The Plasma port is a status
view plus a minimal, gated control surface (v0.2, `UX-SPEC-CONTROL.md`):

- Kept: connection state + counts, self identity (name/IP/DNS), health
  warnings, active exit-node name, machine list with online state, subnet
  routes, IPs, DNS names, last-seen, offline collapsed/expanded; **v0.2
  adds** connect/disconnect, exit-node set/clear — behind a
  `tailscale set --operator` gate, with a mandatory two-step inline
  disconnect confirm (500 ms arm dead-zone kills the double-click path),
  an op watchdog (15 s / 30 s for `up`), and a closed typed-op allowlist.
- Not ported: Mullvad region picking, account switching, Taildrop
  send/receive, SSH launcher, health-warning acknowledgement, preference
  toggles, keyboard-driven cursor navigation. On KDE, Trayscale or the
  Tailscale CLI cover those. Model.js stays byte-identical to the Omarchy
  port; all control logic lives in the separate `Control.js` layer.

## Control surface (v0.2) and its safety rules

- **Ops are a closed allowlist** (`Control.js`): `up`, `down`,
  `set --exit-node=<host>`, `set --exit-node=`. Nothing else is
  constructible; tests assert the map byte-for-byte.
- **Operator gate:** controls render only when `tailscale debug prefs`
  reports `OperatorUser` = the current user (read-only probe, once per
  load). Otherwise one hint row names the exact fix.
- **Disconnect cannot be a stray click:** arm → 500 ms dead-zone (extra
  clicks ignored) → confirm within 4 s, with the remote-lockout warning
  shown while armed. Popup close or any other control disarms.
- **Tests never touch the real binary:** `tests/control.test.js` is pure
  logic (injected clocks/env); the harness (`tools/popup-harness/
  run-tailfin.sh`) puts a logging stub first in the nested session's PATH
  and asserts the stub's argv log. The first real control op is always
  the user's own click at the desk — a disconnect from a remote tailnet
  session has no recovery path until physical access.

## Data source

`tailscale status --json` — no arguments, no state change. Polled every
`interval` seconds (default 10; KConfig XT, 5–3600). Mullvad peers are
filtered from the machine list (Model.js behavior); an active Mullvad exit
node still surfaces in the banner. Subnet routes per peer are read from the
payload's `AllowedIPs` (host `/32`//`/128` self-entries stripped) — kept from
the raw Peer map because Model.js's normalizer drops that field; joined on
`peer.id`. Traffic counters are not shown: the model carries cumulative
bytes, which are meaningless without rate math over a fast poll.

## Config keys (contents/config/main.xml + config.qml)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `interval` | Int | `10` | Seconds between `tailscale status --json` polls (5–3600) |
| `showOffline` | Bool | `false` | Show offline devices inline instead of a collapsed count |

## Install

Requires Plasma 6.3+, the `tailscale` CLI on PATH, and `kpackagetool6` (shipped
with Plasma). No sudo, no compiling — installs to
`~/.local/share/plasma/plasmoids/` and survives Bazzite/ostree updates.

```bash
./install.sh                 # copy + restart plasmashell (standard)
./install.sh --dry-run       # show what would happen
./install.sh --plasmoid-id com.gdeyoung.plasma.tailfin.test   # side-by-side test copy
./install.sh --no-restart    # copy only; restart plasmashell yourself later
```

Then: right-click panel → **Enter Edit Mode** → **Add Widgets** → search
**Tailfin** → drag to panel.

## Rollback

```bash
kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.tailfin
systemctl --user restart plasma-plasmashell.service
```

(`./install.sh --plasmoid-id X` installs are removed the same way with that
id; a plain `rm -rf ~/.local/share/plasma/plasmoids/<id>` + restart also works
since the package is just files.)

## Verified (static, this repo — install not performed)

- `tools/check_qml.py plasma-tailfin` → **0 errors, 0 warnings, exit 0**
  (1 QML file checked: contents/ui/main.qml; metadata.json rules pass).
- `node --test tests/model.test.js tests/port.test.js` → **21/21 pass**
  (14 upstream Model tests against the verbatim file + 7 port-contract tests
  using a synthetic `tailscale status --json` payload; no host-specific
  payload is committed).
- Model.js sha256 verified identical to the Omarchy source snapshot.
- install.sh **NOT run** (code-complete artifact; install is an install-day
  step per the repo's port roadmap).

## Install-day verify plan (run when at the tower)

1. `./install.sh`, then add the widget to the panel.
2. Chip renders the dot mark with state color and `N/M` count; hover + click
   opens the popup.
3. `journalctl --user -u plasma-plasmashell.service --since -5min | grep -i tailfin`
   → no QML errors naming `main.qml` / `Model.js`.
4. Popup lists real machines (online dot colors, routes lines on advertisers),
   exit-node banner matches `tailscale status` output, health warnings match.
5. Config round-trip: set interval 5 s in widget settings → chip count updates
   visibly faster; set Show offline devices → offline machines appear inline.
6. Toggle `tailscale down`/`up` in a terminal (or stop tailscaled) → chip
   switches to crossed glyph and popup shows Disconnected within one interval.
7. Screenshot chip + popup (spectacle) for the README.
8. Rollback check: `kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.tailfin`
   + restart → widget gone, panel intact.

## Development

```bash
node --test tests/model.test.js tests/port.test.js tests/control.test.js  # 50 tests
python3 ../tools/check_qml.py .                      # static QML/metadata check
./install.sh --dry-run                               # preview install actions
```

## Verified (v0.2)

- 50/50 node tests (model + port + control allowlist/confirm/watchdog).
- `tools/popup-harness/run-tailfin.sh` at scale 1 and 2 (host-DPR
  geometry): stubbed `tailscale` — journal checkpoints (gate=enabled,
  arm, dead-zone held, fire, exit-set, end) + stub argv log exact
  (one `down`, one `set --exit-node=…`, no dead-zone leak); pixels
  confirmed: Disconnect/Confirm-disconnect + warning line, banner ×,
  `use` on candidate rows only, `exit` tag on the active node, offline
  footer. Scale-2 armed shot missed the 2.4 s transient (spectacle
  capture latency at 5120×2880) — armed-state pixels verified at
  scale 1; wire sequence verified at both scales.

## License

MIT — see [LICENSE](LICENSE). Model.js carries its upstream MIT lineage from
omarchy-tailfin / Omarchy's `omarchy.tailscale` panel.
