# plasma-tailfin v0.7 — Popup UX Spec (§V7-1..§V7-13)

Status: DESIGN SPEC, awaiting implementation. Replaces the v0.6 popup
direction **in full**. §T-1..§T-8 (`UX-SPEC-CONTROL.md`, repo root)
carry forward **byte-identical** (5-op closed allowlist, single-click
exit ops, §T-3 arm machine, §T-5 message stack + watchdog, §T-6 chip,
§T-8 scope guard). Model.js and Control.js are **untouched**
(`tests/{control,model,port,search}.test.js` green, unchanged). Panel
chip OUT OF SCOPE; this spec touches the popup only.

v0.6 (single-lane slot grid): **"I really hate that design."** ·
"Did you look at Tailfin and other Linux clients…? Look at the Mac one.
Look at the Windows one. Come up with some ideas." · "There needs to be
some tabs." · "Look at Trayscale. It does a pretty good job of the
interface. But it's missing some parts."

History: v0.3 tabs were rejected for their **content**, not for tabs.
v0.6 removed tabs — rejected. **Tabs return**, with content modeled on
the teardowns in `~/vaults/agentic/fleet/research/tailfin-ux-references-2026-11.md`
§8 ([MAC] macOS client · [WIN] Windows client · [TS] Trayscale master ·
[DMTH] Disk-MTH GNOME ext · [ECO] ecosystem survey · [OMA] omarchy
original). Every structural rule below cites one.

---

## §V7-1 — Diagnosis, and the Trayscale gap plan

v0.6 put three jobs on one scrolling page — *census*, *routing*, and
*device state* — and its dense rows couldn't fit routing + health
without stacking bands. The fix is structural: **split the jobs into
tabs**, as [TS] does with sidebar groups (This machine / Exit Nodes /
Online / Offline) and [MAC]/[WIN] do with menu zones. v0.3 failed
because each tab's *content* was a thin dump; v0.7 maps proven content
into each tab. Trayscale's own gaps (§8) are the feature list:

| [TS] gap (§8 teardown) | v0.7 fill |
|---|---|
| health = literal TODO, never surfaced | header `⚠ n` pill (all tabs) + DEVICE health section §V7-7 |
| traffic raw integers, no rates, no per-peer view | detail TRAFFIC group, cumulative + derived rates §V7-5 |
| exit change = navigate + flip | EXIT tab one-gesture picker §V7-6 + detail `use exit` |
| conn type + OS never rendered | row OS/CONN slots (§V7-4) + detail CONNECTION |
| no compact popup form factor | this spec: 34·gu tabbed popup |

Anti-goals from the rejections: no prose sublines (v0.5 B1), no
two-line slot grid or everything-on-one-page (v0.6), no name-only
census (v0.4), no action buttons down the list (v0.6 B2), no modals
(§T-3), no OS-brand glyphs (Breeze ships none — text only), no
color-only state (WCAG 1.4.1).

## §V7-2 — Tab set, order, rationale **[NEW]**

**`PEERS · EXIT NODES · DEVICE`** — three tabs, text-only labels.

| Trayscale sidebar group [TS] | v0.7 destination |
|---|---|
| This machine (self page) | **DEVICE** tab (deep facts; glance facts pinned in header) |
| Exit Nodes (section) | **EXIT NODES** tab |
| Online + Offline (sections; offline hidden by a setting) | **PEERS** tab — online section + collapsed offline section ([OMA] count-row pattern, owner-approved) |

Mac/Win cross-check [MAC][WIN]: "This device: host (100.x)" info line →
pinned header (self is NEVER a peer row); "Exit node ›" submenu → EXIT
NODES tab; "Network devices ›" → PEERS tab.

**Order defense.** PEERS first — default tab; the primary task in
every owner conversation is the tailnet census, and [MAC]'s 2025
windowed app exists because a menu "can't include a search bar" — the
device list is the core surface. EXIT NODES second — routing is a
daily action with its own vocabulary (radio picker, None, degraded
state); folding it into the peer list produced v0.4's three-ACTIVE
collision and v0.6's B2 button scatter. DEVICE last — read-mostly
config/health, farthest from the default tab, matching [WIN]'s
terminal-action-last grammar. Three tabs, not four: offline peers are
the same object type as online — a destination split means two places
to look for "where did host03 go" (Hick's law: cut the choice).

**Tab bar anatomy.** Hand-rolled row of 3 checkable `AbstractButton`
cells, `autoExclusive`, each `width: contentWidth/3`, height `2.0·gu`
(36px). Label T4; `textColor @ 0.62` inactive / `textColor` active —
never `disabledTextColor` (enabled controls never look disabled, §T
invariant). Active cell: `2px` underline at the cell's bottom edge,
full cell width, `Kirigami.Theme.highlightColor`. Hairline under the
bar. Hover = highlight `@0.06`; pressed `@0.12`; focus = Breeze ring.
Full cell is the hit target (~204×36px, Fitts). Keyboard: `←`/`→`
walks, `Ctrl+1..3` jumps. No icons, no counts on tabs (header carries
state; no icon-name risk). Tab state resets every popup open
(fresh-open law, §V-8): **PEERS when `running`, DEVICE when not** —
zero-friction first action, the Connect button lands visible [MAC].
Tab switches never change the frame.

## §V7-3 — Frame and global zones (all tabs) **[KEEP §V-5/§W-3]**

Width `34·gu` fixed (612px @ gu=18); height `min(38·gu, 0.9·available)`
(684px typical). The frame NEVER resizes on data, search, tab switch,
detail push, or op flight — scroll is the only overflow valve. Sizing
lives in `PopupShell.qml` only; one visible scroll region per tab.
Spacing: `smallSpacing` (S=4), `largeSpacing` (G=9), inner margin
`0.35·gu` (M=6); hairline = `Kirigami.Separator` 1px.

```
● gdtower                                 [🔍][Disconnect]    HEADER 2.2·gu
  RUNNING · 100.71.87.72 · via tower            [⚠ 2]
(§T-5 strip items 1–3 only, conditional, 0.9·gu/row)           STRIP
[ PEERS         EXIT NODES         DEVICE ]▬2px underline▬    TABBAR 2.0·gu
┌ tab content region (fills; one scroll region) ┐
● AS OF 23:44:39 · 5s ago     CONTROL ENABLED · gdeyoung     FOOTER 1.3·gu
```

- **HEADER [KEEP §W-7, AMEND line 2]:** line 1 = state dot (6px,
  positive iff Running) + `selfName` (T1 bold) + right-aligned `[search]`
  checkable ToolButton (`edit-find`, tooltip `Search peers (Ctrl+F)`,
  hidden when nothing to search) + §T-3 power button (`Disconnect` /
  `Confirm disconnect` negative-while-armed / `Connect` / `working…`
  disabled; 1.4·gu) — header-right is §T-3's own site and [TS]'s
  always-visible StatusSwitch; Disconnect is reversible and
  arm-machined, so [WIN]'s terminal-last grammar doesn't apply (no
  terminal op exists in the §T-2 allowlist). Line 2 = T3 muted, `tnum`
  on the IP: `<BACKENDSTATE CAPS> · <selfIp> · <routing>` with
  `<routing>` = `via <activeExitName>` | `direct` | `⚠ exit not
  routing` (neutral) — glance #2 popup-wide [MAC]; self DNS name moves
  to DEVICE + header tooltip (it elided to nothing at 612px anyway).
- **HEALTH PILL [NEW]:** iff `health.length > 0`, a flat chip at line
  2's right: `⚠ <n>` (`neutralTextColor` T3 bold, `0.9·gu`, hairline
  border). Tooltip `<n> health warnings — open the Device tab`; click →
  DEVICE. A count + pointer, not the text — warning text renders
  exactly once, on DEVICE (dedup law).
- **STRIP [AMEND §W-8]:** §T-5 items 1–3 only (armed warning, op error,
  gate hint), strings + order byte-identical, single-site elided rows.
  Item 4 (health) MOVES to DEVICE — health is steady-state, not op
  feedback, and v0.5 M6 measured it costing lane height on every view.
- **FOOTER [KEEP §V6, AMEND]:** `● AS OF hh:mm:ss · <rel>` left, gate
  verdict right, hairline above, 24px. v0.6's footer `Disconnect` is
  REMOVED — power returns to the header (§T-3's site; v0.6 B2's
  complaint was the adjacent-control cluster, which no longer exists).

Type scale [KEEP §W-4]: T1 `0.8·gu` bold (selfName, detail title) ·
T2 `0.72·gu` DemiBold (names, picker labels) · T3 `smallFont`
(everything informational) · T4 smallFont bold caps ls 0.4 (labels).
Floor: nothing below `smallFont`. **Font-bind law:** member binds only
(`font.pixelSize/weight/family/features`); whole-object `font:` binds
banned. Colors [KEEP §V6-13]: `textColor` primary · muted = `textColor
@ 0.62` (never disabledTextColor for information) · `positiveTextColor`
reserved for online-ness ONLY (dots — B4 lesson) · routing state =
`highlightColor` family + always a word · warnings `neutralTextColor` ·
failures/armed `negativeTextColor`. Offline rows: whole-row `opacity
0.62`, dot `disabledTextColor` [OMA]. Online-flip flash 400ms highlight
@0.25, counters never flash [KEEP §W-15.8]. `tnum` on every ticking
numeric. Zero hex literals; dark+light Breeze by construction.

## §V7-4 — PEERS tab: census + search surface **[NEW]**

Content region top→bottom: `[search row — revealed only]` → `[section
header row, pinned]` → `[lane, scrolls]`.

**Search row [AMEND §W-9].** Revealed by the header `[🔍]` toggle or
`Ctrl+F` — which also switches to PEERS (search means "find a peer") —
auto-focus + select-all. Standard `PC3.TextField`, `1.9·gu` (34px),
full content width, placeholder `Search peers`, trailing `✕`
(`edit-clear-all`, tooltip `Clear search`) inside the field's right
edge, visible iff text non-empty. `Esc` clears non-empty text, else
collapses + blurs; popup close clears + collapses. Engine =
`Model.searchPeers` UNTOUCHED (§V-8: multi-token AND,
prefix>substring>subsequence, weights DisplayName 4 / HostName 3 /
DNSName 2 / IPs 1). Revealed-search is the [TS] precedent; the v0.4
defect was a dominant always-on field — a revealed 34px row under two
chrome bars is not that.

**Section header row [AMEND v0.6 lane labels]:** height `1.4·gu` (25px), pinned at
the lane top. Left, T4 caps + tnum: `ONLINE · <n>` normally; while
querying `MATCHES · <n> OF <total>` (denominator = `peers.length` — the
v0.5 B3 auditability fix). Right, while querying only: one `~` chip per
token that matched **only as a subsequence** (T3 muted, up to 3, then
`+k`) — fuzzy results explain themselves without touching the engine.

**Lane.** `ONLINE` label + peer rows → offline toggle row → offline
rows. While querying: results render as ordinary rows (offline matches
dimmed), the offline toggle hides [KEEP §W-9]. Empty search → centered
muted `NO MATCHING PEERS` (PlaceholderMessage). The fold shows a
partially-clipped row (continuation cue, §V6 M2 fix carried).

**PeerRow — single line, 33px [AMEND §V6-2].** Root `Item`,
`implicitHeight: gridUnit * 1.85` = 33px, fixed — no content-driven
height. One line of fixed slots (x-axes identical every row, online and
offline — §V6-1's addressable columns kept, the second line deleted;
density moves to the detail page [TS]):

| Slot | x-start | Width | Align | Content |
|---|---|---|---|---|
| DOT | 0 | 0.9·gu | l | 6px dot (0.35·gu), positive/disabled |
| NAME | 0.9·gu | → 12.6·gu | l, elide r | DisplayName, T2 DemiBold |
| ADDRESS | 12.6·gu | 7.2·gu | **r**, tnum | `TailscaleIPs[0]` |
| OS | 19.8·gu | 2.6·gu | r | `Linux Windows macOS iOS Android` (brand case; empty → slot reserved) |
| CONN | 22.4·gu | 4.4·gu | r | `direct` \| `relay · <code>` \| `offline` \| empty (never connected) |
| ROLE | 26.8·gu | 5.4·gu | r | exactly ONE: `◌ network-vpn EXIT NODE` (bold T3 `textColor`, icon `highlightColor` 0.7·gu) \| `exit` muted \| `<cidr> +N` muted (elide l) |

- Conn derivation [KEEP §V6-3]: `peerIsDirect` → `direct`; else
  `peerRelay` → `relay · dfw` (tooltip appends `relayed via DERP
  <region>`). Offline rows render `offline` in CONN. ROLE priority:
  active exit (`peer.ExitNode`) > exit-capable (`ExitNodeOption`) >
  subnet routes (`subnetRoutes(peer)`).
- **Rows are clickable [AMEND §W-5]:** hover = highlight `@0.06` fill,
  pointing cursor, pressed `@0.12`, focus ring; click / Enter opens the
  detail page. No per-row action buttons — exit switching lives on the
  EXIT tab + detail page; this deletes v0.6's `use exit`/`stop` scatter
  (B2) at the source [TS rows carry no controls].
- Offline rows: identical slots, whole-row `opacity 0.62`. Last-seen is
  NOT on the row [TS keeps it off rows too]; it renders on the detail
  page + row tooltip. Tooltip (hover + `Accessible.name`) [KEEP §W-5]:
  `<fqdn> · <v4> · <v6>` + ` · routes: …` + ` · last seen <absolute>`
  when offline.
- Offline block [KEEP §W-10 verbatim]: full-width standard Button
  `<N> OFFLINE · SHOW` ⇄ `HIDE` (1.4·gu), dimmed rows beneath;
  `showOffline` config seeds it. **All-offline exception:** when
  `onlineCount === 0` the block auto-expands and the lane top gains
  `0 OF <total> ONLINE · SHOWING ALL OFFLINE` (T4 + tnum) — the v0.5 M5
  fix; a dead tailnet must not render as a 470px void.

## §V7-5 — Peer detail: page-stack-with-back **[NEW]**

**Decision: page-stack, not inline expansion.** A `StackView` inside the
PEERS content region (header, tab bar, footer stay visible — you can hop
tabs mid-inspection). Justification: [TS] uses one detail page per peer
and [MAC]'s windowed app a detail pane (Jakob's convention); inline
expansion makes the row variable-height and shoves everything below it
past the fold (the v0.5 pitch-jitter defect class); ~12 values + rates
need 612px of calm width, not a squeezed accordion. Back = one gesture.

Anatomy (top→bottom in the content region):

1. **Back row `2.0·gu`:** flat ToolButton, text `← PEERS` (T4), tooltip
   `Back to peers`, hit ≥1.4·gu; `Esc` and mouse-back also pop.
   Push/pop ≤300ms, transform/opacity only.
2. **Title block:** `DisplayName` T1 bold; T3 muted status line `<OS> ·
   <conn> · online · active|idle` or `<OS> · <conn> · offline · last
   seen <rel>` (the §V6-3 field grammar, relocated here).
3. Hairline, then labeled groups (T4 label; rows `1.85·gu`, muted label
   left, value right, `tnum` on numbers, selectable text):
   - **IDENTITY:** `dns name` · `ipv4` · `ipv6`
     (`peer.TailscaleIPv6` — Model already parses it).
   - **CONNECTION:** `os` · `path direct | relay · <code>` · `state
     online · active | idle | offline` · `last seen <rel>` (offline
     only [TS]).
   - **TRAFFIC [NEW — [TS] gap #2]:** `received ↓ <fmtBytes(Rx)> ·
     <rate>/s`, `sent ↑ <fmtBytes(Tx)> · <rate>/s`. Rates derive from
     consecutive poll ticks in `main.qml` (NOT Model.js): keep
     `prevSample = {peerId: {rx, tx, ms}}`, update each `applyStatus`;
     rate = Δbytes/Δs via `fmtBytes(rate)+"/s"`. `—` until a second
     sample exists (never invent), `idle` at ≤ 0.
   - **SUBNET ROUTES (conditional):** one row per `subnetRoutes(peer)`
     CIDR, `tnum`, no elide; `0.0.0.0/0` on exit peers suppressed
     (tautology, §V-4 #1).
   - **EXIT NODE (conditional, `ExitNodeOption` ∧ isExitCandidate):**
     `this peer can route your traffic` (T3 muted) + button `use exit`
     — §V6-5/§T-4 verbatim: standard PC3.Button, 1.4·gu, tooltip `use
     <peer name> as exit node`, single click, no confirm, disabled
     while any op flies, hidden gate-off. If this peer IS the active
     exit: `current exit node` + button `stop`, tooltip `stop using
     exit node`, fires `exit-clear`. In-flight: the group shows
     `switching…` (T3 disabled color).
4. Clipboard copy stays **deferred** (§V-14 ROADMAP; no clipboard API in
   the plasmoid) — values render fully and are text-selectable.

## §V7-6 — EXIT NODES tab: picker + routing-health pill **[NEW]**

Fills [TS] gap #3 ("changing exit node = navigate+flip"). Top→bottom:

1. **State block `2.2·gu` (pinned):** line 1 = `network-vpn` icon 0.7·gu
   (`highlightColor` when routing, muted otherwise) + **§T-4 banner text
   byte-identical**: `▸ exit node: <name>` (T3 muted prefix, T2 name;
   Mullvad via `activeMullvadExit`) or `no exit node · direct` [§W-6
   strings move here; v0.6's ExitStrip is deleted]. Line 2 = the
   **routing-health pill** [DMTH]: chip `0.9·gu`, hairline border token,
   T3 bold — routing+online → `● routing` (highlight border+dot) · none
   → `● direct` (muted) · **warn → `⚠ not routing`
   (`neutralTextColor`)** + T3 muted cause line beneath: `<name> is
   offline` or `<ip> configured but no peer is routing — pick another`.
   Warn conditions (derivable, no new data): (a) a peer with
   `ExitNode === true` is `Online === false`; (b) `parsePrefs(gatePrefs)
   .exitNodeIp` non-empty while no peer has `ExitNode === true`. Never
   color-only: the word always renders.
2. Hairline. **Picker list** (scrolls if long) — [WIN] radio grammar,
   rows reuse the peer-row slot geometry (same x-axes, §V7-4):
   - Row 0 **`None · direct`** — radio circle 0.5·gu at the DOT column,
     label T2, CONN slot `direct`. Selected iff no active exit. Click =
     `exit-clear`. Selected rendering: filled radio (`highlightColor`),
     name bold, whole-row tint highlight `@0.10` [KEEP §V6-6 grammar].
   - Candidate rows: `status.exitNodes` filtered by
     `Control.isExitCandidate(peer, rawPeers[id])` (§T-4's raw
     `0.0.0.0/0` test — the pinned definition), alphabetical. Radio +
     name T2 + ADDRESS/OS/CONN slots as peer rows. Single click = §T-4
     `exit-set` with `Control.exitTarget(peer)` — **one gesture, no
     confirm** (pinned). Row tooltip: `use <peer name> as exit node`.
     Offline peers never appear (candidates are online-only, §T-4).
   - In-flight (§T-4 verbatim): all picker rows + None disabled; target
     row grows to `2.72·gu` with third line `switching…`; cleared on
     completion, failure, or watchdog timeout.
   - Gate-off (§T-1): rows render read-only — radios still show the
     selection, no hover/pointer/click; the §T-1 hint renders in the
     strip (single site).
3. **Empty state:** no candidates → below None row, centered muted
   `NO EXIT-CAPABLE PEERS ONLINE` + teaching line `a peer must
   advertise 0.0.0.0/0 before it can route your traffic` (T3).
4. No `Recommended`/auto entry: [MAC]'s Recommended auto-tracks latency;
   we have **no latency data** and `exit-node suggest` is outside the
   §T-2 allowlist — absent by honest scope, not omission.

## §V7-7 — DEVICE tab: identity, options, health **[NEW]**

Deep self facts [TS self page + MAC/Win "This device" zone]. Glance
facts stay pinned in the header; nothing here duplicates them (single
render site). Top→bottom, groups as §V7-5 (T4 label + rows 1.85·gu):

1. **THIS DEVICE:** `dns name <selfDnsName>` · `ipv6 <addr>` (plumb raw
   `Self.TailscaleIPs` in `main.qml`; render only if present). Name/IP/state live in the header already.
2. **OPTIONS · READ-ONLY:** four fact rows parsed by
   `Model.parsePrefs(gatePrefs)` — the §T-1 probe already runs
   `tailscale debug prefs` once per plasmoid load and `main.qml`
   retains the raw stdout; parsing it adds **no new exec source**:
   `route all traffic on|off` (`RouteAll`) · `lan access
   allowed|blocked` (`ExitNodeAllowLANAccess`) · `shields up on|off`
   (`ShieldsUp`) · `override dns on|off` (`CorpDNS`). Value right T3;
   tooltip per row teaches the meaning + `read-only — change it with
   the tailscale CLI`. [TS] has live switches here; ours are facts —
   the §T-2 allowlist is closed and stays closed (§T-8). **`main.qml`
   AMEND:** re-run the allowlisted `probe` op in `endControlOp()`
   (alongside `pollNow()`) so `exitNodeIp` + option facts refresh
   exactly when they change.
3. **HEALTH [NEW — [TS] gap #1 ("health = literal TODO in poller.go")]:**
   `⚠ <text>` rows, `neutralTextColor`, order preserved, wrap ≤2 then
   elide + tooltip full text; scope label `THIS DEVICE` (status-health
   is daemon-level — never attribute a warning to a peer; we cannot,
   honestly). Empty → one muted row `no health warnings` (teaching
   empty state).
4. Nothing destructive lives here: the master control is the §T-3
   header button. [WIN] puts Exit last because it is terminal;
   Disconnect is reversible + arm-machined, and [TS]/[MAC] keep the
   master control adjacent to status — exemplar + §T-3 text win.

## §V7-8 — State matrix

| State | Signal | PEERS | EXIT NODES | DEVICE | Chrome |
|---|---|---|---|---|---|
| All offline | `onlineCount===0 && peers>0` | offline block auto-expands + `0 OF <n> ONLINE · SHOWING ALL OFFLINE` | normal | normal | header dot stays positive (self IS connected — honest) |
| Zero peers | `peers.length===0` (running) | centered `NO PEERS · TAILNET EMPTY`; search hidden | None row + empty-teach string | normal | — |
| Gate off | §T-1 | rows fine, no detail `use exit`/`stop` | picker read-only | options render | zero enabled buttons; §T-1 hint single site in strip; footer verdict |
| Health warnings | `health.length>0` | normal | normal | full ⚠ rows | header `⚠ n` pill (all tabs), click→DEVICE |
| Empty search | query ≠ ∅, 0 results | `MATCHES · 0 OF <n>` + `NO MATCHING PEERS` | — | — | ✕ visible; Esc clears |
| Needs login / backend down / binary missing / parse error | §W-12 signals | tab bar + search **hidden**; single centered §W-12 edge row + icon in the content region | — | — | header (`Connect`, identity per §W-12), strip, footer stand; `◐ STALE` where applicable |
| Op in flight | `ctlBusy` | detail buttons disabled | all picker rows disabled + `switching…` | — | power `working…`; §T-5 one-op rule |
| Exit degraded | §V7-6 warn conditions | active peer's ROLE still `EXIT NODE` (state is fact) | warn pill + cause | normal | header line-2 `⚠ exit not routing` |

Edge strings are §W-12 verbatim (`NEEDS LOGIN · RUN: tailscale login`,
`TAILSCALED NOT RESPONDING · RETRY EVERY <N> S`, `TAILSCALE BINARY
MISSING · INSTALL TAILSCALE`, `STATUS ERROR · RETRYING`); on open while
`!running` the default tab is DEVICE (§V7-2).

## §V7-9 — Interaction map (new elements; all others §W-11 carries)

| Element | Rest | Hover | Active/armed | Busy | Disabled | Edge |
|---|---|---|---|---|---|---|
| Tab cell | T4 @0.62 | @0.06 fill | active: textColor + 2px underline; focus ring | — | never | — |
| PeerRow | dot+slots | @0.06 fill, pointer | pressed @0.12; focus ring; Enter=detail | — | never | offline 0.62; flash 400ms on flip |
| Picker row | radio ○ | @0.06 fill | ● filled + tint @0.10 + bold | disabled; target `switching…` | gate-off: read-only, no pointer | warn pill conditions |
| Back `← PEERS` | T4 | @0.06 fill | pressed; Esc/mouse-back | — | never | — |
| Health pill `⚠ n` | neutral chip | @0.06 fill | click → DEVICE tab | — | never | hidden iff n=0 |
| Options row | label+value | tooltip only | — | — | never (facts) | `unavailable` when prefs unparseable |

Every icon-only control carries a tooltip doubling as
`Accessible.name`; hit targets ≥1.4·gu, separated from neighboring text
by ≥ smallSpacing (§T-4).

## §V7-10 — Copy catalog (byte-exact; counts always computed)

Carried verbatim (single render site each): the §T-3 set (`Disconnect`,
`Confirm disconnect`, `Connect`, `working…`, `tailnet goes down here —
remote access via ts.net drops until reconnect`) · §T-5 set (`op
failed: …`, `op timed out`, `login required — run: tailscale login`) ·
§T-1 hints (`control disabled — run: sudo tailscale set
--operator=$USER`, `control unavailable — tailscaled not responding`) ·
§T-4 (`▸ exit node: <name>`, `use <peer name> as exit node`, `stop
using exit node`, `switching…`) · `no exit node · direct` · `Search
peers` · `ONLINE · <n>` · `<N> OFFLINE · SHOW/HIDE` · `NO PEERS ·
TAILNET EMPTY` · `NO MATCHING PEERS` · §W-12 edge strings · footer
(`● AS OF hh:mm:ss · <rel>` / `◐ STALE …`, `CONTROL ENABLED · <user>` /
`CONTROL DISABLED` / `CONTROL UNAVAILABLE`). New
strings: tab labels `PEERS` `EXIT NODES` `DEVICE` · `MATCHES · <n> OF
<m>` · `~` fuzzy chip · `← PEERS` / `Back to peers` · `direct` · `via
<n>` · `⚠ exit not routing` · `● routing` · `● direct` · `⚠ not
routing` · `<name> is offline` · `<ip> configured but no peer is
routing — pick another` · `None · direct` · `NO EXIT-CAPABLE PEERS
ONLINE` · `a peer must advertise 0.0.0.0/0 before it can route your
traffic` · group labels `IDENTITY` `CONNECTION` `TRAFFIC` `SUBNET
ROUTES` `EXIT NODE` `THIS DEVICE` `OPTIONS · READ-ONLY` `HEALTH` ·
`this peer can route your traffic` · `current exit node` · `route all
traffic` `lan access` `shields up` `override dns` + `on|off` /
`allowed|blocked` · `read-only — change it with the tailscale CLI` ·
`no health warnings` · `0 OF <n> ONLINE · SHOWING ALL OFFLINE` · CONN
tokens `relay · <code>` / `offline` · rates `idle` / `—` · `received ↓`
/ `sent ↑` · row labels `dns name` `ipv4` `ipv6` `os` `path` `state`
`last seen` · `⚠ <n>` + `<n> health warnings — open the Device tab`.
Grammar [KEEP §R-7]: STATUS words CAPS; joiner ` · `; labels
sentence-case; no em-dash placeholders. `NO ONLINE PEERS` is superseded
by the §V7-4 all-offline treatment.

## §V7-11 — Ledger vs v0.6 ([KEEP]/[AMEND]/[NEW])

- **[KEEP]** §T-1..§T-8 byte-identical · frame 34·gu × min(38·gu,
  0.9·av), never resizes · chip · footer grammar + relative age ·
  §W-4 scale + color roles + tnum + font-bind law · offline dim 0.62 +
  count-row collapse · search engine + Esc/✕ + fresh-open law · `relay
  · <code>` wording, brand-case OS, relative last-seen · row tooltip
  field set · 400ms flip flash · §W-12 edges · §T-4 in-flight
  `switching…` + watchdog · active-exit role grammar · count-sum
  invariant (rows + offline = peers.length = chip total).
- **[AMEND]** rows: two-line slot grid → single-line slots (density →
  detail page) · rows non-interactive → clickable (detail) · health:
  strip item 4 → header pill + DEVICE section · ExitStrip band → EXIT
  tab state block (same §T-4 strings) · `use exit`/`stop`: on-row → EXIT
  picker + detail page only · header line 2: `STATE · ip · dns` →
  `STATE · ip · routing` · footer Disconnect → header §T-3 button ·
  search label → `MATCHES · <n> OF <m>` + `~` chips · all-offline void →
  auto-expand + aggregate line.
- **[NEW]** tab bar + 3 tabs · peer detail page (StackView, back, rates)
  · routing-health pill + warn conditions · exit picker (None-first
  radio list) · DEVICE tab (identity, read-only options, health) ·
  header health pill · probe re-run after ops · prev-sample rate map ·
  Ctrl+1..3 / ← → keys.

## §V7-12 — Files and implementation constraints

```
contents/ui/
  PopupShell.qml     — rewritten: frame + header + strip + tab bar + footer
  PeersTab.qml       — NEW (search row, section header, lane, offline block)
  PeerRow.qml        — AMEND (single-line slot row, clickable)
  PeerDetailPage.qml — NEW (back + groups + rates + exit action)
  ExitTab.qml        — NEW (state block + pill + picker)
  DeviceTab.qml      — NEW (identity + options + health)
  SearchRow.qml      — AMEND (revealed-in-PEERS contract)
  SectionLabel.qml   — KEEP ·  ExitStrip.qml — DELETE
  main.qml           — AMEND plumbing ONLY: selectedTab + detail depth +
                       prevSample map (rates) + parsePrefs(gatePrefs) + probe
                       re-run in endControlOp + raw Self IPv6; chip untouched (§T-6)
```

Model.js / Control.js byte-identical; `tests/*` green unchanged; no new
config keys (`interval`, `showOffline` only); no new exec sources (probe
re-use is allowlisted); no whole-object font binds; zero hex in new
files; `tools/check_qml.py` before every install; timers run only while
expanded; ~150ms deferred open work (§R-10); `ctx` passing (never
`root`); one handler per signal per file; `metadata.json` `0.7.0` +
README Differences/Verified + ROADMAP in the same commit.

## §V7-13 — Acceptance checklist (harness: virtual + host DPR, scale 1)

1. Frame 612×684 (±1) across all fixtures; never resizes on tab switch, search reveal, detail push, op flight, or data tick.
2. Tab bar: 3 equal cells (centers 1/6, 1/2, 5/6 of content width); active
   underline 2px `highlightColor` full cell width; bar 36px; `Ctrl+1..3` +
   `←`/`→` switch; focus ring visible.
3. Open with `!running` lands on DEVICE; open while running on PEERS.
4. Header power states pixel-assert §T-3 (`Disconnect` → `Confirm
   disconnect` negative → `working…` disabled; `Connect` when down);
   sub-500ms re-click stays armed (no `down` in stub log); 4s
   auto-disarm; other-control-click disarms + performs.
5. Strip renders §T-5 items 1–3 only (grep: no health row); strings byte-identical, single site each.
6. Rows: 33px pitch ±1; one text baseline band per row (no second
   line); DOT x-axis identical across rows and header dot.
7. ADDRESS right-edges align ±1 across rows; ROLE right edge = content
   right edge ±1; OS/CONN start-x fixed across rows.
8. Offline rows opacity 0.62, CONN reads `offline`, geometry unchanged.
9. Row click / Enter opens detail; hover fill @0.06; Esc and `← PEERS`
   pop; push/pop ≤300ms, transform+opacity only.
10. Detail TRAFFIC: `—` on first tick, numeric after second, `idle` at
    zero; totals byte-match `fmtBytes(RxBytes/TxBytes)`.
11. `use exit` iff `ExitNodeOption` ∧ `isExitCandidate` ∧ ¬`ExitNode`;
    hidden gate-off; tooltip `use <peer name> as exit node`.
12. EXIT tab: `None · direct` is row 0; candidates alphabetical; one
    click emits `set --exit-node=<dns>` / `--exit-node=` (stub log);
    selected row tint @0.10 + filled radio.
13. In-flight: picker + detail controls disabled; target `switching…`;
    watchdog timeout surfaces `op timed out`, controls re-enable.
14. Pill truth table: active+online → `● routing`; none → `● direct`;
    active-peer-offline OR prefs-exit-without-flag → `⚠ not routing` +
    cause. Word always present.
15. DEVICE options match stub `debug prefs` (4 rows); no clickable
    chrome; `unavailable` when unparseable.
16. Health rows = `health[]` count + order, wrap ≤2 + tooltip; empty →
    `no health warnings`; `⚠ n` pill iff n>0, n = row count; click →
    DEVICE.
17. Green census: `positiveTextColor` pixels only in the dot class.
18. Contrast (PIL glyph peak, dark + light): T2 name, T3 muted, pill
    text all ≥ 4.5:1.
19. `tnum` on ADDRESS, rates, counts, footer clock; grep: zero
    whole-object `font:` binds, zero hex, nothing < smallFont.
20. Search: `tow` ranks tower above watertower; `MATCHES · 2 OF 40`; `~`
    chip for a subsequence-only token; offline toggle hidden while
    querying; `zzz` → `NO MATCHING PEERS`; Esc clears-then-collapses;
    reopen = cleared + PEERS + collapsed.
21. All-offline: block auto-expanded + `0 OF 21 ONLINE · SHOWING ALL OFFLINE`; zero peers: `NO PEERS · TAILNET EMPTY` + search hidden; gate-off: zero enabled buttons popup-wide.
22. Edge fixtures: tab bar hidden; one §W-12 string + icon centered; header/strip/footer standing; `◐ STALE` on down/missing/parse.
23. `git diff` on the compactRepresentation block empty; all four test files green, unchanged.
