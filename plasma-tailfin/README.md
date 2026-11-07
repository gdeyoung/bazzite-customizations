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
popup (v0.4 — single sectioned view, one scroll, no tabs):
  gdtower                          [Disconnect]
  ● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
  🔍 [ Search peers                                    ] ✕
  EXIT NODES · 5
    ▸ exit node: tower                              [×]
    ● spark2          [ACTIVE]                      [use]
      100.x.y.z · spark2.horse-frog.ts.net
  ONLINE · 13
    ● aibox      ● watertower     ● spark   ● nas    (2-col, ● name)
  21 OFFLINE · SHOW                                   ← collapsed
  ● AS OF 14:22:31                    CONTROL ENABLED · gdeyoung
Frame fixed at 34×38·gu (612×684 @100%); only the section stack scrolls
(exit nodes → online → offline). Search filters ALL peers live
(multi-token, prefix/substring/subsequence, name · hostname · DNS · IP).
Edge states: needs-login / backend down / binary missing / parse error —
each with standing content, never a dead popup.
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
- **v0.3** replaced the flat list with a 3-tab popup — *rejected in desk
  use (sparse pages, navigation tax)*; **v0.4** removed the tabs for a
  single Trayscale-sectioned view (EXIT NODES get their own section and
  never duplicate into ONLINE; offline collapses behind a count row;
  health warnings returned to the top strip; live search added).
  (spec `§R-1..§R-12` in `UX-SPEC-CONTROL.md`): fixed frame, 2-column
  peer grid with computed offline collapse, four discriminated edge
  states, persisted last tab. Chip and control surface unchanged.
- **v0.5** (*rejected in desk use: "barely, barely, barely usable…
  the way you structure the tabs are trash"*) rebuilds the popup per
  `docs/UX-SPEC-V5.md` (§W-1..§W-19): ONE scrollable peer lane under
  pinned chrome — header (self identity + search toggle + §T-3 power),
  §T-5 message strip, and a both-modes **routing band** ("▸ exit node:
  X [×]" / "no exit node · direct · N available"). Exit sections and the
  census grid are deleted; every peer is a full-width rich **PeerRow**
  (state dot · name · badges `ACTIVE EXIT`/`exit`/subnet-CIDR · `use` on
  candidates · subline `OS · IP · direct|via <relay> [· ↓rx ↑tx]` /
  `last seen <t>`). Search is revealed by a header button (Ctrl+F),
  filters in place (label flips to `MATCHES · N`), offline rows dim
  0.62 behind a standard toggle row. The v0.4 `ACTIVE` tag (session
  traffic, not exit selection) is deleted; liveliness is the ↓/↑
  counters. §T-1..§T-8 control semantics and every §T string carry
  byte-identical; chip untouched.
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

## Verified (v0.5)

- 68/68 node tests (model + port + control + search; port.test §W-2
  inventory updated to the v0.5 file set — control/model/search suites
  byte-identical).
- `tools/check_qml.py plasma-tailfin` → 0 errors (6 QML files).
- `tools/popup-harness/run-tailfin-v5.sh` (fixture `norm19` = the real
  tailnet shape 19/40): frame 612×685 pixel-stable across search,
  offline-expand (lane content 733→1489 px absorbed by scroll; pinned
  zones fixed); count invariants exact (online 19 + offline 21 = 40 =
  chip; candidates 5 + census 13 + active-exit 1 = 19); search
  host03→2 / zzz→0 / cleared→sections; offline toggle + dimmed rows;
  gate-off run: no buttons, hint only. Fixtures `norm19h` (2 health ⚠,
  orange, wrapped ≤2 lines), `zero19` (ONLINE · 0 + NO ONLINE PEERS),
  `empty` (NO PEERS · TAILNET EMPTY), Breeze light, and scale 2 all
  green. Vision-audited screenshots: rich rows, badges, routing band,
  MATCHES search state, no scrollbar clipping (reserved 0.8·gu lane).
  Candidate rows render 40px (Breeze Button floor) — the §W-19
  documented exception; plain rows 33px ±1; hit targets ≥ 1.4·gu kept.
- CC technology-architecture cross-check on the spec: 0 surviving
  MATERIAL findings (its size-loop/fixed-px/lupdate concerns are
  contradicted by the gu-derived frame/rows and the absence of
  translations; scale matrix run green).

## License

MIT — see [LICENSE](LICENSE). Model.js carries its upstream MIT lineage from
omarchy-tailfin / Omarchy's `omarchy.tailscale` panel.
