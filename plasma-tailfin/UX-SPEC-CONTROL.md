# plasma-tailfin — Control Spec (v0.2 candidate, r2)

Extends the read-only port with the three control operations, gated and
testable. Review scope: §T-1..§T-9. Conventions follow krunner-hermes
UX-SPEC.md: every interactive element has defined states, and every state a
source of truth. Design language: Kirigami primitives only, compact popup,
no modals launched from the applet popup (Plasmoid popup + Dialog window is
a known-janky combo; two-step inline is the widget-native confirm).

r2 folds the UX verdict (deleg_96598ff9, APPROVE-WITH-CHANGES ×8):
arm dead-zone, explicit disarm ordering, op watchdog, honest button
styling, minimum hit targets, `use` tooltip, message-row stacking, and
switching/failure cleanup incl. the login-required case.

r3 (2026-11-03) appends §R-1..§R-12 — v0.3 tabbed popup redesign. The
flat scrolling list is dead: user verdict "No tabs, just a big long
fucking list. It scrolls." §R supersedes the §T-9 wireframe; §T-1..§T-8
(gates, allowlist, confirm, exit-node ops, busy/failure) carry forward
unchanged.

HARD invariants (not up for redesign):
- Automation never executes control ops against the real `tailscale` binary.
  All tests/harness runs use a stub. First real op is the user at the desk.
- Ops are a closed allowlist; argv is built only from typed enums (§T-2).
- Disconnect confirmation is mandatory and not configurable (§T-3).
- disabledTextColor is used ONLY for disabled=true. An enabled control is
  never styled to look disabled.

## T-1 — Operator gate

- On popup open (not per poll), run read-only `tailscale debug prefs`;
  parse `OperatorUser`. Probe once per plasmoid load; cache last-known.
- Controls render iff `OperatorUser === current user` (this box:
  gdeyoung — enabled).
- When disabled: no buttons anywhere; one hint row under the header:
  `control disabled — run: sudo tailscale set --operator=$USER`
  (disabled color, single line). Rows/list unchanged.
- Probe failure (tailscaled down): keep last-known verdict. First-ever
  load with daemon down = controls hidden, hint row says
  `control unavailable — tailscaled not responding` (retry next popup open).
- Hint row position: third in the header message stack (§T-5 order).

## T-2 — Closed op allowlist

Control.js exports `opArgv(op)`; the ONLY constructible invocations:

| op (typed) | argv | note |
|---|---|---|
| `up` | `tailscale up` | no flags — reuses saved prefs |
| `down` | `tailscale down` | confirmed path only (§T-3) |
| `exit-set` | `tailscale set --exit-node=<target>` | target resolved §T-4 |
| `exit-clear` | `tailscale set --exit-node=` | empty value = clear |
| (probe) | `tailscale debug prefs` | read-only, §T-1 |

Binary path overridable via `TS_BIN` (default `tailscale`) for the harness.
Tests assert: the exported map is total, exact, and contains no other
strings — no op ever yields `up/down/set` outside these five rows.

## T-3 — Connect / disconnect (header toggle)

- Header gains a trailing flat ToolButton in the title row (right-aligned,
  next to selfName):
  - Running: `Disconnect` — normal textColor at rest, hover background;
    negativeTextColor only while armed.
  - Stopped: `Connect` — normal textColor, hover background.
  - In-flight: disabled, label `working…` (disabledTextColor — honest).
- **Connect: single click.** Up is additive/safe.
- **Disconnect: two-step inline confirm with an arm dead-zone.**
  1. Click 1 arms: text becomes `Confirm disconnect`
     (negativeTextColor), and a one-line warning appears beneath the
     title (negative color, small font):
     `tailnet goes down here — remote access via ts.net drops until reconnect`
  2. **Dead-zone:** a click on the button within 500 ms of arming is
     IGNORED (state stays armed, the 4 s window keeps running). This
     closes the double-click path — the canonical stray in a panel popup.
  3. Click 2 after the dead zone, within the 4 s window, fires `down`.
  - Auto-disarm at: 4 s elapsed, popup close, op launch (armed=false at
    launch, so the warning line and `working…` never coexist), or any
    other control click.
  - **Other-control-click ordering:** clicking any other enabled control
    while armed DISARMS and PERFORMS that control's action (arm
    Disconnect → click `use` → exits armed state, exit-set fires,
    `down` never does).
  - No modal. No config to skip the confirm.

## T-4 — Exit-node set / clear

- **Candidates:** Online peers whose raw AllowedIPs contain `0.0.0.0/0`
  (same data the routes line already shows).
- **Set:** candidate rows get a trailing `use` ToolButton in the name row
  (flat, neutralTextColor, hover background; single click, no confirm —
  trivially reversible). Tooltip: `use <peer name> as exit node` (resolved
  DisplayName, so it teaches even when the row name is elided).
  Active exit node's row keeps its existing `exit` tag and hides its own
  `use` button (re-select is a no-op).
- **Hit targets:** `use` and `×` ToolButtons are at least
  `Units.gridUnit * 1.4` (~22–24 px) tall with horizontal padding, and
  separated from row/banner text by at least smallSpacing — a click aimed
  at the node name or banner text cannot land on a control.
- **Target resolution:** DNSName with trailing dot stripped; fallback first
  TailscaleIP. (Stable across renames better than HostName.)
- **Clear:** the active exit-node banner (`▸ exit node: X`) gains a
  trailing `×` ToolButton (tooltip `stop using exit node`). Single click.
  Works for Mullvad exits too (banner already names them).
- In-flight: all `use`/`×` buttons disabled; target row shows `switching…`
  as a transient sub-line, cleared on completion OR failure OR timeout.
- Mullvad region *picking* stays out of scope (Trayscale/CLI territory).

## T-5 — Busy, refresh, failure, message stack

- One op at a time; presses during flight are ignored (no queue).
- **Op watchdog:** each op has a timeout — 15 s for `down`/`exit-set`/
  `exit-clear`, 30 s for `up` (can block on auth/network). On timeout:
  kill the source, error row `op timed out`, re-enable controls. The
  executable engine only reports on process exit; without this the widget
  would sit in `working…` forever.
- Op completes → force an immediate status re-poll (bypass the interval
  Timer) so feedback is the refreshed list/banner/chip, not a toast.
- **Failure row:** one line, negative color, small font:
  - `up` failing with an auth/login URL in output →
    `login required — run: tailscale login` (actionable over raw stderr)
  - otherwise `op failed: <first line of stderr>` (fallback
    `op failed: exit <n>` when stderr is empty)
  - dismissed by the next successful op or popup reopen. No auto-retry.
  Controls re-enable immediately after any op end (exit or timeout).
- **Header message stack order** (coexistence defined, top→bottom):
  1. armed warning (§T-3)
  2. op error (this section)
  3. operator-gate hint (§T-1)
  4. health warnings (existing)
  All single-line elided except health (wrap, as today).

## T-6 — Chip unchanged

The compact chip reflects polled status only — no busy/armed state leaks
into the panel bar. (We do not display state we don't know.)

## T-7 — Execution + stub architecture

- Ops run through the same `plasma5support` `executable` engine as the
  status poll (source = argv string; connect on demand, disconnect on
  data), launched with `TS_BIN` if set in plasmashell's environment.
- Node tests (`tests/control.test.js`), no real binary anywhere in PATH:
  - allowlist totality/exactness (§T-2 table, byte-for-byte argv)
  - probe parser: operator match / mismatch / absent / daemon-down
  - target resolution: dot-strip, IP fallback, non-candidate rejection
  - confirm machine: arm → dead-zone re-click → still armed (no `down`
    in log) → post-zone click fires; arm → 4 s timeout → disarm;
    arm → popup close → disarm; arm → other-control click → that op
    fires, `down` never; connect needs no arm
  - watchdog: op with tiny timeout never resolving → timeout surfaces,
    controls re-enable, `switching…` cleared
  - exclusivity: second op while in-flight is refused at the API level
  - error formatting: auth-URL case, stderr first-line case,
    empty-stderr fallback
- Harness: stub `tailscale` shell script first in PATH + `TS_BIN` export;
  logs each argv line to a file; serves canned `status --json` (connected,
  one exit-node candidate, one offline peer) and `debug prefs`
  (OperatorUser gdeyoung). Driver asserts pixels (arm/confirm states, use
  buttons, banner ×) AND the stub log after synthetic clicks.

## T-8 — Scope guard

Still NOT ported: Mullvad region picker, Taildrop, tailscale SSH launcher,
account switching, advertise-routes toggles, preference editing.
README "Differences" section updates to move up/down + exit-node set/clear
into the ported column.

## T-9 — Popup wireframe (delta only)

```
gdtower                              [Disconnect]   ← title-row flat ToolButton
100.x.y.z · gdtower.…dns
tailnet goes down here — …            ← msg 1: armed only (negative)
op failed: …                          ← msg 2: last op failure (negative)
control disabled — run: sudo …        ← msg 3: operator gate (disabled color)
▸ exit node: tower                   [×]            ← clear action
● tower            exit              [use hidden — it's active]
  100.x.y.z · tower.dns
  routes: 0.0.0.0/0, ::/0
● nasbox                             [use]
  100.x.y.z · nasbox.dns             (≥gridUnit·1.4 tall, smallSpacing gap)
```

---

# v0.3 — Tabbed popup redesign (r3 sections §R-1..§R-12)

Mandatory restructure of the fullRepresentation. Verdict on v0.2's popup:
"No tabs, just a big long fucking list. It scrolls." The one ScrollView +
inline ListView over unbounded peer data is the anti-pattern the house
rule exists for — the popup becomes a PC3.TabBar + StackLayout in the
sysmon Details.qml house pattern. **The compact chip is liked and STAYS
BYTE-IDENTICAL** (§T-6 restated: glyph, count `online/total`, `!`/`–`
fallbacks, click-to-toggle — zero diff in `compactRepresentation`).
§T-1..§T-8 control semantics (gate, allowlist, arm/dead-zone, exit-node
ops, watchdog, message strings) carry forward verbatim.

Design data volume is MEASURED, not assumed (live tailnet, 2026-11-03):
**40 peers total, 19 ONLINE, 21 offline.** The fit budget below must hold
zero-scroll at 19 online. Offline peers stay collapsed behind a count
row exactly as designed.

## R-1 — Tab inventory

PC3.TabBar + PC3.TabButton + StackLayout, `currentIndex` shared, house
pattern copied from plasma-sysmon/contents/ui/Details.qml (v0.7). Last
tab persists via KConfig (`lastTab`, int, default 0 = Status; same
save/restore shape as sysmon's `lastTab`).

| # | Label (i18n) | Contents | Data source |
|---|---|---|---|
| 0 | `Status` | this-device identity, backend state, exit node | `status.self*`, `backendState`, exit-node state |
| 1 | `Peers` | online peer grid, offline collapsed count | `peers` / `filterOnline`, `rawPeers` (routes) |
| 2 | `Health` | warnings, backend detail, operator, provenance | `health`, gate state, tick stamp |

Three tabs, not two: health/backend is a required surface (it has
standing content — backend state, operator, provenance — so the tab is
never empty; warnings are the variable part). Not more than three: no
fourth tab has standing content the model can fill (see §R-9 flags).
Static labels only — no count badges on tabs; counts live in section
labels inside tabs, always computed.

## R-2 — Frame geometry & fit budget

**Fixed frame, identical for all tabs.** Sizing lives in ONE shell file
(the fullRepresentation root) and nowhere else — the sysmon single-site
rule; v0.6-style per-tab self-sizing is dead (popup jumps on tab
switch). Width authority flows one way: `Layout.minimumWidth` +
`Layout.preferredWidth` equal on the root, children inherit; no child
the popup sizes (`parent.width`) feeds back into popup width.

| Dimension | Value | @ gridUnit 18 (100%) | @ gridUnit 22 (125%) |
|---|---|---|---|
| Width | `34·gu` | 612 px | 748 px |
| Height | `27·gu` | 486 px | 594 px |

Family check: weatherx popup is `46·gu` wide (min `30·gu`), self-height
capped `40·gu`; sysmon frame is 960×640. Tailfin's `34×27·gu` sits
inside both — a status widget's popup, not a dashboard. `27·gu` height
is far under Plasma's popup cap (~94% desktop height), so no screen
clamp at any supported scale. Watch for the frozen `popupWidth` /
`popupHeight` applet-config keys overriding hints after any popup-open
crash — audit appletsrc for them if the frame misbehaves in harness.

**Peers-tab fit math (the budget, px constants are sysmon's):**

```
gu = Kirigami.Units.gridUnit   row height R = 1.5·gu

Vertical chrome (all tabs):
  top margin 12 + header 32 + gap 8 + TabBar ≈2.2·gu + gap 8 + bottom 12
Peers-tab fixed rows:
  section label 16 + 4  +  offline count row 18 + 6
Grid viewport height   G = 27·gu − 2.2·gu − 116 px = 24.8·gu − 116
Zero-scroll capacity   C = 2 · ⌊G / R⌋        (2-column grid)

@ gu=18:  G = 330 px, R = 27  → ⌊330/27⌋ = 12 rows → C = 24 peers
@ gu=22:  G = 430 px, R = 33  → ⌊430/33⌋ = 13 rows → C = 26 peers
```

- Measured demand: **19 online peers = 10 rows = 270 px ≤ 330 px** →
  zero-scroll with 5 spare slots (2 full spare rows) of headroom at
  gu=18; capacity only grows with `gu` (only TabBar scales).
- With ONE persistent message-strip row present (gate hint, +22 px):
  G = 308 → 11 rows → C = 22 ≥ 19. **Budget guarantee: 19 online,
  zero-scroll, even with the gate-hint row showing.**
- Transient armed-warning/op-error rows (a further 22 px each) may push
  the grid into scroll while visible — accepted; they auto-clear (§T-3/
  §T-5 windows are 4 s / next op).
- **Scroll policy beyond budget:** >C online peers, or offline section
  expanded (21 offline = 11 more rows), the peers content scrolls
  (ScrollView + StopAtBounds, scrollbar lane reserved on the right edge
  so it never covers a `use` button). The FRAME never resizes — scroll
  is the overflow valve, not a geometry change.
- One-column rejection: 19 × 27 px = 513 px > 330 px — a single-column
  list cannot make budget at any honest row height; two columns is the
  density answer (grid, alphabetical, row-major — Model already sorts
  online-first then `HostName`).

Width check: 612 − 32 margins − 8 gutter = 572 → column 286 px; name
elide-right at ~180 px + `use` ~60 px fits without truncating fleet
names. Sublines elide-middle.

**Type scale (one sweep, all tab files — spot-small is a defect):**
hero selfName `0.8·gu` bold · peer name `0.62·gu` · sublines & stamps
`Kirigami.Theme.smallFont` (≤`0.6·gu`) · section labels `0.5·gu` bold,
`Font.AllUppercase`, `disabledTextColor`, letterSpacing 0.4 (weatherx
section-label pattern; source strings stay Title Case).

Colors: Kirigami.Theme tokens ONLY (`textColor`, `disabledTextColor`,
`positiveTextColor`, `negativeTextColor`, `neutralTextColor`) — dark and
light Breeze both correct by construction; no hex literals in new files
(v0.2 already binds `positiveTextColor` in the popup; if it ever logs
undefined on this Plasma build, fall back to sysmon's `#3fd18b`/
`#f4405c` and note it in README Verified).

## R-3 — Status tab

```
THIS DEVICE                              ← section label
gdtower                                  ← hero 0.8·gu bold (selfName)
100.101.135.9 · gdtower.horse-frog.ts.net  ← selfIp · selfDnsName
● RUNNING                                ← state pill, computed CAPS
EXIT NODE                                ← section label
▸ exit node: tower                  [×]  ← active (§T-4 copy + clear)
NO EXIT NODE · 3 CANDIDATES ON PEERS TAB  ← when none active (computed)
```

Row inventory: identity block (selfName hero; subline joiner `·`,
existing v0.2 fields, elide-middle); backend-state line (see §R-7 for
the CAPS mapping and colors — honest polled state, never busy/armed
state); exit-node block — active banner + `×` clear button byte-identical
to §T-4 (tooltip `stop using exit node`, works for Mullvad exits via
`activeMullvadExit`); when no exit node is active and
`exitNodes.length > 0`, one muted hint line whose count is computed.
No OS row for self (§R-9 flag 5). Power toggle is NOT here — it lives in
the shared header (§R-6) so §T-3 is reachable from every tab.

## R-4 — Peers tab

Two-column grid of compact cells, alphabetical (Model sort), row-major.
Cell anatomy (height `1.5·gu`, both lines):

```
┌───────────────────────────────┐  ┌───────────────────────────────┐
│ ● tower       ACTIVE exit [use]│  │ ● nasbox                [use] │
│   100.x.y.z · tower.dns · 0.0.0.0/0 │  │   100.x.y.z · nasbox.dns      │
└───────────────────────────────┘  └───────────────────────────────┘
```

- Line 1: state dot (`0.35·gu`, `positiveTextColor` online) + name
  (`0.62·gu`, elide-right) + right-aligned muted tags in fixed order
  `ACTIVE` (neutral, when `peer.Active`) then `exit` (neutral, when
  `peer.ExitNode`), then the `use` ToolButton (§T-4 unchanged: online
  candidates whose raw AllowedIPs carry `0.0.0.0/0`, hidden on the
  active exit node and whenever the gate is disabled, hit target
  ≥ `1.4·gu`, ≥ smallSpacing from name text, tooltip
  `use <resolved name> as exit node`).
- Line 2 (muted, elide-middle): `<ip> · <dnsName>`; when the peer
  advertises routes (AllowedIPs minus its own /32 /128 — existing
  `subnetRoutes` logic): append ` · <routes joined ", ">`. Full string
  (all routes, un-elided) in the cell tooltip.
- Offline section BELOW the online grid, default-collapsed behind a
  count row (house rule: secondary sections default-collapse):
  - collapsed: `21 OFFLINE · SHOW` — centered muted row, count computed
    from `offlinePeers.length`, click expands (and collapses);
  - expanded: header `21 OFFLINE · HIDE` + the same 2-column cells with
    muted styling (dot and name `disabledTextColor`) and line 2
    `<ip> · last seen <fmtLastSeen>` (`never seen` for never); the
    config `showOffline` seeds the initial expanded/collapsed state,
    the click toggles it for this popup session.
- `switching…` transient sub-line on the target row (§T-4) renders as a
  third line inside that cell only — cell height grows for its duration;
  this can scroll the grid; accepted (transient by the same windows).
- Empty states: online count 0 with offline >0 → `ONLINE · 0` label +
  centered muted `NO ONLINE PEERS`; zero peers total → single centered
  `NO PEERS · TAILNET EMPTY`.

## R-5 — Health tab

```
BACKEND
● RUNNING · POLL EVERY 10 S            ← state + interval (computed)
NEEDS LOGIN · RUN: tailscale login     ← only when needsLogin

WARNINGS
⚠ <health[i]> …                        ← wrap, negative, order preserved
NO WARNINGS                            ← when list empty

OPERATOR
CONTROL ENABLED · gdeyoung             ← gate verdict + identity (computed)

PROVENANCE
● AS OF 14:03:22                       ← sysmon stamp pattern
```

Standing content: backend state (CAPS mapping §R-7), poll interval
(computed from `pollSeconds`), warnings list (existing `⚠ ` rows),
operator verdict (`CONTROL ENABLED|DISABLED|UNAVAILABLE` — when
disabled, the §T-1 hint string verbatim beneath), provenance stamp
(`● AS OF hh:mm:ss`, goes `◐ STALE` when the last tick is older than
3× poll interval — sysmon's stamp semantics; requires a `statusStampMs`
UI property stamped in `applyStatus`, NOT model data). Mullvad note:
active Mullvad exit is named on Status; Mullvad peers never list
(Model excludes them) — no dead Mullvad rows here.

## R-6 — Shared chrome (header + message strip)

Header (all tabs, sysmon house shape, height 32): left = `selfName`
bold 13 px (fallback `Tailscale`); right = §T-3 power ToolButton
(`Connect` / `Disconnect` / `Confirm disconnect` / `working…` — states,
colors, arm behavior byte-identical to §T-3).

Message strip sits BETWEEN header and TabBar (visible on every tab —
these rows annotate controls that live in shared chrome):

1. armed warning (§T-3 string, negative)
2. op error (§T-5 strings, negative)
3. operator-gate hint (§T-1 strings, disabled color)

**Amendment to §T-5:** stack item 4 (health warnings) MOVES to the
Health tab; the strip is items 1–3 only. Popup open/close behavior
unchanged (reopen clears op error; close disarms).

## R-7 — Copy catalog & grammar

Grammar: STATUS words rendered CAPS; subtext joiner is ` · ` (single
space each side — v0.2's double-space `  ·  ` is retired); counts are
always computed properties, never literals. §T-3/§T-4/§T-5 control and
banner strings are APPROVED and byte-identical — the CAPS rule governs
new v0.3 strings only (control labels stay sentence-case: `use`, `×`,
`Disconnect`…; the `exit` row tag stays lowercase per §T-9-as-shipped).

| String | Where | Binding (all computed) |
|---|---|---|
| `Status` `Peers` `Health` | tabs, i18n | static |
| `Connect` `Disconnect` `Confirm disconnect` `working…` | header | §T-3 unchanged |
| `<selfIp> · <selfDnsName>` | Status | `status.selfIp`/`selfDnsName` |
| `RUNNING` `NEEDS LOGIN` `STOPPED` … | Status pill, Health | `backendState.toUpperCase()` |
| `▸ exit node: <name>` + `[×]` | Status | §T-4 unchanged (Mullvad via `activeMullvadExit`) |
| `NO EXIT NODE · <N> CANDIDATES ON PEERS TAB` | Status, when inactive & candidates>0 | `exitNodes.length` |
| `ONLINE · <N>` | Peers section label | `onlinePeers.length` |
| `<ip> · <dns>` [` · <routes>`] | Peers line 2 | peer fields + `subnetRoutes()` |
| `ACTIVE` / `exit` | Peers tags | `peer.Active` / `peer.ExitNode` |
| `<ip> · last seen <fmtLastSeen>` / `never seen` | offline cells | `fmtLastSeen(LastSeen)` |
| `<N> OFFLINE · SHOW` / `<N> OFFLINE · HIDE` | offline toggle | `offlinePeers.length` |
| `NO ONLINE PEERS` / `NO PEERS · TAILNET EMPTY` | Peers empties | counts |
| `NEEDS LOGIN · RUN: tailscale login` | edge (§R-8) | `needsLogin` |
| `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S` | edge | unavailable + stderr |
| `TAILSCALE BINARY MISSING · INSTALL TAILSCALE` | edge | exit 127 / stderr match |
| `STATUS ERROR · RETRYING` | edge | `!parsed.ok` |
| `⚠ <text>` / `NO WARNINGS` | Health | `health` list |
| `CONTROL ENABLED · <user>` / `CONTROL DISABLED · <operator>` | Health | gate state |
| `CONTROL UNAVAILABLE · TAILSCALED NOT RESPONDING` | Health | gate unavailable |
| `● AS OF hh:mm:ss` / `◐ STALE · hh:mm:ss` | Health | `statusStampMs` vs `pollSeconds` |
| `POLL EVERY <N> S` | Health | `pollSeconds` |

## R-8 — Edge states

Detection is by existing signals only (no new probes); the binary-missing
branch must be added in `onNewData` BEFORE the current
`applyStatus("")` collapse (exit code + `lastError` are already
plumbed, just unused for discrimination):

| State | Signal | Rendering |
|---|---|---|
| Needs login | `status.needsLogin` (BackendState) | header button `Connect`; Status + Peers centers `NEEDS LOGIN · RUN: tailscale login`; Health adds it under BACKEND. No peer rows (peers empty when not running) |
| Backend down | poll exit ≠ 0, stdout empty, stderr without "not found" | all tabs: centered `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S`; poll timer keeps running; chip crossed |
| Binary missing | exit 127 OR stderr `/not found/` | all tabs: centered `TAILSCALE BINARY MISSING · INSTALL TAILSCALE`; chip crossed |
| 0 peers, running | `peers.length === 0` | Peers: `NO PEERS · TAILNET EMPTY`; Status/Health render normally |
| 0 online, offline >0 | `onlinePeers.length === 0` | `ONLINE · 0` + `NO ONLINE PEERS` + offline count row |
| Parse error | `!parsed.ok` | centered `STATUS ERROR · RETRYING` |

Edge rows replace tab content; tabs and header stay mounted (the popup
never becomes a bare error screen; Health/Status still show operator and
identity where the gate probes returned).

## R-9 — Data flags (model lacks; nothing invented)

1. **Direct-vs-relay per peer** — `status --json` carries `CurAddr`/
   `Relay` but `peerFromStatus` drops them → no connection-quality
   subtext in v0.3. Extending Model.js is an upstream diff; deferred.
2. **Traffic** — `RxBytes`/`TxBytes` are cumulative counters; rate math
   is meaningless at a 10 s poll (v0.2 decision) → not shown.
3. **OS glyphs** — `osIcon()` exists but emits Nerd Font codepoints;
   stock Bazzite fonts render tofu → not used in the popup; dot + name
   only.
4. **Parsed-but-unfetched** — `parseSuggest`, `parsePrefs`,
   `parseAccounts`, `loginPlan`, `filterPeers` (peer search) all exist
   in Model.js but no pipeline step runs their commands. v0.3 adds NO
   new exec sources; search is redundant at ≤24 visible cells.
5. **Self OS/Tags** — the normalizer extracts OS/Tags for peers only,
   not Self → Status identity has no OS row.
6. **Health severity** — warnings are strings without severity → all
   render negative color equally.
7. **Payload timestamp** — `status --json` has none; provenance stamp
   uses local tick time (`statusStampMs` is UI state, not model data).
8. **Peer grouping** — `Tags` exist but are arbitrary ACL names; no
   grouped-by-type sections in v0.3 (alphabetical grid instead). If
   grouping is ever wanted it needs a fleet-tag convention first.

## R-10 — File layout & implementation constraints (for the build pass)

- Component-split per house rule (one handler per signal per FILE):
  `main.qml` keeps ALL data plumbing/exec + chip; new
  `contents/ui/PopupShell.qml` (frame + header + strip + TabBar +
  StackLayout), `tabs/StatusTab.qml`, `tabs/PeersTab.qml`,
  `tabs/HealthTab.qml`, `PeerCell.qml` atom. `tools/check_qml.py` gate
  before every install.
- Tab files receive the PlasmoidItem root as `ctx` (never `root` —
  shadowing trap); `Plasmoid` context is root-file-only, so config
  reads (`lastTab`, `showOffline`) flow through `ctx`.
- Popup-open work (status re-poll is NOT needed — timer owns polling;
  only stamp refresh) defers through a ~150 ms Timer on
  `onExpandedChanged`; no synchronous work in the open handler.
- `metadata.json` → `0.3.0`; README Differences + Verified sections and
  ROADMAP row updated in the same commit (release-stamp rule).

## R-11 — Acceptance criteria (harness: virtual harness, scale 1 + host DPR)

1. **Fixed frame:** HARNESSGeometry probe reports identical WxH on all
   three tabs; no resize on tab switch or data tick.
2. **19-online fixture: zero scroll** — peers grid `contentHeight ≤`
   viewport height; no scrollbar pixels. Asserted with the gate-hint
   row present (worst persistent case).
3. **Capacity:** 24-online fixture still zero-scroll (empty message
   strip) per §R-2 math; 25-online scrolls — scrollbar lane does not
   overlap `use` buttons.
4. **Offline collapsed:** 21-offline fixture shows exactly one count
   row `21 OFFLINE · SHOW`, zero offline cells; click reveals 21 muted
   cells (scrolling permitted); `SHOW`/`HIDE` copy flips.
5. **Computed counts:** fixtures with different peer counts render
   different count strings; grep finds no count literals in new QML.
6. **Copy catalog:** every rendered string matches §R-7 (or §T-3/4/5
   approved strings) byte-for-byte; joiner is ` · ` everywhere.
7. **Edge fixtures** (§R-8 all six): each renders its edge copy, no
   dead rows, no empty sections, header/tabs remain mounted.
8. **Chip untouched:** `git diff` on the compactRepresentation block is
   empty; chip still reflects polled status only.
9. **Control layer untouched:** `tests/control.test.js`,
   `model.test.js`, `port.test.js` pass unchanged; harness stub-binary
   runs show no new argv beyond the §T-2 allowlist.
10. **Theme:** no hex literals in new files; dark + light Breeze
    screenshots legible (dot, tags, muted text) at both scales.
11. **Default-config pass:** one harness run on wiped config (empty
    `lastTab`, `showOffline` unset renders the collapse default).
12. **Hit targets:** `use`/`×` ≥ `1.4·gu` tall with smallSpacing
    separation, pixel-verified at both scales (§T-4 preserved).

## R-12 — Wireframe (full popup, superseding §T-9)

```
gdtower                          [Disconnect]   ← header 32 px (all tabs)
tailnet goes down here — …                      ← strip: armed only
──────────────────────────────────────────────
[ Status ]  [ Peers ]  [ Health ]               ← PC3.TabBar
──────────────────────────────────────────────
Status tab:                Peers tab (2-col):   Health tab:
THIS DEVICE                ONLINE · 19          BACKEND
gdtower                    ● tower  ACTIVE [use]● RUNNING · POLL EVERY 10 S
100.101.135.9 · gdtower…   ● nasbox       [use]WARNINGS
● RUNNING                  ● spark … (24 max)   NO WARNINGS
EXIT NODE                  21 OFFLINE · SHOW    OPERATOR
▸ exit node: tower [×]     ────────────────     CONTROL ENABLED · gdeyoung
                           (scroll only past    PROVENANCE
                            capacity or when    ● AS OF 14:03:22
                            offline expanded)
```
