# plasma-tailfin v0.5 — Popup UX Spec (§W-1..§W-19)

Status: DESIGN SPEC, awaiting implementation. Supersedes §V-3..§V-14
(popup structure) of `UX-SPEC-CONTROL.md`; §T-1..§T-8 (operator gate, closed
argv allowlist, mandatory disconnect confirm, inline two-step confirms, op
watchdog, chip invariants, scope guard) CARRY FORWARD unchanged — every
§T-3/§T-4/§T-5 control string stays byte-identical. The compact chip stays
byte-identical (§T-6). Kirigami primitives only; no modals, ever.

Conventions follow UX-SPEC-CONTROL.md: every interactive element has defined
states; every state has a source of truth; every count is computed, never
literal. All px below are at gridUnit 18 (100% scale); gu expressions are
authoritative and scale linearly (125% column shown where it matters).

---

## Preamble — what v0.4 did wrong, and what this fixes

User verdicts (verbatim history — hard evidence):

> v0.3 (tabs): "No tabs, just a big long fucking list. It scrolls."

> v0.4 (single section stack): "Your design for the Tailfin client that you
> built is not great. It's barely, barely, barely usable... the tab — your
> content, the way you structure on the tabs are trash. I want the most
> highly usable, best user experience, a lot of information in an easy to
> understand, simplified interface."

> Standing guidance: "LOOK AT WHAT WE BUILT FOR TAILFIN AND OMARCHY. THAT UX
> WAS OKAY. YOU CAN LOOK AT TRAYSCALE."

Independent review + pixel audit of the v0.4 screenshots (612px popup,
norm19 fixture) found, with measurements:

| # | v0.4 defect (measured) | What v0.5 does |
|---|---|---|
| 1 | **Inverted hierarchy.** The 596×32px search field (97% of popup width, near-black fill) is the largest high-contrast object; section labels are the loudest text; the actual tailnet/exit state is weak gray ~11px | Search is hidden behind a header tool button (Trayscale/plasma-nm pattern). The glance facts — state verdict, exit routing, health — live in pinned, state-colored bands at the top |
| 2 | **Exit-node section collides and lies.** Two-line entries squeezed into irregular 20/39px cadence → text collisions at y≈164 and y≈224; `ACTIVE` (orange, bold) rendered on **three** rows because it means "has recent session traffic" (`peer.Active`), not "is the active exit node" — three "active" rows contradict the one-selection model | Exit candidates dissolve into ONE unified peer list. The `ACTIVE` tag is deleted entirely; traffic liveliness moves into the subline (↓/↑ counters). The one active exit node is marked `ACTIVE EXIT` in positive color + named in the routing band |
| 3 | **~121px dead space (19% of the popup)** above the footer while the useful top half is over-compressed; census grid leaves ~244px of the right half unused | The list lane always runs edge-to-edge to the pinned footer; rows are full-width (586px of text width), so every row carries its information instead of dumping it |
| 4 | **Information-free census.** The online section is a dot+name grid at 13px uniform type carrying zero census data — "a lot of information" is nowhere | The approved Omarchy money-row returns: OS · IP · direct/via-relay · ↓rx ↑tx (or last seen) in every row, per the ranked reference patterns (digest §5.1) |
| 5 | **Weak affordances.** `use` ≈ 22×13px of bare gray lowercase text; bare-text `SHOW`; unexplained × sitting ~550px from its content | `use` and the offline toggle become standard (non-flat) buttons with full Breeze hover/press/focus/disabled chrome; `×` becomes an iconic window-close button ≥24px with tooltip; everything icon-only carries a tooltip |
| 6 | **No type scale.** Everything renders at ~13px; hierarchy is faked with bold/orange/caps; 11px secondary text fails contrast | One unified 4-token scale (§W-4); nothing below `smallFont`; real information text never uses `disabledTextColor` |
| 7 | **Ambiguous selection.** `exit node: host03` row with an isolated ×, no selected-state treatment, three orange ACTIVEs competing | The routing band is a fixed-height, hairline-bounded band that answers "am I routing through what" in BOTH modes (active AND none-direct) — never absent, never ambiguous |

The user's own words supply the architecture: **one big long list that
scrolls** — not v0.3's tabs, not v0.4's section stack.

---

## W-1 — Design thesis and the glance contract

One glance at the pinned chrome must answer, in order:

1. **Is my tailnet up and healthy?** → header state block (dot + verdict +
   identity) + §T-5 message strip (armed / op error / gate hint / health ⚠).
2. **Am I routing through an exit node, and which?** → routing band (§W-6),
   present in both modes.
3. **Who's online right now, and anything wrong?** → the list lane (§W-5),
   headed by a computed count, with offline collapsed behind a count row.

Everything below the pinned chrome is **one scrollable peer list** — the
v0.3 verdict's own architecture — with rich hierarchical rows (Omarchy's
approved PeerRow, information per the Tailscale admin console's field set,
exit switching per Trayscale's inline row actions). No tabs, no sections that
pull peers out of the list, no census grid, no page-like modes.

Sources: Trayscale (header master switch, search-as-revealed-bar, inline
exit switch semantics, NeedsAttention badge on the active exit), omarchy-tailfin
(the approved money row, offline dimmed-not-hidden, collapsed count row,
click-teaching tooltips), Tailscale admin console (Name / Address / OS /
Connection direct-vs-DERP / Last seen / rx-tx field set). Ranked borrow
patterns are digest §5 items 1–8; widget patterns P1–P13 + the dashboard
live-data rules are the vocabulary (row pitch, tnum, PlaceholderMessage,
refresh/provenance rules).

---

## W-2 — Structure tree

```
PopupShell (fixed 34·gu wide × min(38·gu, 0.9·available) tall)
├─ Pinned chrome (never scrolls)
│  ├─ HEADER (40px) — self block + [search] [power] buttons        §W-7
│  ├─ MESSAGE STRIP (§T-5 items 1–4, in order, conditional rows)    §W-8
│  ├─ ROUTING BAND (38px, both modes, when running)                 §W-6
│  ├─ SEARCH ROW (34px, revealed only)                              §W-9
│  └─ FOOTER (24px) — provenance + gate verdict                     §W-13
└─ LIST LANE — the ONLY scroll region                               §W-5
   ├─ ONLINE · <N> label (computed)
   ├─ PeerRow × N  (online, alphabetical, row-major)
   │   ├─ exit candidates: trailing [use] + `exit` badge            §W-5
   │   └─ active exit node: `ACTIVE EXIT` badge, no use
   ├─ <N> OFFLINE · SHOW toggle row (computed count)
   └─ PeerRow × M (offline, dimmed 0.62, only while expanded)
```

Deleted from v0.4: `ExitNodeSection.qml` (the dedicated exit section),
`CensusSection.qml` + `CensusCell.qml` (the name-only grid),
`CandidateRow.qml` (folded into PeerRow). Nothing replaces tabs (§V-2
carries: no navigation of any kind).

---

## W-3 — Frame, pinned-zone math, and the list lane

Frame rules carry from §V-5/§R-2 unchanged: width `34·gu` fixed
(`Layout.minimumWidth == Layout.preferredWidth`, nothing feeds back); height
`min(38·gu, 0.9·availableHeight)`; the frame NEVER resizes on data, search,
section expand, or op flight — scroll is the overflow valve. Sizing lives in
PopupShell.qml and nowhere else (single-site rule).

Spacing tokens: M = 6px inner margin (0.35·gu) · S = 4px (smallSpacing) ·
G = 9px (largeSpacing). Hairline = Kirigami.Separator, 1px.

Pinned zone heights (@ gu=18):

| Zone | px | gu expr | Notes |
|---|---:|---|---|
| top margin | 6 | 0.35·gu | |
| HEADER | 40 | 2.2·gu | selfName 18px line + identity 14px line + 8px padding; both buttons are 1.4·gu (25px) tall, vertically centered |
| STRIP row | 16/row | 0.9·gu | single-line elided; health rows may wrap to ≤2 lines (≤26px) then elide + tooltip |
| gap | 4 | smallSpacing | strip→band, band→search/lane |
| ROUTING BAND | 38 | 2.1·gu | hairline + 34 content + hairline; SAME height in both modes (frame never jumps when an exit engages); hides entirely when not running |
| SEARCH ROW | 34+4 | 1.9·gu | revealed only; sits directly above the lane |
| LIST LANE | fills | — | everything between pinned chrome and footer; scrolls |
| OFFLINE toggle | 26 | 1.4·gu | inside the lane, at its end |
| FOOTER | 24 | 1.3·gu | one line + padding; hairline above |
| bottom margin | 6 | 0.35·gu | |

Lane budget, norm19 shape (19 online · 3 exit-capable · 21 offline,
@ 684px frame):

```
Pinned (no strip items, search hidden): 6+40+4+38+4 + 24+6 = 122 → lane 562
Pinned (2 health warnings ≈ +32, worst persistent):            → lane ~530
Lane content: label 20 + 19×33 + toggle 26                     = 673
Scroll delta: 673−562 = 111px ≈ 3.4 rows (typical), ~4.3 with health
```

At 125% (gu=22, frame 836px): pinned ≈ 150px, rows 41px (inside the 36–44
row-height band), lane ≈ 686px — capacity only grows. Search revealed costs
38px of lane; that is where the v0.4 dead-space went: the lane, not the page,
absorbs overflow. A 40/40-online tailnet scrolls ~23 rows — accepted by the
v0.3 verdict. Primary readouts (header, strip, routing band) NEVER scroll.

---

## W-4 — Type scale, color, and status semantics

One unified proportional scale. No spot sizes; every rendered text uses one
of these four tokens. Floor rule: nothing renders below `Theme.smallFont`
anywhere (v0.4's microtype floor violation, §V-6, carries).

| token | binding | @ gu=18 | used for |
|---|---|---:|---|
| T1 hero | `0.8·gu` bold | 14.4 | selfName only |
| T2 name | `0.72·gu`, `Font.DemiBold` | 13.0 | peer names; routing-band exit name |
| T3 body | `Kirigami.Theme.smallFont` | ~11.5 | row sublines, strip, footer, toggle, hints, badges |
| T4 label | `smallFont` bold, `Font.AllUppercase`, `letterSpacing 0.4`, `disabledTextColor` | ~11.5 | section labels only |

Colors — `Kirigami.Theme.*` tokens only (dark and light Breeze correct by
construction; the §R-2 hex fallback note stands: `#3fd18b`/`#f4405c` if
tokens ever log undefined). Color NEVER carries state alone (WCAG 1.4.1) —
every state also has a glyph/shape/text channel:

| Role | Treatment |
|---|---|
| Primary text (names, band) | `textColor` |
| Muted information (sublines, hints) | `textColor` at `opacity 0.62` — NOT `disabledTextColor`, which is reserved for true-disabled controls and labels (v0.4's low-contrast 11px defect: information text was styled disabled). 0.62 measures ≈5.9:1 on dark Breeze, ≈7:1 on light — AA-passing at T3 sizes in both schemes |
| Labels / true-disabled | `disabledTextColor` (labels only, per §V-6) |
| Online dot · RUNNING · `ACTIVE EXIT` badge | `positiveTextColor` (fixed fallback `#3fd18b`) |
| Armed warning · op error · edge states | `negativeTextColor` |
| Health warnings ⚠ | `neutralTextColor` (orange = warning class per HIG; these are advisories — SELinux note, accept-routes off — not failures; deviation from v0.4's negative, ledgered §W-15) |
| Offline rows | whole-row `opacity 0.62`, dot `disabledTextColor` (Omarchy: dimmed, not hidden — state conveyed, information kept) |
| State-change flash | `highlightColor` at alpha 0.25, 400ms decay, on rows whose `Online` flag flips between ticks (change-blindness rule; not on counter updates) |

`tnum` (`font.features: ({ "tnum": 1 })`, Qt ≥ 6.6) REQUIRED on every ticking
numeric: row sublines, footer timestamp. Right-align nothing (rows are
single-column; alignment axis is the dot column at every row's left edge —
one grid, fixing v0.4's four unrelated x-axes).

---

## W-5 — PeerRow: the money row (the center of the redesign)

Full-width, 33px tall (`Math.round(1.85·gu)` = 33 @ gu=18; ≤ the operator's
~33px ceiling; 41px @ gu=22). One column — the v0.4 2-col census grid is
dead: 612px-wide rows have room for information, a 282px column does not.

Anatomy (x from row left; row content width = 600px inside margins):

```
x=0    ● state dot 6px (0.35·gu) — positive online / disabled offline
x=14   line 1 (y 2..17):  NAME            T2 DemiBold, elide-right
                           + trailing badges + [use] (right-anchored)
       line 2 (y 17..31):  SUBLINE         T3, textColor @ 0.62, elide-right, tnum
[use] button where present: 1.4·gu (25px) tall, right-anchored at x≈548,
       vertically centered across the full 33px row; ≥ smallSpacing gap from
       badge text; standard (non-flat) PC3.Button — full Breeze
       hover/press/focus/disabled chrome (fixes the "bare-text use" defect).
```

Subline composition (fields joined ` · `, grammar §W-14):

| Peer state | Subline |
|---|---|
| Online, active session (`peer.Active`) | `linux · 100.71.87.9 · direct · ↓ 12.3 M ↑ 1.1 G` |
| Online, idle (`!peer.Active`) | `macOS · 100.64.8.3 · via dfw` |
| Offline | `windows · 100.64.3.5 · last seen 3h ago` (`last seen never` when never seen) |

- `direct` = `ctx.peerIsDirect(peer)` (raw `CurAddr` non-empty); else
  `via <relay>` from `ctx.peerRelay(peer)` when non-empty; else omitted
  (never connected). Admin-console Connection semantics from local data.
- Traffic = `Model.fmtBytes(RxBytes / TxBytes)` with ↓/↑ glyphs; shown only
  when `peer.Active` (cumulative counters are meaningless as idle noise).
- OS token: prettified `peer.OS` — `linux · windows · macOS · iOS · android`;
  empty → omitted. **Text, not a glyph** — cut rationale: Model.osIcon emits
  Nerd Font codepoints (tofu on stock Bazzite, §R-9 flag 3) and Breeze ships
  no OS-brand icons (verified on this system: computer/laptop/smartphone/
  tablet exist; no linux/windows/apple glyphs); text is honest, accessible,
  and i18n-safe.

Trailing badges (right→left fixed order; exactly ONE role badge renders;
priority `ACTIVE EXIT` > `exit` > subnet CIDR):

| Badge | When | Style |
|---|---|---|
| `ACTIVE EXIT` | `peer.ExitNode === true` | T3 bold, `positiveTextColor` |
| `exit` | exit-capable candidate (`ExitNodeOption`, online, not active) | T3, muted 0.62 |
| `192.168.30.0/24` (first subnet route, `+N` if more) | `ctx.subnetRoutes(peer)` non-empty on a non-exit peer | T3, muted 0.62; all routes in tooltip |

(v0.4's `ACTIVE` tag on `peer.Active` is deleted — that flag means "has
recent session traffic" and painted three orange ACTIVEs on rows that were
merely chatty. Liveliness now lives in the ↓/↑ counters.)

Tooltip (every row, hover AND Accessible.name): `<dns> · <v4> · <v6>` +
` · routes: <all routes, ", "-joined>` when any + ` · last seen <t>` when
offline. Full DNSName and second IP live here, not in the row (cut list
below).

Rows are **non-interactive** (honest non-affordance: default cursor, no
hover background — nothing pretends to be clickable; v0.4 rule carries).
Offline rows: same anatomy, whole-row opacity 0.62, `use` never (candidates
are online-only, §T-4).

In-flight (§T-4 verbatim): all `use`/`×` disabled; the switching target row
grows +13px with a third line `switching…` (T3, disabled color), cleared on
completion OR failure OR timeout. Transient relayout accepted (§T windows).

**Field hierarchy and the cut list** (what each census field gets, and what
is deliberately cut):

| Field | Rank | Where | Cut/kept |
|---|---|---|---|
| Online state | 1 | dot + row opacity + count labels | kept — glance #3 |
| Name (DisplayName ‖ HostName) | 1 | line 1 | kept |
| OS | 2 | subline token | kept as text (glyph cut, see above) |
| TailscaleIPs[0] | 2 | subline | kept; IPv6 → tooltip (row carries v4; both IPs are copy-relevant, not glance-relevant) |
| direct / via relay | 2 | subline | kept — the admin console's Connection column, newly derivable locally |
| rx/tx ‖ last seen | 3 | subline, state-split | kept; LastHandshake recency CUT entirely — `Active` + counters already encode liveliness and handshake math adds a clock column for marginal value (Trayscale keeps it on the detail page; there is no detail page here) |
| Subnet routes | 3 | badge + tooltip | kept for subnet routers; `0.0.0.0/0` on exit candidates CUT from the row (tautology — §V-4 deviation ledger #1 carries) |
| Exit role | 3 | badge + routing band | kept |
| Full DNSName | 4 | tooltip | cut from row (display name is the label) |
| Tags / KeyExpiry / Created / PeerAPIURL / client version | — | nowhere | cut — Tags empty fleet-wide (census), KeyExpiry None fleet-wide, Created not actionable, client version is control-plane data absent from `status --json` |

---

## W-6 — Routing band (glance #2, both modes)

Fixed 38px band between strip and lane, hairline-bounded top+bottom
(Kirigami.Separator), present whenever `running` — the answer to "am I
routing through an exit node" is never absent and never ambiguous.

Active (Von Restorff: the ONE element that must stand out):

```
[network-vpn 16px, positiveTextColor]  ▸ exit node: tower   [×]
                                       (T3 muted)  (T2 name) (icon button)
```

- Copy `▸ exit node: <name>` + `×` byte-identical §T-4 (Mullvad exits name
  via `activeMullvadExit`); × tooltip `stop using exit node`.
- `×` = flat ToolButton, `window-close-symbolic` icon (16px), hit target
  ≥ 1.4·gu, ≥ smallSpacing from band text (§T-4 unchanged). The icon + tooltip
  fix the "unexplained ×" defect; the band position (38px, adjacent) fixes
  the "~550px from its content" defect.
- In-flight `exit-clear`: `switching…` renders in the band next to the name
  (the banner is the clear target); `×` disabled (§T-4 in-flight rule).

None active:

```
[network-vpn 16px, muted 0.62]  no exit node · direct · 3 available
```

- Sentence-case (not a STATUS word; §R-7 grammar). `<N> available` =
  computed exit-candidate count (hidden when 0).
- No buttons in this mode — switching happens on rows (`use`), which the
  band's "available" count points into. When the gate is disabled the band
  still renders (state is read-only fact); only buttons vanish (§T-1).

---

## W-7 — Header and self identity (glance #1)

```
● gdtower                                    [search] [Disconnect]
  RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
```

- Self block (single render site — dedup rule): line 1 selfName T1 bold
  (fallback `Tailscale`); line 2 identity T3 muted:
  `<backendState.toUpperCase()> · <selfIp> · <selfDnsName>` elide-middle.
  State dot 6px left of the name block: positive iff Running, neutral
  otherwise. Tooltip on the block: full `<selfDnsName> · <selfIp>` (row
  shows elided values; nothing invented). Click-to-copy stays deferred
  (§V-14, ROADMAP).
- `[search]`: flat ToolButton, `edit-find` icon, checkable = field revealed
  (§W-9), tooltip `Search peers (Ctrl+F)`. Hidden when nothing to search
  (0 peers or a down/missing/login/parse edge).
- Power button: §T-3 VERBATIM — flat ToolButton in the title row, states
  `Disconnect` / `Confirm disconnect` (negative while armed) / `Connect` /
  `working…` (disabled, honest), 1.4·gu min height, arm machine with 500ms
  dead-zone + 4s window + other-control-click disarm-perform, all unchanged.
- Self is NOT a row in the list (it is the machine you're sitting at; its
  facts are the header). List counts therefore equal the chip's counts
  exactly (`onlinePeers.length / peers.length`), keeping the count-sum
  invariant trivial: lane rows + offline count = `peers.length`.

---

## W-8 — Message strip (§T-5 items 1–4, order and strings unchanged)

Directly under the header; rows appear only when their condition holds;
§T-5 coexistence order is verbatim:

1. armed warning — `tailnet goes down here — remote access via ts.net drops
   until reconnect` (negative)
2. op error — `op failed: <first line of stderr>` / `op timed out` /
   `login required — run: tailscale login` (§T-5 verbatim, negative)
3. operator-gate hint — §T-1 verbatim, the ONLY site (disabled color)
4. health warnings — `⚠ <text>`, `neutralTextColor` (orange; ledgered
   deviation §W-15), one row each, order preserved, wrap ≤2 lines then
   elide + tooltip with the full text

Items 1–3 are single-line elided (§T-5). Dismissal rules unchanged (op
error dies on next successful op or popup reopen; armed warning dies with
disarm; popup close disarms §T-3 and clears the query).

---

## W-9 — Search (revealed, in-place — the Trayscale/plasma-nm port)

- Invocation: header `[search]` button (checkable) or `Ctrl+F` (popup
  focused) → reveal the 34px field row directly above the lane, auto-focus +
  select-all. The engine is Model.searchPeers unchanged (§V-8: multi-token
  all-must, prefix > substring > subsequence, weights DisplayName 4 /
  HostName 3 / DNSName 2 / IPs 1, score-desc sort, offline included).
- **In place, not replacing the popup:** the lane's label flips
  `ONLINE · 19` → `MATCHES · N`; the offline toggle row hides while the
  query is non-empty; results render as ordinary PeerRows (offline matches
  dimmed with `last seen` on the subline). No page-like mode, no void —
  the v0.4 search defect was replacement-plus-emptiness, not filtering.
- `Esc` → clear text if non-empty, else collapse the field and blur (clear
  restores `ONLINE · <N>` and the toggle). Trailing `✕` (edit-clear-all
  icon, tooltip `Clear search`) clears but keeps the field open. Popup close
  clears the query AND collapses (fresh open = fresh view, §V-8).
- Zero matches → centered muted `NO MATCHING PEERS` in the lane (PlaceholderMessage
  cause, §V-10 pattern). Search never interacts with the op machine (typing
  never disarms — §T-3 disarm triggers are control CLICKS, verbatim).
- Field is a standard PC3.TextField (Breeze field chrome: focus ring,
  hover), placeholder `Search peers`. Hidden entirely when `peers.length
  === 0` or an edge state (nothing to search).

Keyboard: `↑` from the lane's top interactive element returns focus to the
field (P5). Tab order: power → search → field (when revealed) → offline
toggle → visible `use`/`×` buttons. Focus ring = Breeze default (visible by
construction; keyboard pass is part of the shipping QA, §P12).

---

## W-10 — Offline block (collapsed by default)

- Toggle row INSIDE the lane, after the online rows: standard (non-flat)
  full-width PC3.Button, 1.4·gu tall, copy unchanged:
  `<N> OFFLINE · SHOW` ⇄ `<N> OFFLINE · HIDE` (count computed). The Breeze
  button chrome fixes the "SHOW looked like footer text" defect; the copy is
  approved and byte-identical.
- Expanded: PeerRows exactly as §W-5, whole-row opacity 0.62, subline
  `… · last seen <t>`, alphabetical, scrolling freely inside the lane.
- `showOffline` config seeds the initial state; the click flips it for the
  session (v0.4 behavior carries; no new config keys).
- Offline exit-capable peers render muted with NO use button (candidates are
  online-only, §T-4) — their `exit` badge still shows, so the role survives
  the collapse.

---

## W-11 — Interaction map (every interactive element, every state)

| Element | Rest | Hover | Armed/active | Busy | Disabled | Failure/edge |
|---|---|---|---|---|---|---|
| Power button (§T-3) | `Disconnect`/`Connect`, textColor, hover bg | hover bg | `Confirm disconnect`, negative + warning line; 500ms dead-zone; 4s window | `working…`, disabled | disabled when gate off (button hidden) | §T-5: error row, controls re-enable |
| Search button | edit-find, tooltip | hover | checked while field revealed | — | hidden when nothing to search | hidden on edges |
| Search field | placeholder | Breeze field chrome | focused ring; live filter | — | — | `NO MATCHING PEERS` cause |
| `✕` clear | edit-clear-all, tooltip | hover | — | — | hidden iff text empty | — |
| `use` (candidates) | standard Button, Breeze chrome, tooltip `use <name> as exit node` | hover | — | disabled while ANY op in flight (§T-4) | hidden on active row + gate disabled | §T-5 error row; `switching…` clears on timeout |
| Band `×` | window-close icon, tooltip `stop using exit node` | hover | — | disabled in flight | — | §T-5 error row |
| Offline toggle | `SHOW`/`HIDE` standard Button | hover | expanded state | — | — | — |
| PeerRow | non-interactive (default cursor, no hover) | tooltip only | ACTIVE EXIT badge / flash 400ms on Online flip | `switching…` line on target | offline dim 0.62 | — |
| Footer | non-interactive; tooltip `POLL EVERY <N> S` | — | — | — | — | `◐ STALE` when stamp > 3×poll |

One op at a time; presses during flight ignored (§T-5). No modals anywhere
(§T-3). Every icon-only control carries a tooltip that doubles as
Accessible.name (P11). No text below smallFont; `disabledTextColor` only on
disabled=true controls and T4 labels (hard invariant).

---

## W-12 — Edge states (detection by existing signals only)

Edge strings are §V-10/§R-8 verbatim; the edge row renders in the LANE
(centered, PlaceholderMessage anatomy: status icon 32px + string); header,
strip, and footer stay mounted — never a bare error screen:

| State | Signal | Lane rendering | Rest of popup |
|---|---|---|---|
| Needs login | `status.needsLogin` | `NEEDS LOGIN · RUN: tailscale login` (`network-unavailable` icon) | header `Connect`; identity `● NEEDS LOGIN · …`; band hidden; search hidden |
| Backend down | poll exit ≠ 0, stdout empty, stderr w/o "not found" | `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S` (`network-offline-symbolic`) | identity hidden (no status); band hidden; footer goes `◐ STALE` naturally; chip crossed |
| Binary missing | exit 127 / stderr `/not found/` | `TAILSCALE BINARY MISSING · INSTALL TAILSCALE` (`network-offline-symbolic`) | as backend-down |
| Parse error | `!parsed.ok` | `STATUS ERROR · RETRYING` (`dialog-cancel`) | as backend-down |
| 0 peers, running | `peers.length === 0` | `NO PEERS · TAILNET EMPTY` | band `no exit node · direct · 0 available`... band shows with count 0 → renders `no exit node · direct` (count clause omitted at 0); search hidden |
| 0 online, offline > 0 | computed | `ONLINE · 0` label + centered `NO ONLINE PEERS` + toggle row | band per its mode |

Icon names verified present in Breeze on this system.

---

## W-13 — Footer and provenance

Unchanged from v0.4 (fleet-original pattern, keep): left
`● AS OF hh:mm:ss` → `◐ STALE · hh:mm:ss` (stamp = `statusStampMs` vs 3×
`pollSeconds`; tnum; tooltip `POLL EVERY <N> S`); right gate verdict
`CONTROL ENABLED · <user>` / `CONTROL DISABLED` / `CONTROL UNAVAILABLE`.
Hairline separator above. 24px. The footer pins to the frame bottom; the
lane fills to it — no dead band (the v0.4 121px void is structurally
impossible: everything between band and footer is lane).

---

## W-14 — Copy catalog (byte-exact; every count computed)

Grammar unchanged (§R-7/§V-7): STATUS words CAPS; joiner ` · ` (single
spaces); control labels sentence-case; dedup — every string exactly ONE
render site.

| String | Site | Binding |
|---|---|---|
| `<selfName>` / `Tailscale` | header | `status.selfName` |
| `RUNNING`/`STOPPED`/`NEEDS LOGIN`… CAPS | header identity | `backendState.toUpperCase()` |
| `Connect` `Disconnect` `Confirm disconnect` `working…` | header | §T-3 verbatim |
| `tailnet goes down here — remote access via ts.net drops until reconnect` | strip 1 | §T-3 verbatim |
| `op failed: <stderr L1>` / `op timed out` / `login required — run: tailscale login` | strip 2 | §T-5 verbatim |
| `control disabled — run: sudo tailscale set --operator=$USER` / `control unavailable — tailscaled not responding` | strip 3 | §T-1 verbatim, only site |
| `⚠ <health[i]>` | strip 4 | `health[]`, order preserved |
| `Search peers` | placeholder + search tooltip | static i18n |
| `▸ exit node: <name>` + `×` (tooltip `stop using exit node`) | routing band | §T-4 verbatim (`exitBannerText()`, Mullvad via `activeMullvadExit`) |
| `no exit node · direct` [` · <N> available`] | routing band | computed; count clause omitted when 0 |
| `switching…` | target row line 3 / band | §T-4 verbatim |
| `ONLINE · <N>` / `MATCHES · <N>` | lane label | `onlinePeers.length` / `searchResults.length` |
| `NO ONLINE PEERS` / `NO PEERS · TAILNET EMPTY` | lane empties | computed |
| `<N> OFFLINE · SHOW` / `<N> OFFLINE · HIDE` | toggle | computed |
| `<OS> · <ip> · direct`/`via <relay>` [` · ↓ <rx> ↑ <tx>`] / [` · last seen <t>`] | row subline | `peer.OS` prettified, `fmtBytes`, `peerIsDirect`/`peerRelay`, `fmtLastSeen` |
| `ACTIVE EXIT` / `exit` / `<cidr>`[` +N`] | row badges | `peer.ExitNode` / `ExitNodeOption` / `subnetRoutes(peer)` |
| `<dns> · <v4> · <v6>` [` · routes: …`] [` · last seen …`] | row tooltip | full fields |
| `use` (tooltip `use <name> as exit node`) | candidate rows | §T-4 verbatim |
| `MATCHES · <N>`-empty: `NO MATCHING PEERS` | search | computed |
| `NEEDS LOGIN · RUN: tailscale login` / `TAILSCALED NOT RESPONDING · RETRY EVERY <N> S` / `TAILSCALE BINARY MISSING · INSTALL TAILSCALE` / `STATUS ERROR · RETRYING` | lane edge rows | §V-10/§R-8 verbatim |
| `● AS OF hh:mm:ss` / `◐ STALE · hh:mm:ss` (tooltip `POLL EVERY <N> S`) | footer | `statusStampMs` vs 3×`pollSeconds` |
| `CONTROL ENABLED · <user>` / `CONTROL DISABLED` / `CONTROL UNAVAILABLE` | footer | gate verdict only |

Count-sum invariant: `ONLINE·N + offline·M === peers.length === chip total`;
chip online === lane online rows. (Trivially holds — no peer renders twice.)

---

## W-15 — Deviation ledger vs §T-9/§V (deliberate, each with a reason)

1. **EXIT NODES section dissolved.** Exit candidates are rows in the one
   list (badge + `use`); the active exit node keeps its §T-4 banner (now the
   routing band) AND a marked row. Reason: the user's v0.3 verdict IS the
   one-list architecture; v0.4's dedicated section caused the collisions,
   the three-ACTIVE ambiguity, and stole 155px from a 19-row census. The
   §T-9 anti-duplication worry (peer in two places) dissolves: the band is
   routing state (verb), the row is the peer record (noun).
2. **`ACTIVE` tag deleted.** `peer.Active` means session-traffic, not exit
   selection (measured: three simultaneous orange ACTIVEs). Liveliness moves
   to ↓/↑ counters in the subline. Active exit marking becomes `ACTIVE EXIT`
   (positive color) — supersedes §T-4's "`exit` tag on the active row" wording.
3. **`use` and offline toggle restyled flat → standard Button.** §T-4
   SEMANTICS unchanged (single click, no confirm, tooltip, hit ≥ 1.4·gu,
   ≥ smallSpacing separation, hidden on active/gate-off). Reason: the
   independent-review defect — bare gray 13px text is not an affordance;
   Breeze button chrome supplies hover/press/focus/disabled for free.
4. **`×` becomes iconic** (`window-close-symbolic`) with its §T-4 tooltip.
   Reason: "unexplained ×".
5. **Health strip color negative → neutral (orange ⚠).** §T-5 never pinned
   the color; two live warnings are advisories, and orange/warning keeps red
   for genuine failures (armed, op errors, edges) per the HIG status ladder.
6. **Search: always-visible field → revealed field + checkable header
   button.** §V-8 engine untouched. Reason: measured — the 596×32px
   field was the popup's dominant object and its replace-mode created the
   void; Trayscale and plasma-nm both reveal search.
7. **Census 2-col name-only grid → 1-col rich rows.** Reverses §V-1
   failure 4's overcorrection per digest §5.1 (the approved Omarchy money
   row); the 33px ceiling holds because rows are full-width.
8. **Row flash on Online flips (400ms).** New, from the pattern bank's
   change-blindness rule; counters do not flash.

---

## W-16 — File layout and implementation constraints

```
contents/ui/
  main.qml         — data plumbing + chip UNCHANGED (chip byte-identical, §T-6;
                     §W helpers peerIsDirect/peerRelay/subnetRoutes already here)
  PopupShell.qml   — rewritten: frame, pinned chrome, lane, footer; owns ALL sizing
  PeerRow.qml      — NEW atom (money row; replaces CensusCell + CandidateRow)
  RoutingBand.qml  — NEW (band, both modes)
  SearchRow.qml    — modified: reveal/collapse contract (§W-9)
  SectionLabel.qml — kept as-is
  DELETED: ExitNodeSection.qml, CensusSection.qml, CensusCell.qml, CandidateRow.qml
```

Carry-forward constraints: `ctx` passing (never `root`); Plasmoid context
root-file-only; ~150ms deferred popup-open work (§R-10, no synchronous work
in the open handler); one handler per signal per file; `tools/check_qml.py`
before every install; timers run only while expanded; no new exec sources;
no new config keys (`interval`, `showOffline` only); `metadata.json` →
`0.5.0` with README Differences/Verified + ROADMAP updated in the same
commit. `tests/control.test.js` / `model.test.js` / `port.test.js` /
`search.test.js` pass UNCHANGED (control semantics untouched; search engine
untouched).

---

## W-17 — Wireframes (README-style, norm19 measured shape)

Default (19 online · 3 exit-capable · 1 active · 21 offline, gate on,
health empty):

```
gdtower                              [🔍] [Disconnect]
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
──────────────────────────────────────────────────────────
[network-vpn] ▸ exit node: tower                       [×]
──────────────────────────────────────────────────────────
ONLINE · 19
● tower                    ACTIVE EXIT
  linux · 100.101.135.11 · direct · ↓ 1.2 G ↑ 340 M
● aicube
  linux · 100.101.135.4 · direct
● greg-tab
  android · 100.101.135.9 · via dfw
● nasbox                                             [use] exit
  linux · 100.101.135.14 · direct
● spark2                                             [use] exit
  linux · 100.101.135.20 · direct · ↓ 12.3 M ↑ 1.1 G
● watertower            192.168.30.0/24
  linux · 100.101.135.2 · direct
   ⋮ (scrolls inside the lane; header/band/footer pinned)
21 OFFLINE · SHOW
──────────────────────────────────────────────────────────
● AS OF 23:44:39                        CONTROL ENABLED · gdeyoung
```

Offline expanded (same popup, after toggle click):

```
   ⋮
21 OFFLINE · HIDE
● greg-galaxy            (whole row 0.62)
  macOS · 100.101.135.31 · last seen 3h ago
● host103
  windows · 100.101.135.44 · last seen 2026-10-01
   ⋮
```

Search revealed + query (`tow`):

```
gdtower                              [🔍✓] [Disconnect]
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
[network-vpn] ▸ exit node: tower                       [×]
──────────────────────────────────────────────────────────
[🔍 Search peers                                    ] [✕]
MATCHES · 2
● tower                    ACTIVE EXIT
  linux · 100.101.135.11 · direct · ↓ 1.2 G ↑ 340 M
● watertower            192.168.30.0/24
  linux · 100.101.135.2 · direct
21 OFFLINE · SHOW  ← hidden while query non-empty
```

Health warnings present (strip item 4, orange):

```
gdtower                              [🔍] [Disconnect]
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
⚠ SELinux is preventing tailscaled from opening the SSH server…
⚠ accept-routes is off on this node while peers advertise routes
──────────────────────────────────────────────────────────
[network-vpn] ▸ exit node: tower                       [×]
```

Disconnect armed (§T-3 verbatim):

```
gdtower                              [🔍] [Confirm disconnect]   ← negative
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
tailnet goes down here — remote access via ts.net drops until reconnect
```

Gate disabled (§T-1: no buttons, one hint, band persists):

```
gdtower                              [🔍]
● RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net
control disabled — run: sudo tailscale set --operator=$USER
[network-vpn] ▸ exit node: tower     ← × hidden with gate
──────────────────────────────────────────────────────────
ONLINE · 19
● tower                    ACTIVE EXIT      ← badge survives, no use
  linux · 100.101.135.11 · direct · ↓ 1.2 G ↑ 340 M
```

Exit-node switch in flight (§T-4):

```
[network-vpn] ▸ exit node: tower                       [×]
ONLINE · 19
● nasbox                             [use] exit        ← disabled
  linux · 100.101.135.14 · direct
  switching…                                           ← transient line 3
```

Needs login / backend down / binary missing / parse / empty:

```
gdtower                              [Disconnect]
● NEEDS LOGIN · …
NEEDS LOGIN · RUN: tailscale login                    ← strip
(network-unavailable) NEEDS LOGIN · RUN: tailscale login   ← lane edge row
● AS OF 23:44:39                        CONTROL ENABLED · gdeyoung
```

```
TAILSCALED NOT RESPONDING · RETRY EVERY 10 S             ← lane, centered
◐ STALE · 23:44:39                      CONTROL ENABLED · gdeyoung
```

```
NO PEERS · TAILNET EMPTY                                 ← lane, centered
(no exit node · direct)                                  ← band, count 0
```

---

## W-18 — Acceptance criteria (harness: virtual harness, scale 1 + host DPR)

1. **Frame:** identical 34·gu × min(38·gu, 0.9·avail) WxH across all
   fixtures, during search, offline expand, op flight, and data ticks.
2. **Pinned zones never scroll:** header, strip, routing band, search row,
   footer y-positions pixel-stable while the lane scrolls; lane is the only
   scroll region; scrollbar lane reserved clear of `use`/`×` (§V-5 rule).
3. **Row geometry:** pitch 33px @gu=18 (±1 tolerance), dot column aligned at
   one x-axis across every row; nothing below smallFont; no `ACTIVE`-on-
   `peer.Active` anywhere (grep).
4. **norm19:** zero peer duplication; `ONLINE · 19` + `21 OFFLINE` = 40 =
   chip total; tower renders `ACTIVE EXIT` + band naming tower, no `use` on
   its row; nasbox/spark2 render `use` + `exit`; scroll valve open (≈111px)
   with header/band/footer pinned.
5. **norm19h (2 health warnings):** strip items render orange ⚠ in order;
   lane shrinks; pinned chrome intact.
6. **Search:** `tow` → tower first (prefix-scored) + watertower; `zzz` →
   `NO MATCHING PEERS`; in-place label flip `ONLINE · 19`→`MATCHES · 2`;
   toggle hidden while querying; Esc clears-then-collapses; `✕` clears only;
   Ctrl+F reveals+focuses; reopen clears+collapses; offline matches dimmed
   with last seen; search hidden on empty/login/down/missing/parse.
7. **Offline:** collapsed default; `showOffline=true` and wiped-config passes;
   expanded rows dim 0.62 with last-seen; `exit` badge survives collapse.
8. **Controls:** stub-log asserts `set --exit-node=<dns>` / `set
   --exit-node=`; in-flight disables all buttons + `switching…` transient +
   band `switching…` on clear; watchdog re-enables; arm/dead-zone/confirm
   pixel-asserted; `control.test.js` green unchanged; gate-off run: no
   buttons anywhere, hint in strip (only site), badges persist.
9. **Edges:** all six §W-12 states render their one string + standing
   header/footer; `◐ STALE` on down/missing/parse; no dead rows, no empty
   labels.
10. **Theme + type:** no hex literals in new files (fallback note §R-2);
    dark + light Breeze screenshots legible (dots, badges, muted sublines,
    dimmed offline rows) at scale 1 and 2; tnum present on sublines+footer.
11. **Chip untouched:** `git diff` on the compactRepresentation block empty.
12. **Flash:** flipping a peer's Online between ticks flashes that row only,
    400ms; counters never flash.

---

## W-19 — Risks

| Risk | Mitigation |
|---|---|
| Breeze Button implicit min-height may exceed 25px in some styles, stretching candidate rows | Button explicit height 1.4·gu + tight padding; if a style still enforces a taller floor, allow candidate rows to render 36px as a documented exception (still ≤ v0.4's 47px) — never shrink the hit target below 1.4·gu |
| 40/40-online tailnets scroll ~23 rows | Accepted by the v0.3 verdict; counts stay visible via chip + band; pinned chrome guarantees the glance triad regardless |
| Revealed search discoverability | Checkable header button with tooltip naming Ctrl+F; ↑-from-top returns to field; Esc collapse is teachable via tooltip on ✕ |
| Health orange vs v0.4 red | Ledgered §W-15 item 5; if the user wants red advisories, it is a one-token revert |
| `textColor @ 0.62` vs token purity | Not a hex literal (grep-clean); measured AA-passing on both schemes; alternative (disabledTextColor) is the measured v0.4 defect |
| Sticky `ONLINE · N` label not implemented (scrolls away) | Conscious cut for a plain ColumnLayout lane (proven in harness); counts remain pinned via chip/band; revisit only on user ask |
| `switching…` third line relayouts one row by +13px | Transient within §T-4 windows; v0.4 behavior carried |
| Long health texts | Wrap ≤2 lines then elide; full text in tooltip (never hover-only-critical: the ⚠ line itself is always visible) |
