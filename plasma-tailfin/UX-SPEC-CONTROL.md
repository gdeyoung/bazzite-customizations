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

r4 (2026-11-04) appends §V-1..§V-14 — v0.4 single-view redesign. Verdict on
v0.3: "NOPE, THE UX STILL FUCKING SUCKS… LOOK AT WHAT WE BUILT FOR
TAILFIN AND OMARCHY. THAT UX WAS OKAY. YOU CAN LOOK AT TRAYSCALE." Tabs
are dead; §V supersedes §R-1..§R-12 (strings re-adopted where noted);
§T-1..§T-8 carry forward unchanged, chip stays byte-identical.

r5 (2026-11-07) — v0.4 REJECTED in desk use ("It's barely, barely, barely
usable… a lot of information in an easy to understand, simplified
interface"). The v0.5 redesign lives in `docs/UX-SPEC-V5.md` (§W-1..§W-19):
one unified rich-row peer list (the v0.3 verdict's own architecture) with
pinned glance chrome (header → §T-5 strip → routing band → revealed search →
footer). §W supersedes §V-3..§V-14 (popup structure, rows, search surface,
edge rendering); §V-8's search ENGINE and §V-10 edge strings carry verbatim;
§T-1..§T-8 control semantics carry forward unchanged; chip stays
byte-identical. Deliberate §T-9/§V deviations are ledgered in §W-15.
Release stamp: 0.5.0 shipped 2026-11-07 — 68/68 tests, check_qml 0
errors, harness matrix green (norm19/norm19h/zero19/empty × gate on/off
× Breeze dark/light × scale 1/2), vision-audited rows/band/search,
README Verified (v0.5).

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

---

# v0.4 — Single-view popup redesign (r4 sections §V-1..§V-14)

> **BUILD STATUS (2026-11-04): SHIPPED as tailfin v0.4.0.** 68/68 node
> tests; full harness matrix green — norm19 (gate enabled+disabled),
> norm24 (24 online zero-scroll, content 516 ≤ view 547), norm25 (valve
> opens, 598 > 548), empty/login/down/missing/parse, LIGHT, SCALE=2;
> GEO-UNIQUE=1 (612×685 logical) everywhere incl. search round-trip;
> count-sum invariant ok on every tick; search pixel-verified
> (host03 → MATCHES · 2 = prefix host03 + subsequence host103);
> needs-login strip + Connect header pixel-verified. Two §V-4 ledger
> deviations implemented as specified (no `routes:` line, exit tag →
> tooltip).

Mandatory restructure of the fullRepresentation. The two approved poles:
the Omarchy §T-9 single view (context-first, inline actions, zero
navigation — "THAT UX WAS OKAY") and Trayscale's information
architecture (THIS MACHINE / EXIT NODES / ONLINE / OFFLINE sections,
live peer search, explicit empty states — "YOU CAN LOOK AT TRAYSCALE").
v0.4 deletes the tab chrome and rebuilds the popup as ONE sectioned view
with Trayscale's section semantics, verified against trayscale master
(`internal/ui/mainwindow.go` sidebarLayout/searchSidebarLayout,
`internal/peersearch/peersearch.go`):

- Exit-node-capable ONLINE peers get their own EXIT NODES section and
  are EXCLUDED from the Online census (never two places for one peer).
- A section with zero rows renders no label at all.
- Search is a first-class control: multi-token, all tokens must match,
  substring or in-order subsequence over name/hostname/DNS/IP, results
  score-sorted; empty result has an explicit empty state.

§T-1..§T-8 control semantics (gate, allowlist, arm/dead-zone, exit-node
ops, watchdog, message strings) carry forward byte-identical. The chip
stays byte-identical (§T-6 restated).

## V-1 — Diagnosis: why v0.2 and v0.3 both failed, and what prevents each

| # | Failure mode (evidence) | v0.4 structural prevention |
|---|---|---|
| 1 | **Sparse fixed-frame pages.** Status and Health each filled ~20% of the 612×487 frame; the frame was sized for Peers, so every other tab read as an unfinished diagnostic dump (rej-v03-status/health: 35–50% of the panel blank) | No pages. One view whose every section draws from live data; a section with count 0 renders nothing. No surface can exist without content |
| 2 | **Navigation tax.** Identity, exit switching, and health each lived on a different tab; the whole was never glanceable, each tab sparse alone | Zero navigation in the popup. All four glanceables (identity+state, exit node, peer census, health) sit on the first screenful, pinned above any scrolling region |
| 3 | **Dialog-like geometry.** A fixed 487 px frame read as a window, not a tray popup | Width unchanged (never the complaint); height rises to 38·gu ONLY because measured content (19/3/21 split) demands it — §V-5's ledger accounts for every row; no filler |
| 4 | **Density without hierarchy.** 1.5·gu two-line cells, 6–8 px sublines, three competing status treatments (green dot / orange ACTIVE / orange exit), tags eliding into a floating right column with ambiguous row association (rej-v03-peers) | Census cells are name-only one-liners in a 2-col grid — no sublines, no tags, no second status vocabulary. Tags exist in exactly one place (ACTIVE on the active exit candidate). Detail lives in tooltip + search, not in microtext |
| 5 | **Buried actions.** Exit switching needed a tab hop; `SHOW` looked like footer text; the operator remediation was dead prose rendered twice (header + Health) | Exit nodes are a first-class SECTION at the §T-9 position (top of the list); `use`/`×` inline there; remediation string renders exactly once (message strip); footer carries only the verdict |
| 6 | **Duplication.** `gdtower` in header AND under THIS DEVICE; control-disabled string in header AND Health | The header IS the machine block (§T-9 shape: title row + identity line). Dedup rule: every string has exactly one render site (§V-7) |
| 7 | **Wall-of-peers (v0.2).** 40 ungrouped rows, one endless scroll, offline dominant | Trayscale sectioning: exit-capable pulled out and never duplicated, offline collapsed behind a count row by default, census zero-scroll at 19 measured online; live search for find-by-anything |

## V-2 — Disposition of v0.3 artifacts (what happens to the tabs)

- **Tabs: DELETED.** PC3.TabBar/TabButton + StackLayout removed from
  PopupShell.qml. Nothing tab-like replaces them; the popup contains no
  navigation of any kind — sections stack in one ScrollView.
- **Files deleted:** `tabs/StatusTab.qml`, `tabs/PeersTab.qml`,
  `tabs/HealthTab.qml`. `PeerCell.qml` is replaced by the name-only
  census atom `CensusCell.qml`. `SectionLabel.qml` survives.
- **Config:** `lastTab` — QML reader deleted, kcfg entry removed from
  `contents/config/main.xml`; a stale value in an existing appletrc is
  harmless (never read). `showOffline` survives unchanged (seeds the
  offline section's initial state). No new config keys; search is not
  configurable.
- **§R-6 amendment REVERTED:** health warnings return to the message
  strip; the §T-5 four-item stack order is restored verbatim.
- **Superseded:** §R-1..§R-12 in full. Re-adopted verbatim from §R: the
  offline toggle copy, all §R-8 edge strings, §R-7 grammar, §R-2
  type/color/token discipline (with the §V-6 label amendment), §R-10
  file/release discipline. NOT re-adopted: per-row `exit` tags
  (tautological inside a dedicated EXIT NODES section), the candidate
  row's `routes:` line (same tautology — §V-4 deviation ledger), tab
  labels, `POLL EVERY <N> S` (moves to the provenance tooltip).
- **§T-9:** its structure returns as §V-3; two row details change
  (§V-4 deviation ledger). §T-1..§T-8 untouched.

## V-3 — Popup wireframe (supersedes §R-12)

Measured tailnet shown (19 online · 3 exit-capable · 21 offline):

```
gdtower                                    [Disconnect]  ← header (§T-3 states)
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net    ← identity + state
tailnet goes down here — …                 ← strip 1: armed only (negative)
op failed: …                               ← strip 2: last op failure (neg)
control disabled — run: sudo tailscale …   ← strip 3: operator gate (disabled)
⚠ <health warning, wraps>                  ← strip 4: health (negative, wrap)
────────────────────────────────────────────────────────
[edit-find] Search peers               [✕]               ← Ctrl+F · Esc clears
EXIT NODES · 3                                           ← hidden when 0 & none active
▸ exit node: tower                          [×]          ← §T-4 banner + clear
● tower                                           ACTIVE ← active row: `use` hidden
  100.101.135.11 · tower.horse-frog.ts.net
● nasbox                                    [use]         ← §T-4 candidate
  100.101.135.14 · nasbox.horse-frog.ts.net
● host04                                    [use]
  100.101.135.20 · host04.horse-frog.ts.net
ONLINE · 16                                              ← census = online − exit-capable
● aicube          ● aibox                               ← 2-col census, name-only
● gx10            ● gx13                                (tooltip: dns · ip · routes)
● jellyfin        ● micro
● node            ● spark2         … (16 cells = 8 rows, zero-scroll)
21 OFFLINE · SHOW                                        ← collapsed (showOffline seeds)
────────────────────────────────────────────────────────
● AS OF 23:44:39            CONTROL ENABLED · gdeyoung  ← footer
```

Search mode (query non-empty) — sections are REPLACED by one result
list; header, strip, banner context, and footer stay pinned:

```
[edit-find] tow                        [✕]
MATCHES · 2
● tower                                ACTIVE [use]
  100.101.135.11 · tower.horse-frog.ts.net
● watertower
  100.101.135.2 · watertower.horse-frog.ts.net · last seen 3h ago
```

## V-4 — Section & row inventory

| Zone | Contents | Height | Source | Renders when |
|---|---|---|---|---|
| Header | selfName hero + §T-3 power ToolButton | 30 px | `status.selfName` (fallback `Tailscale`) | always |
| Identity line | `● <STATE CAPS> · <selfIp> · <selfDnsName>` | 20 px | `backendState.toUpperCase()`, self fields | parsed status known |
| Message strip | §T-5 items 1–4, in order, one line each except health (wrap) | 20 px/row | §T-3/§T-5/§T-1 + `health[]` | per-item conditions |
| Search row | `edit-find` icon + TextField (placeholder `Search peers`) + trailing `✕` clear | 34 px | UI state `peerQuery` | ≥1 peer and no down/missing/login/parse edge |
| EXIT NODES label | `EXIT NODES · <E>` | 22 px | `exitNodes.length` | E > 0 or an exit node is active |
| Banner | `▸ exit node: <name>` + `×` (§T-4 verbatim) | 26 px | active exit / `activeMullvadExit` | exit node active |
| Candidate row | `● <name>` [+ `ACTIVE` tag] + trailing `use`; line 2 `<ip> · <dns>`; transient `switching…` line 3 (§T-4) | 47 px (+20 switching) | `exitNodes[]` (online, 0.0.0.0/0 — §T-4 unchanged) | per candidate; `use` hidden on active row and when gate disabled |
| ONLINE label | `ONLINE · <N>`, N = census count | 22 px | computed | N > 0 or offline > 0 |
| Census grid | 2-col, row-major, alphabetical; cell = dot + name ONLY | 27 px pitch | online peers minus exit-capable | N > 0 |
| Census empty | centered muted `NO ONLINE PEERS` | 26 px | computed | N = 0 and offline > 0 |
| Offline toggle | `<N> OFFLINE · SHOW` / `· HIDE` | 26 px | `filterOnline(peers,false).length` | offline > 0 |
| Offline grid | same 2-col cells, muted (dot+name `disabledTextColor`) | 27 px pitch | offline peers | expanded (toggle or search) |
| Footer | `● AS OF hh:mm:ss` (→ `◐ STALE · hh:mm:ss`) + `CONTROL <verdict>` | 26 px | `statusStampMs` vs `pollSeconds` · gate state | always |
| Edge row | centered §V-10 string, replaces sections | region | §V-10 signals | edge states |

**Cell/row anatomies (final):**

- **Census cell:** `● name`. Dot 0.35·gu (`positiveTextColor` online /
  `disabledTextColor` offline), name 0.62·gu elide-right. NO subline, NO
  tags, NOT interactive (default cursor, no hover background — honest
  non-affordance; nothing in the census pretends to be clickable).
  Tooltip: `<dns> · <ip>` + ` · routes: <joined ", ">` when
  `subnetRoutes(peer)` is non-empty; offline cells append
  ` · last seen <fmtLastSeen>`.
- **Candidate row (the §T-9 action row):** line 1 `● name` + `ACTIVE`
  tag (neutral, `peer.Active`) + trailing `use` ToolButton (§T-4
  verbatim: flat, `neutralTextColor`, hover bg, single click, tooltip
  `use <DisplayName> as exit node`, hit ≥ 1.4·gu, ≥ smallSpacing from
  text; hidden on the active exit node and when the gate is disabled);
  line 2 `<ip> · <dns>` (smallFont, elide-middle). `switching…` renders
  as a transient third line on the in-flight target only.
- **Search result row:** same two-line anatomy as the candidate row
  (full 1-col width); exit-capable matches keep their `use`, the active
  one its `ACTIVE` tag; offline matches render muted with line 2
  `<ip> · <dns> · last seen <fmtLastSeen>`.

**Deviation ledger vs the approved §T-9 (deliberate, both):**

1. The candidate row's `routes: 0.0.0.0/0, ::/0` line is DROPPED from
   the row (moves to tooltip). Inside a dedicated EXIT NODES section the
   route advertisement is tautological — it is why the row exists; the
   §T-9 line predates the section (routes disambiguated candidates in a
   flat list). This deletes the most common 3-line row (every candidate
   advertises 0.0.0.0/0) and is what makes the §V-5 budget close.
2. v0.3's per-row `exit` tag is not re-adopted (same tautology).

## V-5 — Frame geometry & fit budget

**Fixed frame, one view.** Width authority unchanged from §R-2
(`Layout.minimumWidth == Layout.preferredWidth` on the root; children
inherit; nothing feeds back into popup width). The frame NEVER resizes
on data, search, section expand, or op flight — scroll is the overflow
valve, never a geometry change (§R-2 rule, restated).

| Dimension | Value | @ gridUnit 18 (100%) | @ gridUnit 22 (125%) |
|---|---|---|---|
| Width | `34·gu` | 612 px | 748 px (≈598 logical — under the ~640 bar) |
| Height | `min(38·gu, 0.9·availableHeight)` | 684 px | 836 px (clamped on short screens) |

38·gu is justified row-by-row below; at 125% capacity only grows
(px-constant chrome, gu-scaled rows — §R-2 convention). Audit
appletsrc for frozen `popupWidth`/`popupHeight` keys if the frame
misbehaves in harness (§R-2 warning carries).

**Vertical ledger (gu=18, banner present, gate-hint present — worst
PERSISTENT case; E = exit-capable online count):**

```
Fixed chrome:
  top pad 10 + header 30 + identity 20 + strip 20 + search 34
  + EXIT label 22 + banner 26 + ONLINE label 22 + offline row 26
  + footer 26 + bottom pad 10                      = 246 px
Candidates: E × 47 px (2-line anatomy, no routes line — §V-4)
Census region   G = 684 − 246 − 47·E         cell pitch 27 (1.4·gu + 2)
Census capacity C = 2 · ⌊G / 27⌋             (2-col grid)

  E=1: G=391 → C=28   demand 18 (norm19, 1 exit)   ✓ zero-scroll, 10 spare
  E=3: G=297 → C=22   demand 16 (measured shape)   ✓ 6 spare
  E=5: G=203 → C=14   demand 14                    ✓ exact — E>5 opens the valve
  norm24 (E=1): demand 23 ≤ 28 ✓      norm25 (E=1): demand 24 ≤ 28 ✓
@ gu=22: G = 836 − 246 − 57·E → E=3: 419 → C = 2·⌊419/33⌋ = 24 ≥ 16 ✓
```

- **Budget guarantee: 19 online (any E ≤ 5), 24, and 25 online —
  zero-scroll, with the persistent gate-hint row present.**
- Transients (armed warning, op error: +20 each; health warnings: wrap,
  variable; `switching…`: +20 on one row) may push the census into
  scroll while visible — accepted; they auto-clear (§T-3/§T-5 windows).
- **Scroll valve cases:** offline section expanded (21 cells = 11 grid
  rows ≈ 297 px beyond), E > 5, transients, >25 online. ScrollView +
  StopAtBounds over the SECTION STACK ONLY (header, identity, strip,
  search, footer pinned outside it); scrollbar lane reserved on the
  right edge so it never covers a `use`/`×` button.
- One-column census rejection: 18 × 27 = 486 px > 391 — cannot make
  budget; two columns is the density answer for the census (as §R-2
  found for the old grid), now safe because cells are name-only (§V-1
  failure 4).

Width check: 612 − 32 margins − 8 gutter = 572 → column 282 px; a
0.62·gu name elides-right at ~34 chars — fleet names fit untruncated.
Candidate/result rows use the full 572 px: name + tag + `use` never
collide. Search field 572 px wide.

## V-6 — Type scale, color, tokens

One sweep, all files: hero selfName `0.8·gu` bold · peer name
`0.62·gu` · sublines, tooltips, footer `Kirigami.Theme.smallFont` ·
section labels **smallFont bold, `Font.AllUppercase`, letterSpacing
0.4, `disabledTextColor`** — NOT v0.3's `0.5·gu` custom size (the
rejection screenshots' 7–8 px microtype is the floor violation; no text
renders below `smallFont`). Colors: Kirigami.Theme tokens only —
`textColor`, `disabledTextColor`, `positiveTextColor` (online dot,
RUNNING dot), `negativeTextColor` (strip rows 1/2/4, edge rows),
`neutralTextColor` (ACTIVE tag, non-running state dot); no hex literals
in new files (§R-2 fallback note stands).

## V-7 — Copy catalog & grammar (v0.4)

Grammar (§R-7 unchanged): status words CAPS; joiner ` · `; every count
computed; control labels sentence-case. **Dedup rule (new):** every
string has exactly ONE render site. §T-3/§T-4/§T-5 strings are approved
and byte-identical.

| String | Render site | Binding (all computed) |
|---|---|---|
| `<selfName>` / `Tailscale` | header hero | `status.selfName` |
| `Connect` `Disconnect` `Confirm disconnect` `working…` | header | §T-3 unchanged |
| `● <STATE> · <selfIp> · <selfDnsName>` | identity line | `backendState.toUpperCase()`; dot positive iff Running |
| `tailnet goes down here — …` / `op failed: …` / `op timed out` / `login required — run: tailscale login` | strip 1–2 | §T-3/§T-5 verbatim |
| `control disabled — run: sudo tailscale set --operator=$USER` / `control unavailable — tailscaled not responding` | strip 3 | §T-1 verbatim (the ONLY site) |
| `⚠ <health[i]>` | strip 4 (wrap) | `health[]` order preserved |
| `Search peers` | TextField placeholder | static i18n |
| `EXIT NODES · <E>` | section label | `exitNodes.length` |
| `▸ exit node: <name>` + `×` | banner | §T-4 unchanged (Mullvad via `activeMullvadExit`) |
| `ACTIVE` | active candidate row tag | `peer.Active` |
| `use` / tooltip `use <name> as exit node`; tooltip `stop using exit node` | candidate row / banner | §T-4 unchanged |
| `<ip> · <dns>` | candidate + result line 2 | peer fields |
| `switching…` | transient line 3 | §T-4 unchanged |
| `ONLINE · <N>` | census label | online − exit-capable |
| `<dns> · <ip>` [` · routes: <r>, …`] [` · last seen <t>`] | census tooltip | `subnetRoutes()`, `fmtLastSeen()` |
| `<N> OFFLINE · SHOW` / `<N> OFFLINE · HIDE` | offline toggle | offline count |
| `NO ONLINE PEERS` / `NO PEERS · TAILNET EMPTY` | census empties | counts |
| `MATCHES · <N>` / `NO MATCHING PEERS` | search mode | results length |
| `<ip> · <dns>` [` · last seen <t>`] | result line 2 (offline matches muted) | peer fields |
| `● AS OF hh:mm:ss` / `◐ STALE · hh:mm:ss` | footer left | `statusStampMs` vs 3×`pollSeconds` (tooltip: `POLL EVERY <N> S`) |
| `CONTROL ENABLED · <user>` / `CONTROL DISABLED` / `CONTROL UNAVAILABLE` | footer right | gate state (verdict only — remediation lives in strip 3) |
| `NEEDS LOGIN · RUN: tailscale login` · `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S` · `TAILSCALE BINARY MISSING · INSTALL TAILSCALE` · `STATUS ERROR · RETRYING` | edge row (§V-10) | §R-8 strings re-adopted verbatim |

**Count-sum invariant** (asserted, §V-13): E + census N + offline N ===
`peers.length` === chip total; chip online === E + census N.

## V-8 — Search (the Trayscale port)

Matcher = Model.js `searchPeers(peers, query)` — semantics ported from
trayscale `peersearch` + `searchSidebarLayout` (verified in source):

- Tokens: whitespace-split query; ALL tokens must match (each against
  any field). Fields: DisplayName (weight 4), HostName (3), DNSName
  (2), each `TailscaleIPs` entry (1).
- Token match (case-insensitive): prefix > substring > in-order
  subsequence; no subsequence → token fails → peer excluded.
- Sort: score descending, then HostName ascending.
- Pure JS over already-parsed peers — NO new exec sources (extends
  `filterPeers`, §R-9 flag 4's "search is redundant" judgment is
  REVERSED: at 19 online + 21 offline behind a toggle, find-by-IP/dns
  is the missing operation and search is the reference-blessed answer).

Behavior:

- Live filter per keystroke; query non-empty → EXIT NODES / ONLINE /
  OFFLINE sections are REPLACED by one 1-col result list (`MATCHES · N`
  label). Offline peers are searched regardless of collapse state
  (Trayscale behavior); collapse state is restored when the query
  clears.
- Zero matches with non-blank query → centered muted
  `NO MATCHING PEERS`.
- `Ctrl+F` (popup focused) → focus + select-all. `Esc` → clear text if
  non-empty, else blur. Trailing `✕` clear visible iff text non-empty.
  Popup close → query cleared (fresh open = fresh view).
- Search row hidden when `peers.length === 0` and in the
  down/missing/login/parse edge states (nothing to search).
- Search does NOT interact with the op machine: typing never disarms
  (§T-3 disarm triggers are control CLICKS, verbatim).

## V-9 — Interaction map

| Target | Click / key | Effect | States |
|---|---|---|---|
| Header button | click | §T-3 machine verbatim: Connect single-click; Disconnect arm → `Confirm disconnect` (negative) + dead-zone 500 ms → 4 s window fire; `working…` in flight; auto-disarm at 4 s/close/launch/other-control-click (disarm+perform) | rest / armed / in-flight; disabledTextColor ONLY when disabled=true |
| Banner `×` | click | §T-4 `exit-clear` (works for Mullvad); disabled in flight | rest / disabled |
| Candidate `use` | click | §T-4 `exit-set` (DNSName dot-stripped, IP fallback); no confirm; tooltip teaches | rest / hover / disabled-in-flight; hidden on active row + gate disabled |
| Search field | type / Ctrl+F / Esc / `✕` | §V-8 | empty / active / no-matches |
| Offline toggle row | click | expand/collapse offline grid this session | `SHOW`/`HIDE` copy flips |
| Census cells | — | NON-interactive; tooltip only | online / offline (muted) |
| Footer | — | non-interactive | fresh / stale |
| Outside popup | click / Esc | popup closes (disarms §T-3; clears query) | — |

## V-10 — Edge states (detection by existing signals only — §R-8 map)

| State | Signal | Rendering (standing content preserved) |
|---|---|---|
| Needs login | `status.needsLogin` | strip row `NEEDS LOGIN · RUN: tailscale login` (§R-8 string); header `Connect`; identity line `● NEEDS LOGIN · …`; sections + search hidden; footer stands |
| Backend down | poll exit ≠ 0, stdout empty, stderr w/o "not found" | edge row `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S`; identity + sections + search hidden; footer stands (stamp goes `◐ STALE` naturally); gate keeps last-known; chip crossed |
| Binary missing | exit 127 or stderr `/not found/` | edge row `TAILSCALE BINARY MISSING · INSTALL TAILSCALE`; rest as backend-down |
| Parse error | `!parsed.ok` | edge row `STATUS ERROR · RETRYING`; rest as backend-down |
| 0 peers, running | `peers.length === 0` | edge row `NO PEERS · TAILNET EMPTY`; search hidden; header/identity/footer stand |
| 0 online, offline > 0 | computed | `ONLINE · 0` + centered `NO ONLINE PEERS` + offline toggle row |

Edge rows replace the SECTION STACK only; header, strip, and footer stay
mounted in every state — the popup is never a bare error screen and
never duplicates a string (edge strings appear in exactly one place).

## V-11 — Model & test additions (spec-only; build pass implements)

- `Model.js` fork-additions: `searchPeers(peers, query)` (§V-8) —
  unit tests in `tests/model.test.js`: substring hit; subsequence hit
  (`gdt` → gdtower); multi-token all-must (`spark gx` → both spark
  nodes, `spark zzz` → none); score order (prefix beats subsequence);
  offline inclusion; empty-query passthrough. `parseStatusPlus`,
  `filterOnline`, `subnetRoutes`, `fmtLastSeen` reused as-is.
- No changes to `Control.js`, `tests/control.test.js`,
  `tests/port.test.js` beyond what §V-2 deletes (none) — §T-2 allowlist
  untouched; harness stub still serves `status --json` + prefs; fixture
  set below.
- Fixtures (stub-served): **norm19** (19 online incl. 3 exit-capable,
  `tower` active, 21 offline, health empty) — run twice, gate enabled +
  gate disabled; **norm24** (24 online, 1 exit-capable active, 16
  offline); **norm25** (25 online, 1 exit-capable none active, 15
  offline); **empty**; **login** (BackendState NeedsLogin + AuthURL);
  **down**; **missing** (exit 127); **parse** (garbage stdout).

## V-12 — File layout & implementation constraints

- `contents/ui/`: `PopupShell.qml` (frame, header, identity, strip,
  search row, footer; owns ALL width/height hints), `SearchRow.qml`,
  `ExitNodeSection.qml` (label + banner + candidate ListView),
  `CandidateRow.qml` (atom: `use`, ACTIVE tag, subline, `switching…`),
  `CensusSection.qml` (mode: online|offline; label, empty row, grid,
  offline toggle), `CensusCell.qml`, existing `SectionLabel.qml`.
  Deleted: `tabs/*`, `PeerCell.qml`.
- Tab-era constraints that SURVIVE: `ctx` passing (never `root`),
  Plasmoid context root-file-only, ~150 ms deferred popup-open work,
  `tools/check_qml.py` before every install, one handler per signal per
  file.
- `metadata.json` → `0.4.0`; README Differences + Verified and ROADMAP
  row in the same commit (release-stamp rule).

## V-13 — Acceptance criteria (harness: virtual harness, scale 1 + host DPR)

1. **Fixed frame:** identical WxH across all fixtures, during search,
   offline expand, and op flight; no resize on data tick.
2. **norm19 zero-scroll:** census `contentHeight ≤` viewport, no
   scrollbar pixels, gate-hint row present (worst persistent case), on
   BOTH gate runs.
3. **norm24, norm25 zero-scroll** per §V-5 math.
4. **Scroll valve:** offline expanded in norm19 scrolls; scrollbar lane
   pixel-clear of every `use`/`×`.
5. **Section membership:** no peer id in two sections; exit-capable
   excluded from census; count-sum invariant holds; chip reads
   `19/40` on norm19.
6. **Computed counts:** fixtures with different peer counts render
   different count strings; grep finds no count literals in new QML.
7. **Copy:** every rendered string matches §V-7 (or §T-3/4/5 approved)
   byte-for-byte; ` · ` joiner everywhere; NO string renders twice.
8. **Search:** `tow` → tower (first, prefix-scored) + watertower;
   `zzz` → `NO MATCHING PEERS`; `gdt` → gdtower (subsequence);
   `spark gx` → both sparks; Esc restores sections; Ctrl+F focuses;
   reopen → query cleared; search hidden on empty/login/down/missing/
   parse.
9. **Offline:** collapsed default (`21 OFFLINE · SHOW`, zero cells);
   click reveals 21 muted cells; `HIDE` flips; `showOffline=true` and
   wiped-config default-config pass both verified.
10. **Control layer:** `use` → stub log `set --exit-node=<dns>`;
    `×` → `set --exit-node=`; `use` absent on active row + gate-disabled
    run; in-flight disables all controls + `switching…` transient;
    watchdog re-enables; arm/dead-zone/confirm pixel-asserted;
    `control.test.js` green and unchanged.
11. **Edges:** all six §V-10 states render their one string + standing
    header/strip/footer; no dead rows; no empty section labels.
12. **Chip untouched:** `git diff` on the compactRepresentation block
    empty.
13. **Hit targets:** `use`/`×` ≥ `1.4·gu` with smallSpacing separation
    at both scales.
14. **Theme + type:** no hex literals in new files; no text below
    `smallFont`; dark + light Breeze legible (dots, tags, muted cells).
15. **lastTab gone:** no reader in QML; entry absent from `main.xml`
    (grep); stale appletrc value ignored.

## V-14 — Data flags delta (nothing invented)

Unchanged from §R-9: no direct/relay, no traffic rates, no OS glyphs,
no self OS/Tags, no health severity, no payload timestamp (stamp is UI
state). New/changed: (1) search reverses §R-9 flag 4 (§V-8 rationale);
(2) copy-IP-per-peer (Trayscale peer page has COPY buttons) is deferred
to ROADMAP with Taildrop/Mullvad-picking — clipboard writes from a
non-interactive census would be undiscoverable and are not part of this
review; (3) peer detail beyond tooltip is out of scope — no detail
pages in a popup.
