# plasma-tailfin v0.6 — Popup UX Spec (§V6-1..§V6-n)

Status: DESIGN SPEC, delta against v0.5. Awaiting implementation.
Supersedes §W-1..§W-19 of `docs/UX-SPEC-V5.md` **where marked [AMEND]**;
every rule marked [KEEP] carries unchanged. §T-1..§T-8 (operator gate, closed
argv allowlist, mandatory disconnect confirm, inline two-step confirms, op
watchdog, chip invariants, scope guard) CARRY FORWARD byte-identical. The
compact panel chip is OUT OF SCOPE and byte-identical (§T-6) — this spec
touches the popup only.

Audience: the builder. Every rule below is implementable without asking a
question. If a value is not written here, it is unchanged from V5.

**Owner verdict driving this pass:** *"a little bit better, but not where it
needs to be."* (v0.3: *"No tabs, just a big long fucking list. It scrolls."* ·
v0.4: *"the way you structure content is trash…"*)

---

## 0. Ground truth this spec is built on (do not re-derive, do not contradict)

### 0.1 The defect backlog — vault `tailfin-ux-references-2026-11.md` §7 "v0.5 as-built audit (2026-11-07 AM)"

15 ranked defects, 4 BLOCKER / 6 MAJOR / 5 POLISH. Evidence tags **[V]** =
seen in pixels, **[C]** = verified in the as-built QML. Both are ground truth.
This spec is organized by those IDs: every rule in §V6-2..§V6-24 names the
defect it kills.

### 0.2 Pixel measurements taken from the as-built screenshots

The vision backend was unavailable for this pass (it returned plausible but
fabricated pixel descriptions, which were discarded). All numbers below were
measured directly from the PNGs with PIL, against the composited popup
surface `(57,44,67)` (Breeze-dark popup blurred over wallpaper).

**Popup frame — as-built, measured:**

| Fact | Measured | V5 said | Δ |
|---|---|---|---|
| Popup box | x 1939–2545, y 690–1374 → **606×684 px** | 612×685 | ✓ |
| Header block | y 697–724 (28px of ink; ~34px box) | 40px | ✓ |
| Routing band | top hairline y **734**, icon row y 746–757, bottom hairline y **769** → **37px** | 38px | ✓ |
| Band icon | x 1947–1958 (12×10px) | 16px icon | — |
| Band `×` | x **2518**–2529, y 746–757 | ≥1.4·gu hit | — |
| Peer row dots | x **1945**–1950 (6px), first dot y 804 | dot column x=0 | — |
| Row pitch | 32–40px, **avg 36.3px** (14 measured gaps) | 33+2=35 | +1.3px |
| Visible online rows | **15 of 19** (dots y 804 → 1312) | ~15 | ✓ |
| Lane bottom | last row dot y 1317 → footer text y 1348 | — | — |
| Footer text | AS OF x 1942–2023 · CONTROL x 2365–2541 (**ends 4px from edge**) | — | defect P1 |
| Search row (active) | field x 1958–2508, `✕` x **2520**–2535, y 776–805 | — | defect B3 |
| Band `×` vs search `✕` | x 2518 vs **2520** — same column, 30px apart | — | defect B2/B3 |
| Health strip (2 warnings) | orange text y 738–749 and y 759–767 → one **30px merged blob**, 435px wide | 2 rows, 16px each | defect M6 |
| Health → band shift | band top y 776 (was 734) = **+42px** | — | ✓ |
| All-offline (zero19) | green pixels = **26** (header dot only); toggle ends y 876; **lane void y 876→1348 = 472px** | — | defect M5 |
| Green census, default view | **814 green px** across 4 element classes, all the identical color | — | defect B4 |
| Header dot vs row dots | x 1941 vs **1945** — 4px axis mismatch | one axis | minor |

**Contrast, measured at glyph peak vs the composited surface:**

| Element | Peak RGB | Ratio | Verdict |
|---|---|---|---|
| Peer name (T2 DemiBold) | (241,241,242) | **11.52:1** | ✅ AAA |
| Peer subline (T3 @ 0.62) | (169,165,173) | **5.37:1** | ✅ AA |
| `ONLINE · 19` label | (170,165,173) | 5.38:1 | ✅ AA |
| `use` button label | (239,240,241) | 11.39:1 | ✅ |
| Footer (disabledTextColor) | (189,195,199) | 7.30:1 | ✅ |
| **Health warning (orange)** | (199,130,61) | **4.14:1** | ❌ **sub-AA at T3** |
| **ACTIVE EXIT badge (green)** | (126,166,75) | **4.61:1** | ⚠️ AA at best, at bold T3 |
| Band icon (green mask) | (126,166,75) | 4.61:1 | ⚠️ graphic only |

Glyph-peak sampling is optimistic; true average is lower. The two rows marked
❌/⚠️ must change in v0.6.

### 0.3 Reference systems borrowed, and why

- **Omarchy tailfin** (owner-endorsed) — the money row: OS · name · one muted
  subline · trailing action; offline dimmed-not-hidden; collapsed offline
  count row. **The row ECONOMY is kept; the row LAYOUT changes to columns.**
- **Trayscale** (owner-endorsed) — header master switch, search-as-revealed,
  inline exit switch on the peer row, `NeedsAttention` on the active exit.
  v0.6 takes Trayscale's *switch-on-the-row* model literally: the exit
  affordance is a labeled control ON the row, and the row is the state.
- **Tailscale admin console** — the canonical field set and, critically, its
  **column** model: a table you can read down, not a paragraph you re-read.
  This is the reference that answers B1.
- **Breeze / Kirigami** — token-only colors, `Units` spacing, `tnum`,
  hairline separators, standard PC3 button chrome.
- **house widget bank** (`widget-ux-patterns.md`) — glance triad, 36–44px
  rows, per-cause empty states, tnum, ≤3 semantic colors.

### 0.4 Non-negotiables (user-ratified — not relitigated here)

1. **One list. No tabs.** Section headers collapse; the list scrolls.
2. Popup ~612×685; **frame never resizes** on data, search, expand, op flight.
3. **Breeze tokens only** — `Kirigami.Theme.*` / `Kirigami.Units.*`. Zero
   hard-coded hex; must survive the light theme.
4. QML constraints: no whole-object `font` binds (members only — the
   `SectionLabel` law); `font.pixelSize` for everything that must scale; no
   C++ changes required.

### 0.5 Anti-goals

No tabs. No modals. No new panels. No color-only state. No emoji as
iconography. No OS-brand glyphs (Breeze has none — text or generic glyph).
No second scrolling region. No pixel value that isn't `Kirigami.Units`-derived.

---

## 1. The 5 structural moves (the one-screen summary)

**v0.5's failure mode, in one line: density as prose — every fact is present,
but nothing is *addressable*.** The peer row is a sentence; you cannot compare
two machines without re-reading both. One color (green) carries four meanings.
Two identical `×` glyphs sit 30px apart meaning opposite things. This pass is
not a new architecture — the v0.5 skeleton ships and works. It is a **slot
pass**: every attribute gets a reserved, aligned slot it can be read down.

### Move 1 — The peer row becomes a grid, not a sentence (kills B1, M4)

The row stops being prose. It becomes **fixed slots with hard x-axes** on two
lines, so a column can be read top-to-bottom (row = 2.0·gu = 36px @gu18;
`Wc` = row content width = 32.2·gu = 579px):

```
LINE 1  x0    ● dot 6px            STATUS   (online=positive / offline=disabled)
        x16   NAME …               IDENTITY (T2 DemiBold, elide; 272px zone)
        x270→392  …192.168.30.0/24  ROUTE    (T3 right-aligned chip, 6.8·gu slot)
        x397→490  [vpn] EXIT NODE    ROLE     (T3; icon+bold when active, 5.2·gu slot)
        x496→579  [use exit]|[stop]  ACTION    (labeled 1.4·gu button, 4.6·gu slot, always reserved)

LINE 2  x16   Linux · direct       OS+CONN  (T3 muted, 8.6·gu slot, left-aligned)
        x310→ …100.101.135.11      ADDRESS  (T3 tnum, right-aligned, 7.2·gu slot — RIGHT EDGE FIXED at x310)
        x363→ …↓ 1.2 G · ↑ 340 M   TRAFFIC  (T3 tnum, right-aligned at x579 — or `idle`, or `last seen 23d`)
```

Every slot has a fixed start x and width, **identical for every row, online
and offline**. ADDRESS right-edges all land at x310 — read the IP column
straight down. TRAFFIC right-edges all land at x579 — read the traffic column
straight down. `↓rx ↑tx` no longer trails a prose subline; route CIDR is its
own chip; `use exit` is the single labeled action. **The prose subline
disappears entirely** — its facts move into columns.

### Move 2 — Exit state moves into the row; the band becomes confirmation (kills B2, M3)

The routing band's job in v0.5 was to *state* the exit node. In v0.6 the
**row states it** (a tinted row + `EXIT NODE` badge + a `stop` control), and
the band becomes a **single confirmation line** that only appears when an
exit node is active. The two `×` glyphs get different jobs and different
appearances: the band's control is a **labeled** `stop` button, never a bare
`×`. Nothing in the popup is a bare `×` except the search field's clear.

### Move 3 — Green means connectivity, and nothing else (kills B4)

`positiveTextColor` is reserved for **online-ness** (the row dot, the
`online` count). Exit-node state gets its own accent — `Kirigami.Theme.highlightColor`
for the active-exit row tint, with a **label**, never hue alone. Buttons are
neutral chrome. The header's `RUNNING` and the lane's `ONLINE` stop being two
words for one fact: the header says what the *device* is, the lane says what
the *peers* are, and the words are different (`this device` vs `online`).

### Move 4 — Search becomes auditable (kills B3)

The results header states the denominator (`2 of 40 peers`), the matched
substring is highlighted **in the row**, the clear control lives **inside the
field** (and the band `×` is gone), and the keyboard model is discoverable
(↑/↓/Enter/Esc printed in the row). A fuzzy result explains itself: the
matched span is highlighted wherever it matched, and the row shows *why* it
matched.

### Move 5 — The lane earns its dead space; the empty states teach (kills M2, M5, M6, P1–P5)

- Section labels get real weight + a count + a **partially-clipped row at the
  fold** so the list visibly continues.
- The **all-offline** state stops being a 472px void: the offline block
  **auto-expands** when 0 peers are online, and the lane shows an aggregate
  line (`0 of 21 peers online · showing all offline`).
- Health warnings become **one orange block that names its scope** and are
  mirrored on the affected rows (a `⚠` glyph at the ROUTE slot's left edge,
  §V6-19), so the band and the list cross-reference without hunting.
- The footer gets a grid, margins, and a **relative** age (`5s ago`), and the
  last-seen format becomes relative (`23d`), with absolute values in tooltips.

**What is explicitly NOT changing:** one-list architecture; no tabs; the
popup frame size; the panel chip; §T-1..§T-8 control semantics; the search
*engine* (§V-8 scoring); the exit-op argv strings (§T-4).

---

## 2. §V6-1 — The slot doctrine (the cross-cutting answer)

**[NEW]** — answers the audit's cross-cutting note ("density as prose, no
addressable slots") at the architectural level.

**Rule.** The popup has exactly **one vertical alignment system**. Every slot
below is a reserved zone with a hard x-axis, defined in `Kirigami.Units.gridUnit`
(gu) and fixed at `gu = 18` for the px column. `Wc` (row content width) =
`34·gu` popup − `2 × smallSpacing·1.25` shell margins − `0.8·gu` scrollbar
reserve − `2 × smallSpacing` lane insets = **32.2·gu = 579px**.

| Slot | Line | x-start (gu / px) | Width (gu / px) | Align | Contents |
|---|---|---|---|---|---|
| STATUS | 1 | 0 / 0 | 0.9 / 16 | left | 6px dot (0.35·gu) |
| IDENTITY | 1 | 0.9 / 16 | → 15.0 / 270 | left, elide right | NAME (T2) |
| ROUTE | 1 | 15.0 / 270 | 6.8 / 122 | right | CIDR chip `+N` |
| ROLE | 1 | 20.5 / 369 | 5.2 / 94 | right | vpn icon + `EXIT NODE` / `exit` |
| ACTION | 1 | 23.1 / 416 | 9.1 / 164 | right | `[use exit]` / `[stop]` button |

*(ACTION as measured from x416 is the button's right-anchored box within the
reserved slot; see §V6-2 for the exact button geometry — slot reserves
4.6·gu for the button + 0.25·gu gap, the remainder is dead-reserve so the
ROLE x never moves between gate states.)*

| Slot | Line | x-start | Width | Align | Contents |
|---|---|---|---|---|---|
| OS+CONN | 2 | 0.9 / 16 | 8.6 / 155 | left, elide | `Linux · direct` etc. |
| ADDRESS | 2 | ends 17.2 / **310** | 7.2 / 130 | **right** | IPv4, tnum |
| — gutter — | 2 | 17.2..20.2 | 1.6 / 53 | empty | scan break |
| TRAFFIC | 2 | ends 32.2 / **579** | 12 / 216 | **right** | traffic / `idle` / `last seen` |

**Invariants (hard, harness-checkable):**

1. **ADDRESS right-edges land at x310 in every row** — online, offline,
   dimmed, flashing, switching. ±1px tolerance.
2. **TRAFFIC right-edges land at x579 in every row.** ±1px.
3. **ROLE and ACTION x positions never move** between rows, gate states,
   or op-flight states. The ACTION slot is **always reserved** (an empty
   plain row reserves the same 164px; its IDENTITY zone simply elides
   earlier). Gate-off hides the button, never the slot.
4. **One dot axis:** the STATUS dot column x0 applies to the header's self
   dot too (v0.5 measured a 4px mismatch: header x1941 vs rows x1945 —
   dead). The header self-dot sits in the same 0.9·gu column.
5. Line 1 and line 2 text blocks share the x0.9·gu left edge (v0.5 measured
   name x26 vs subline x21 — a 5px ragged left edge; dead).
6. `tnum` on ADDRESS, TRAFFIC, both count labels, and the footer clock.
7. Nothing renders below `Kirigami.Theme.smallFont`; no whole-object font
   binds anywhere — `font.pixelSize` / `font.weight` / `font.features`
   members only (the SectionLabel law, now enforced popup-wide; several
   v0.5 `font: Kirigami.Theme.smallFont` whole-object binds are rewritten).

---

## 3. BLOCKER B1 — "Peer rows cannot be scanned — metadata is a sentence, not columns" [V]

**Audit evidence.** Every row packs `<OS> · <ip> · <route> · <rx> · <tx>` as
tiny concatenated text; values never align vertically across rows; comparing
any attribute across peers requires re-reading each row. Vision verdict:
"choosing the right machine is guesswork." Pixel-verified: subline text
starts x21-rel, name x26-rel (ragged); trailing cluster start varies per row
(`ACTIVE EXIT` ends x2514, `use` chrome x2454–2516); row pitch jitters
32–40px.

**Direction (audit).** Fixed row grid — OS column, name, IP in right-aligned
monospace, route+traffic as a stable right-aligned cluster; same geometry
every row, online and offline.

### §V6-2 — PeerRow is a slot grid; height fixed at 2.0·gu **[AMEND §W-5]**

**Old (V5 §W-5):** two-line row, `Math.round(1.85·gu)` = 33px; line 1 =
dot + NAME + trailing badges + `[use]`; line 2 = one prose subline
`<OS> · <ip> · direct|via <relay> [· ↓ rx ↑ tx]` / `… · last seen <t>`,
joined `·`, elide-right, leftMargin 0.78·gu.

**New:** the row is the §V6-1 slot map. Concretely, in `PeerRow.qml`:

- Root `Item`, `implicitHeight: Kirigami.Units.gridUnit * 2.0` **(36px)** —
  **no content-driven height, ever.** Line 1 occupies y1..17, line 2
  y19..33, 2px internal bottom padding. Lane `spacing: 0` — **row pitch is
  exactly 2.0·gu** (v0.5 measured 32–40px jitter because Label implicit
  line-heights drove the column; fixed height + anchored lines kills the
  jitter). Lane capacity unchanged: as-built pitch measured 36.3px average,
  so 36px is a normalization, not a growth.
- Line 1 = `RowLayout`: STATUS column (`Item` 0.9·gu wide, dot 0.35·gu at
  x0, `anchors.verticalCenter: parent.verticalCenter`), IDENTITY Label
  (`Layout.fillWidth`, elide), then a right-anchored `RowLayout` of fixed
  slots in order ROUTE, ROLE, ACTION (each `Layout.preferredWidth` per the
  table, fixed; contents right-aligned inside).
- Line 2 = `RowLayout`: OS+CONN (fixed 8.6·gu, elide right), ADDRESS Label
  (`Layout.preferredWidth: 7.2·gu`, `horizontalAlignment: Text.AlignRight`,
  elide **middle** — a clipped IP keeps both ends), spacer
  (`Layout.fillWidth`), TRAFFIC Label (fixed 12·gu, right-aligned).
- Offline rows: **identical slots**, whole-row content `opacity 0.62`
  (Omarchy dimmed-not-hidden law, carried). The dot renders
  `disabledTextColor`; every slot still lands on its axis.
- Rows remain **non-interactive at rest** (no hover background, default
  cursor, tooltip only). The single exception is search-focus mode (§V6-11).
- Tooltip per row (`Accessible.name` too, carried): `<dns> · <v4> · <v6> ·
  routes: <all> · last seen <absolute date>` — absolute values live here
  (§V6-3/P5).
- Flash on Online flip: carried verbatim (§W-15.8 — 400ms,
  `highlightColor` @0.25; counters never flash).
- In-flight target row: third line `switching…` (§T-4 verbatim, carried);
  row grows to 2.72·gu transiently, then returns to 2.0·gu.

**Why not a single-line grid** (rejected with math): one line holding
dot + name + OS + conn + IP + traffic + route chip + action needs
16+240+20+90+104+120+122+83 ≈ 795px > 579px available. Two lines is the
only honest fit; alignment comes from fixed slots, not from sharing a line.

### §V6-3 — Field grammar per slot (OS case, relay wording, last-seen format) **[AMEND §W-14 subline grammar]**

**Old (V5):** subline `<OS> · <ip> · direct|via <relay> [· ↓ rx ↑ tx]` /
`<OS> · <ip> · last seen <t>`; OS token lowercase `linux`/`windows` with
`macOS`/`iOS` exceptions; relay rendered `via dfw`; last-seen absolute ISO
beyond days.

**New — OS+CONN slot** (max `macOS · relay · dfw` = 18ch ≈ 128px ≤ 155px ✓):

| Peer state | OS+CONN renders | TRAFFIC renders |
|---|---|---|
| online, direct (`peerIsDirect`) | `<OS> · direct` | `↓ <rx> · ↑ <tx>` when `peer.Active`, else `idle` |
| online, relayed | `<OS> · relay · <Relay>` | as above |
| online, never connected (no CurAddr, no Relay) | `<OS>` | `idle` |
| offline | `<OS> · offline` | `last seen <rel>` |

- **OS prettification (P2):** `Linux` `Windows` `macOS` `iOS` `Android` —
  brand case, consistently. Empty OS → slot omitted (slot stays reserved).
  Rendered as **text, not glyphs** (carried §W-5 decision: Breeze ships no
  OS-brand icons — verified; Nerd Font codepoints are tofu on stock
  Bazzite).
- **Relay wording (P3):** `via dfw` → **`relay · dfw`**. "via" names a
  mystery; "relay" names the thing. Tooltip appends ` · relayed via DERP
  <region>` for the curious.
- **Direct** stays `direct` (the admin console's word; the contrast pair
  `direct` / `relay · x` is self-teaching).
- **Last-seen (P5):** **relative only** in TRAFFIC — `last seen 3m` /
  `last seen 8h` / `last seen 23d`; cap at `last seen >1y`. Absolute
  datetime lives in the row tooltip (carried). `fmtLastSeen` relative
  branches already exist; the ISO fallback branch is deleted from display
  (tooltip only).
- **ADDRESS slot:** `TailscaleIPs[0]` (IPv4). IPv6 stays in the tooltip
  (carried §W-5 cut list). `tnum`.
- **TRAFFIC slot:** cumulative `RxBytes`/`TxBytes` via `fmtBytes`, `↓`/`↑`
  glyphs, `tnum`, shown only while `peer.Active` (carried — cumulative
  counters are noise at idle; the slot then reads `idle`). Em dash banned
  as a placeholder; the word `idle` carries meaning.
- **ROUTE slot (chip):** first subnet CIDR + `+N` when more (carried);
  right-aligned, elide left (keep the mask), all routes in tooltip. On
  exit-capable peers the `0.0.0.0/0` tautology stays cut (§V-4 ledger #1).
  Health-warning marking may occupy this slot's left edge (§V6-19).

### §V6-4 — tnum and the alignment axes **[KEEP §W-4 (tnum rule), AMEND (scope)]**

`tnum` (`font.features: ({ "tnum": 1 })`) REQUIRED on: ADDRESS, TRAFFIC,
`ONLINE · n` count, `MATCHES · n OF m`, offline toggle count, footer clock
(carried). **New scope:** the ADDRESS and TRAFFIC columns are the entire
point of §V6-1 — digit-width stability is what makes a column readable, so
tnum on those two slots is a hard invariant, not a nicety. Type scale
carried unchanged from §W-4 (T1 hero 0.8·gu bold · T2 name 0.72·gu DemiBold ·
T3 body smallFont · T4 label smallFont bold caps). Color roles per §V6-13.

---

## 4. BLOCKER B2 — "Exit-node controls are ambiguous and scattered" [V]

**Audit evidence.** `exit` reads like a status label; `USE` is tiny with an
unlabeled target; the strip's `×` reads as "close popup"; `Disconnect` sits
unscoped next to search in the header. Wrong-action risk on an operation
that reroutes all internet traffic. Pixel-verified: band `×` at x2518–2529
y746–757; in search mode the field `✕` renders at x2520–2535 — the same
column, 30px apart.

**Direction (audit).** One explicit affordance per exit-capable row ("use
exit"); active exit carried by the ROW (badge + tint), strip becomes
confirmation only; `×` becomes labeled "stop routing"; Disconnect moves out
of the header cluster or gains scope text.

### §V6-5 — Candidate rows: the action is a labeled `use exit` button **[AMEND §W-5/§W-15.3, §T-4 label]**

**Old (V5):** standard PC3.Button, text `use`, tooltip `use <name> as exit
node`, hit ≥1.4·gu, right-anchored ~x548, hidden on active row and gate-off.

**New:** same standard (non-flat) `PC3.Button` in the reserved ACTION slot
(§V6-1), **label `use exit`** — verb + object; the button says what it does
with no tooltip required. Button geometry: height `1.4·gu` (25px), width
`4.4·gu` (79px: 8ch label ≈ 58px + 2×1.5·smallSpacing padding), vertically
centered on the row. Tooltip stays **byte-identical**: `use <name> as exit
node`. §T-4 semantics verbatim: single click, no confirm, one op at a time,
disabled while any op flies, hidden when gate off (slot reserved, §V6-1
invariant 3). States: rest = neutral Breeze chrome · hover = Breeze hover ·
pressed = Breeze press · focus = Breeze focus ring · disabled (op in
flight) = `disabledTextColor` label, no pointer · hidden = gate off or
already-active row. On failure: §T-5 strip error row (carried), button
re-enables, nothing else changes.

**Ledger:** the label string `use` → `use exit` deviates from §T-4's
byte-exact wording. Reason: audit B2 [V] — "USE (tiny, unlabeled target)"
invited wrong-action risk on a traffic-rerouting op; the verb+object label
is the audit's own direction. The tooltip keeps the §T-4 sentence; the argv
(`set --exit-node=<dns>`) is untouched.

### §V6-6 — The active exit is a state of the ROW: tint + badge + `stop` **[NEW]**

The active exit node (`peer.ExitNode === true`) renders:

- **Whole-row tint:** `Kirigami.Theme.highlightColor` at **opacity 0.12**
  rectangle under the row content (above the offline-dim and flash layers in
  z-order: flash > tint > content). Von Restorff: this is the one tinted
  row in the list.
- **ROLE slot:** `network-vpn` icon 0.7·gu (13px), `isMask`, colored
  `highlightColor`, + label `EXIT NODE` — T3 **bold, `textColor`** (not
  green, not highlight-as-text: theme-proof on light Breeze where
  highlight-on-white ≈3:1 fails for text).
- **ACTION slot:** a `stop` button — same geometry/chrome as §V6-5, label
  **`stop`**, tooltip **`stop using exit node`** (the §T-4 sentence,
  byte-identical). Fires `exit-clear`. §T-4 semantics verbatim (single
  click, no confirm, in-flight disables, hidden gate-off).
- States: tint present whenever the row is the active exit (online by
  definition — an exit node that goes offline is no longer `ExitNode`);
  `stop` disabled while any op flies; during `exit-clear` flight the strip
  shows `switching…` (§V6-7) and the button is disabled.

**What this deletes:** the v0.5 `ACTIVE EXIT` green badge (B4) and the
band's `×` (B2). "Badge and band said it twice, neither said it in words"
— now the row says it in tint, icon, word, and a labeled control, and the
band confirms it in a sentence.

### §V6-7 — RoutingBand → ExitStrip: confirmation-only, active-only, 1.55·gu **[AMEND §W-6]**

**Old (V5 §W-6):** fixed 38px hairline-bounded band, present whenever
running, BOTH modes; active mode = `▸ exit node: <name>` + `×`; none mode =
`no exit node · direct · N available`.

**New — `ExitStrip.qml` (replaces `RoutingBand.qml`):**

- **Renders only when `running` AND an exit node is active.** Height
  **1.55·gu (28px)**, hairline above only (the section label's rule below
  separates it from the lane), background `highlightColor` @0.10.
- Content, left→right: `network-vpn` icon 0.9·gu (16px) in
  `highlightColor`; text `all traffic routing through` (T3, textColor @0.62)
  + **`<name>`** (T2 DemiBold, textColor) elide-middle; right side:
  `<N> direct available` omitted — **no controls, no counts, no `×`**. The
  strip is a sentence that confirms; the row owns the control (§V6-6).
- In-flight `exit-set`: `switching…` (T3, disabledTextColor) appends after
  the name. In-flight `exit-clear`: strip persists until the poll tick
  confirms, then disappears.
- **None-active mode: no strip at all.** The routing fact moves into the
  header identity line (§V6-14: `this device · direct · <ip> · <dns>`).
  Reclaim: 37px + 4px gap of pinned chrome in the default state (as-built
  band occupied y734–769). When an exit engages, the strip's 28px appears
  and the lane's content origin shifts 28px down — **accepted, ledgered**:
  the frame never resizes (§W-3 carries); the shift IS the feedback that
  routing changed, and it is user-initiated, rare, and animated ≤200ms if
  at all.
- **Gate-off:** strip still renders (read-only fact); nothing to hide —
  there are no controls in it anymore.
- Mullvad exits: name via `activeMullvadExit` (carried §W-14).

### §V6-8 — `Disconnect` moves to the footer; the header is identity + search **[AMEND §W-7, §T-3 position only]**

**Old (V5):** flat ToolButton `Disconnect`/`Confirm disconnect` in the title
row, next to `[search]`.

**New:** the power control is a labeled standard (non-flat) `PC3.Button` at
the **footer right** (§V6-20 grid), label states and the entire §T-3 state
machine **byte-identical** — `Disconnect` / `Confirm disconnect` (negative
palette while armed, 500ms dead-zone, 4s window, other-control-click
disarm-perform) / `Connect` / `working…` (disabled). Height 1.4·gu, width
≥4.4·gu. Button height 1.4·gu (25px) inside the 1.55·gu (28px) footer row.

Why the footer: the header cluster was `gdtower [search] [Disconnect]` — an
unscoped destructive verb wedged against a filtering toggle (audit B2).
The footer is the popup's action bar (provenance left, power right); the
header becomes purely identity. Fitts: the footer's right edge is a
screen-edge-adjacent target; the armed state remains impossible to miss
because §T-3's warning line renders in the strip directly above the lane.

States: rest neutral chrome · armed `Confirm disconnect` in
`negativeTextColor` + strip warning row (§T-3 verbatim) · busy `working…`
disabled · hidden when gate off (hint row already covers it, §T-1) ·
`Connect` variant when stopped. Keyboard: footer button is the LAST tab
stop (§V6-22).

---

## 5. BLOCKER B3 — "Search results are unauditable; the only obvious × clears the wrong thing" [V]

**Audit evidence.** `MATCHES · 2` has no denominator; matched substring not
highlighted; fuzzy result (host103 for "host03") unexplained; no discoverable
keyboard model; the sole prominent × belongs to the exit strip. Pixel: band
`×` x2518 and search `✕` x2520 — one column.

### §V6-9 — The results label states its denominator **[AMEND §W-9/§W-14]**

**Old:** lane label flips `ONLINE · 19` → `MATCHES · <n>`.

**New:** flips to **`MATCHES · <n> OF <peers.length>`** (e.g.
`MATCHES · 2 OF 40`, both computed, tnum). Zero matches renders
**`NO MATCHES · “<query>”`** centered in the lane (T3, textColor @0.62 —
not disabled gray; this is information, and the query echo is the
explanation). The offline toggle stays hidden while querying (carried).

### §V6-10 — Matched characters are bolded in the row **[NEW]**

- In search mode, the IDENTITY slot renders NAME as rich text
  (`textFormat: Text.RichText`, same font/size/weight) with **the matched
  characters bolded** (`Font.Bold` over T2's DemiBold) wherever they occur.
- **Marking algorithm (deterministic):** for each query token (in order),
  scan NAME left-to-right from the previous match end, marking each token
  character's next occurrence (greedy in-order). This is the same
  subsequence walk §V-8's engine performs, re-derived for display only —
  **the engine itself is untouched.** Prefix/substring matches therefore
  highlight contiguously (`tow` → **tow**er); subsequence matches highlight
  exactly the chars that matched, in place (`host03` matches `host103` by
  skipping the stray `1`: greedy marks h,o,s,t then 0,3, so the row bolds
  `host`+`03` and leaves the `1` regular) — the row *shows why it matched*,
  killing the "fuzzy result is unexplained" defect.
- If a token's characters cannot all be found in NAME (matched via
  DNSName/IP), bold nothing in NAME — the row still renders; the
  denominator and the row's presence explain it. Rule: never bold a span
  that didn't match.
- HTML-escape NAME before injecting `<b>` spans (names are hostnames, but
  the rule is the rule). Elide still applies (elide-right on the Label);
  bolding never widens the slot.

### §V6-11 — A discoverable keyboard model for results **[NEW]**

- `↑` from the field (or from the first row) moves focus to the **first
  result row**; `↑`/`↓` cycle through result rows (wrapping off — stop at
  ends); `Enter` on a candidate row fires its `use exit` (§T-4 path); on
  the active-exit row fires `stop`; on any other row: no-op. `Esc` returns
  focus to the field (then clears, then collapses — carried §W-9 ladder).
- Focused row renders `highlightColor` @0.08 background + the Breeze focus
  ring on the row item; the row's `stop`/`use exit` button (if any) shows
  its focus ring when the row itself is focused (focus forwarded).
- **Focus mode exists only while the field is revealed with a non-empty
  query** — rows are otherwise non-interactive (carried). This is the one
  sanctioned exception, and it is why the hint is printed (below).
- Discoverability: the field's placeholder is
  **`Search peers · ↑↓ results · Esc clears`** (placeholder, not permanent
  chrome — zero cost when idle; the placeholder is the hint surface).

### §V6-12 — Exactly one × in the popup, and it clears the query **[AMEND §W-9]**

**Old:** field `✕` (edit-clear-all) + band `×` (window-close-symbolic) —
two × glyphs, one column, opposite meanings.

**New:** the band `×` is deleted (§V6-6/§V6-7). The **only** ×-shaped
control in the popup is the search field's clear: `edit-clear-all` icon,
inside the field row's trailing edge, tooltip **`Clear search (Esc)`**,
visible iff text non-empty, click clears and refocuses the field (carried).
Invariant: **no `window-close-symbolic` glyph anywhere in the popup**
(grep + pixel). Esc ladder carried verbatim: clear → collapse → blur.

---

## 6. BLOCKER B4 — "Green means everything, so it means nothing" [V]

**Audit evidence.** Green dots (online), `ACTIVE EXIT` badge, `USE` buttons,
and the exit strip icon are all green; header says RUNNING while rows say
ONLINE for the same token class. Pixel census: **814 green pixels in the
default view across 4 element classes, every one the identical (126,166,75);
the badge and strip icon measure 4.61:1** — AA only because they're bold.

**Direction (audit).** Green reserved for connectivity only; routing state
gets its own accent; action buttons neutral chrome.

### §V6-13 — Color allocation table (one meaning per color) **[AMEND §W-4 color table]**

**Old (V5):** `positiveTextColor` on: online dots, RUNNING, `ACTIVE EXIT`
badge. `neutralTextColor` on health warning text. `negativeTextColor` on
armed/op-error/edges. `highlightColor` only for the 400ms flash.

**New — three semantic colors, one meaning each, never hue alone:**

| Token | Meaning (the ONLY meaning) | Surfaces |
|---|---|---|
| `positiveTextColor` | **connectivity** | row dots (online) · header self dot (running) |
| `highlightColor` | **routing / selection / change** | active-exit row tint @0.12 · ExitStrip bg @0.10 + its icon · ROLE icon on active row · search-focus row @0.08 · Online-flip flash @0.25 (carried) |
| `negativeTextColor` | **failure / armed** | armed warning, op error, edge rows, armed `Confirm disconnect` label |
| `neutralTextColor` | **advisory** | health `⚠` glyph and block tint ONLY (text is textColor — §V6-18) |
| neutral chrome | **actions** | every button (`use exit`, `stop`, offline toggle, power) is standard Breeze chrome — no colored buttons anywhere |

- **Green count in the default view drops from 4 element classes to 1**
  (dots). Harness-checkable: green pixels exist only inside STATUS slot
  x-bands (§ acceptance 4).
- Hue is never the only channel (WCAG 1.4.1, carried and extended):
  online=dot-shape presence; routing=word `EXIT NODE` + tint + icon;
  advisory=`⚠` glyph + tint; failure=word (error strings). Every state is
  readable in grayscale.
- `highlightColor` as TEXT is banned (light-Breeze highlight-on-white ≈3:1);
  it is used only as tint (with a text/glyph partner) or as a masked icon
  ≥13px (non-text 3:1 satisfied by the tint partner).

### §V6-14 — Header vocabulary: the self is `this device`, not a louder peer **[AMEND §W-7, §W-14; kills M1]**

**Old (V5):** line 1 `gdtower` T1 bold; line 2 identity
`RUNNING · 100.71.87.72 · gdtower.horse-frog.ts.net` (T3 @0.62,
elide-middle) — reads like a peer row with bolder text; `RUNNING` collides
with the lane's `ONLINE` for the same fact class.

**New:**

- Line 1: selfName T1 bold (carried) + `[search]` ToolButton (carried,
  §W-9 — now the header's only control).
- Line 2 (T3, textColor @0.62, elide-middle), grammar by state:
  - running, no exit: **`this device · direct · <selfIp> · <selfDnsName>`**
  - running, exit active: **`this device · via <exitName> · <selfIp> · <selfDnsName>`**
  - stopped: `stopped · <selfIp> · <selfDnsName>` (lowercase status word;
    dot de-greens to `neutralTextColor`)
  - needs login: `NEEDS LOGIN · <selfDnsName>` (edge string carried)
- The word RUNNING is **deleted** from the default state. The green dot
  says "up" (connectivity, §V6-13); `this device` names WHO the block is
  about (audit M1: "not identified as THIS machine"); `direct`/`via <name>`
  carries the routing fact that the deleted band used to own (§V6-7).
  Header↔lane vocabulary no longer collides: the header describes the
  device, the lane counts the peers.
- Header dot moves into the 0.9·gu STATUS column (§V6-1 invariant 4 — one
  dot axis top to bottom).
- Tooltip on the block: full `<selfDnsName> · <selfIp>` (carried; elided
  values live here). Click-to-copy stays ROADMAP (carried §V-14).

---

## 7. MAJOR M2 — "Section headers too weak; fold and bottom states read as the end" [V]

**Audit evidence.** `ONLINE · 19` tiny (measured label band ≈9px ink, peak
ink 56/300); 15 of 19 visible with a hairline scrollbar and no partial-row
peek at the fold; the footer's divider reads as end-of-list.

### §V6-15 — Section label with count + rule **[AMEND §W-2 lane label, SectionLabel.qml]**

**Old:** `SectionLabel` T4, disabledTextColor, text `Online · 19`, 20px.

**New — label row, 1.25·gu (22px):**

```
ONLINE  19 ────────────────────────────────────────────────
```

- `ONLINE` T4 (smallFont bold, AllUppercase, letterSpacing 0.4,
  `disabledTextColor` — labels only, carried).
- Count **`19`** immediately after: T3 **bold `textColor`, tnum** — the
  count is data, not a label; it is the strongest thing in the row.
- A `Kirigami.Separator` hairline fills from `largeSpacing` after the count
  to the right edge at opacity 0.5 — the group-header rule (Tailscale admin
  console pattern) that gives the label row real weight and terminates the
  header instead of letting the first row do it.
- Search mode flips the same row to `MATCHES · 2 OF 40` (§V6-9) with the
  same rule. The offline toggle row keeps its byte-identical copy
  `<N> OFFLINE · SHOW/HIDE` (carried §W-10) as a standard full-width button.

### §V6-16 — The fold advertises continuation **[NEW; absorbs P4]**

- **Lane bottom fade:** a 10px (0.55·gu) gradient overlay pinned to the
  lane's bottom inside edge — `backgroundColor` at opacity 1 → 0 (vertical
  gradient, theme token, no hex) — visible **iff the lane can scroll**
  (bind `flickable.atYEnd === false`). At list end the fade is gone and the
  last row sits 0.25·gu above the footer hairline (P4: measured crowding
  gone). Reduced-motion: the fade is static, no animation involved.
- **Fold cuts rows, not gaps:** lane `spacing: 0` with the row's 2px
  internal bottom padding (§V6-2) means the fold almost always clips
  mid-row — a half-visible name is the universal "there's more" signal; a
  clean gap at the fold is what made 15 rows look like all of them.
- **Scrollbar:** policy AsNeeded (carried); the 0.8·gu content reserve
  (carried, as-built comment) keeps it off the ACTION slot.
- Footer clearance: footer hairline + 0.25·gu padding above it; the lane's
  `Layout.bottomMargin` is 0 (the fade owns the transition).

---

## 8. MAJOR M3 — "Two stacked bands burn ~60px before any peer content; exit state duplicated"

**Killed by §V6-7 + §V6-6 + §V6-14** (no separate rule needed — this
section records the arithmetic):

- As-built pinned chrome before the lane: header 34px + band 37px (+4 gap)
  = ~75px; audit counts ~60px of "local-device band + exit-node strip".
- v0.6 default state: header only (~40px incl. identity line) — the strip
  does not render (routing fact in the identity line), the band's both-modes
  law is retired. **Net reclaim ≈ 41px ≈ 1.1 extra visible rows**, and the
  exit duplication (strip + badge with no row treatment) becomes
  reinforcement: row tint + `EXIT NODE` + `stop` (§V6-6) is the state;
  the strip (§V6-7) is a one-line confirmation naming the same host.

---

## 9. MAJOR M4 — "Right-edge zone is semantically mixed"

**Killed by §V6-1** (recorded here for traceability): the trailing zone had
three unrelated tenants (CIDR, `exit`, `USE`) starting at inconsistent x
(measured: badge ends x2514, `use` chrome x2454–2516). v0.6 gives each tenant
a fixed slot with a fixed x (ROUTE 6.8·gu · ROLE 5.2·gu · ACTION 4.6·gu
reserved) and a fixed right→left order. A column that means one thing, in
every row.

---

## 10. MAJOR M5 — "All-offline state under-communicates" [C]

**Audit evidence.** Zero-online renders centered `NO ONLINE PEERS` in
disabled-gray + dimmed rows, but the local header stays green/healthy and no
aggregate line says "0 of 21 online." Pixel: green census 26px (header dot
only); **toggle ends y876, lane void y876→1348 = 472px of nothing.**

### §V6-17 — The all-offline state fills the lane and says the number **[AMEND §W-12 zero-online row]**

**Old:** `ONLINE · 0` label + centered `NO ONLINE PEERS` (disabledTextColor)
+ collapsed toggle; ~472px void.

**New, when `onlinePeers.length === 0 && offlinePeers.length > 0`:**

1. **Auto-expand:** the offline block renders expanded for this state
   (`offlineExpanded` forced true while online==0; a click on the toggle
   still collapses it — the override is a default, not a lock; state resets
   when peers return or popup closes).
2. **Section label row** reads **`OFFLINE · 21`** (same §V6-15 anatomy) —
   not `ONLINE · 0`; a zero-count section header is noise, and every
   visible peer is offline.
3. **Aggregate line** directly under it (T3, `textColor` @0.62, centered,
   one line, no label chrome): **`0 of 21 peers online · showing all offline`**
   — the number the audit demands, computed (`onlinePeers.length`,
   `peers.length`).
4. Offline rows render per §V6-2/§V6-3 — dimmed, slotted, `last seen <rel>`
   filling the void with true information.
5. Header self-dot **stays positive** while `running` — the daemon is up;
   that is a true fact about THIS device (the tailnet's emptiness is the
   lane's fact, stated by the aggregate line). De-greening the dot was
   considered and rejected: it would report the tailnet's peer count in the
   device-status slot — a different lie. Ledgered.
6. ExitStrip: hidden (no exit can be active with 0 online peers; if the
   engine still reports one, it renders — we render facts, not inferences).

**Void rule (harness):** in this state the lane contains no contiguous
empty vertical band taller than 40px between its first and last content.

---

## 11. MAJOR M6 — "Health warnings: merged red/orange wall, tooltip-only detail, no row cross-reference" [C]

**Audit evidence.** Warnings render as 1–2 orange text rows at top with
reasons in tooltips; affected peers unmarked; band↔row cross-referencing is
manual. Pixel: two rows merge into one 30px orange blob spanning 435px;
the band shifts +42px; **orange text measures 4.14:1 — sub-AA at T3.**

### §V6-18 — Health block: readable text, advisory skin, bounded **[AMEND §W-8 item 4]**

**Old:** `⚠ <text>` per warning, `neutralTextColor` text, wrap ≤2, elide +
tooltip, one row each.

**New — one advisory block under the header (same position, §W-8 order 4 of
4 unchanged):**

- Block = `Rectangle` full lane width, radius `smallSpacing`, border 1px
  `neutralTextColor` @0.4, background `neutralTextColor` @0.10; internal
  padding `smallSpacing`; warning rows inside separated by
  `smallSpacing·0.5`.
- Each row: `⚠` glyph 0.7·gu (13px) `neutralTextColor` + text **T3,
  `textColor` @0.85, wrap ≤2 lines, elide, full text in tooltip**
  (carried). The 4.14:1 orange text wall dies; the advisory *skin* (orange
  border + tint + glyph — all ≥3:1 non-text or redundant) carries the
  warning class, the words stay readable (≥7:1). WCAG 1.4.1: tint + glyph +
  text — fine in grayscale.
- **Count in the block header when >1:** first line inside the block:
  `HEALTH · <n>` (T4 label) — the blob becomes a bounded, counted,
  separable block; no more silent merge.
- The block replaces the strip's naked rows; strip items 1–3 (§T-5 armed /
  op error / gate hint) render unchanged above/below it per §W-8 order.
- Click behavior: none (tooltips only) — carried; acknowledgment flows stay
  OUT (scope guard).

### §V6-19 — Affected peers are marked in the list **[NEW]**

- **Rule (deterministic, display-only):** when ANY active health warning
  contains the substring `route` (case-insensitive — the live warnings are
  `accept-routes is off…` and peers-advertise-routes class), every peer
  whose `subnetRoutes(peer)` is non-empty renders a `⚠` glyph 0.6·gu (11px),
  `neutralTextColor`, at the **left edge of its ROUTE slot** (before the
  CIDR), tooltip `route-related health warning · see popup top`.
- **Honesty note (ledgered):** the engine's health strings do not name
  peers; this is a heuristic mapping "routes warning → route advertisers."
  It marks CANDIDATE affected peers, and the tooltip says so. Warnings
  without a derivable peer set (e.g. the SELinux note) mark nothing — never
  guess a peer.
- Cross-reference: the health block's `HEALTH · n` header + the row glyphs
  share the ⚠ glyph — scan the list, see the marked rows, no hunting.

---

## 12. POLISH P1–P5 (traceability + the footer rule)

| ID | Defect [evidence] | Killed by |
|---|---|---|
| P1 | Footer crowding; `CONTROL ENABLED · operator` runs into the edge (measured: right text ends **4px** from popup edge); AS OF absolute-only | **§V6-20** |
| P2 | OS labels lowercase words w/ branded-case exceptions (`windows` vs `macOS`) [V] | §V6-3 (OS prettification table) |
| P3 | `via dfw` opaque jargon [V] | §V6-3 (`relay · dfw` + tooltip) |
| P4 | Scrollbar hairline + last row crowds the footer divider [V] | §V6-16 (fade + 0.25·gu clearance + end-of-scroll fade removal) |
| P5 | last-seen absolute ISO in tiny type [C] | §V6-3 (relative only; absolute in tooltip) |

### §V6-20 — Footer grid: relative age, margins, power slot **[AMEND §W-13; completes §V6-8]**

**Old (V5):** 24px footer; left `● AS OF hh:mm:ss` (disabledTextColor); right
gate verdict; hairline above; measured right text 4px from the popup edge.

**New — footer = action bar + provenance, 1.55·gu (28px) + hairline above:**

```
──────────────────────────────────────────────────────────────────────
● 5s ago                              CONTROL ENABLED · gdeyoung  [Disconnect]
```

- **Left: freshness, relative.** `● <n>s ago` where `<n> = max(0,
  round((clockNow − statusStampMs)/1000))`, tnum. Stale state (>3× poll):
  **`◐ stale · <n>s ago`** (`negativeTextColor` dot-to-halfmoon glyph
  carried). Tooltip: **`as of hh:mm:ss · poll every <N>s`** (the absolute
  value lives here — P1's direction). The relative form answers "how old
  is this" without date math; the absolute form is one hover away.
- **Right cluster, right-aligned, ending ≥0.8·gu (14px) from the popup's
  right edge** (the scrollbar reserve extends to the footer — kills the
  measured 4px collision): gate verdict text (carried strings
  `CONTROL ENABLED · <user>` / `CONTROL DISABLED` / `CONTROL UNAVAILABLE`,
  T3 disabledTextColor), then `largeSpacing`, then the power button
  (§V6-8). Gate-off: verdict text stays, button hidden.
- Footer height 1.55·gu; power button 1.4·gu; single line, no wrap.
- Provenance semantics unchanged otherwise (stamp source, 3× poll rule,
  `statusStampMs === 0` → `--:--:--`).

---

## 13. §V6-21 — Interaction map (every interactive element, every state) **[AMEND §W-11]**

| Element | Rest | Hover | Armed/Focus | Busy | Disabled | Hidden when | Failure/edge |
|---|---|---|---|---|---|---|---|
| `use exit` (candidate rows) | neutral Button, ACTION slot | Breeze hover | Breeze focus ring | label dimmed, no pointer | while ANY op flies (§T-4) | gate off · active row · offline row | §T-5 strip error; re-enable on watchdog |
| `stop` (active-exit row) | neutral Button | Breeze hover | Breeze focus ring | disabled in flight | while ANY op flies | gate off (tint+badge persist) | §T-5 strip error |
| Power (footer, §T-3 verbatim) | `Disconnect`/`Connect` | Breeze hover | `Confirm disconnect` negative + strip warning; 500ms dead-zone; 4s window | `working…` disabled | — | gate off | §T-5 error row; controls re-enable |
| `[search]` header button | edit-find, checkable | hover | checked while revealed | — | — | nothing to search / edges | — |
| Search field | placeholder `Search peers · ↑↓ results · Esc clears` | Breeze field chrome | focus ring; live filter | — | — | collapsed (§W-9 reveal contract) | `NO MATCHES · “<q>”` state |
| Field `✕` clear | edit-clear-all, tooltip `Clear search (Esc)` | hover | — | — | — | text empty | — |
| Result row (search focus mode) | non-interactive; tooltip | tooltip only | `highlightColor` @0.08 + focus ring; Enter = row action | — | — | query empty | Enter no-op on plain rows |
| Offline toggle | `<N> OFFLINE · SHOW` Button | hover | expanded = `HIDE` | — | — | query non-empty | — |
| PeerRow (rest) | non-interactive, default cursor, no hover bg | tooltip only | ACTIVE-exit tint persistent; flash 400ms on Online flip | `switching…` line 3 | offline dim 0.62 | — | — |
| Footer | non-interactive; relative age | tooltip (absolute + poll) | — | — | — | — | `◐ stale` state |

One op at a time; presses during flight ignored (§T-5, carried). No modals
(§T-3, carried). Every icon-only control carries a tooltip that doubles as
`Accessible.name` (P11, carried). Tab order: header search → field (when
revealed) → visible result rows (search mode) → `use exit`/`stop` → offline
toggle → footer power. `↑` from the lane's top interactive element returns
to the field (P5, carried).

---

## 14. §V6-22 — Edge states **[KEEP §W-12, three deltas]**

The §W-12 table carries verbatim (needs-login / backend-down /
binary-missing / parse-error / 0-peers / 0-online), lane-centered
PlaceholderMessage anatomy, header+footer stay mounted. Deltas:

1. **0-online row** is replaced by §V6-17 (aggregate line + auto-expand;
   `NO ONLINE PEERS` string retired — ledger).
2. **Identity line** grammar per §V6-14 (`this device · …`; `NEEDS LOGIN`
   and `STOPPED` override the slot).
3. **No ExitStrip in any edge state** except needs-login-with-active-exit
   (render facts, §V6-17.6).

Search hidden on all edges (carried). Chip crossed/warned logic untouched
(main.qml, out of scope).

---

## 15. §V6-23 — Copy catalog DELTA (all else §W-14 carries byte-identical)

| String | v0.5 | v0.6 | Site |
|---|---|---|---|
| header identity (default) | `RUNNING · <ip> · <dns>` | `this device · direct · <ip> · <dns>` / `… · via <name> · …` | §V6-14 |
| exit candidate button | `use` | `use exit` | §V6-5 |
| active-exit badge | `ACTIVE EXIT` (green) | `EXIT NODE` (bold textColor + vpn icon) | §V6-6 |
| active-exit control | `×` (window-close icon, band) | `stop` (labeled button, row) | §V6-6/§V6-7 |
| band (none mode) | `no exit node · direct · N available` | *(deleted — fact moves to identity line)* | §V6-7 |
| band (active) | `▸ exit node: <name>` + `×` | `all traffic routing through <name>` | §V6-7 |
| search results label | `MATCHES · <n>` | `MATCHES · <n> OF <total>` | §V6-9 |
| zero matches | `NO MATCHING PEERS` | `NO MATCHES · “<query>”` | §V6-9 |
| search placeholder | `Search peers` | `Search peers · ↑↓ results · Esc clears` | §V6-11 |
| clear tooltip | `Clear search` | `Clear search (Esc)` | §V6-12 |
| OS tokens | `linux`/`windows`/… | `Linux`/`Windows`/… | §V6-3 |
| relay token | `via <relay>` | `relay · <relay>` | §V6-3 |
| last seen | `last seen 3h ago` / ISO date | `last seen 3h` / `23d` (relative only) | §V6-3 |
| idle traffic | *(omitted)* | `idle` | §V6-3 |
| offline os+conn | *(OS only)* | `<OS> · offline` | §V6-3 |
| 0-online empty | `NO ONLINE PEERS` | `OFFLINE · <n>` + `0 of <n> peers online · showing all offline` | §V6-17 |
| footer freshness | `● AS OF hh:mm:ss` | `● <n>s ago` / `◐ stale · <n>s ago` (tooltip keeps absolute) | §V6-20 |
| health block | `⚠ <text>` rows | `HEALTH · <n>` header + `⚠ <text>` rows in tinted block | §V6-18 |

Everything else — §T-3/§T-5 strings byte-identical, offline toggle copy,
edge strings, tooltips named above as "byte-identical" — carries. Count-sum
invariant carried: `online + offline === peers.length === chip total`.

---

## 16. §V6-24 — File layout and implementation constraints **[AMEND §W-16]**

```
contents/ui/
  main.qml         — data plumbing + chip UNCHANGED (chip byte-identical §T-6;
                     helpers peerIsDirect/peerRelay/subnetRoutes/exitBannerText
                     already present and sufficient — no JS changes required)
  PopupShell.qml   — header (identity grammar), footer grid + power button,
                     lane (spacing 0, fade overlay, all-offline mode),
                     health block; owns ALL sizing (single-site rule carries)
  PeerRow.qml      — REWRITTEN: slot grid (§V6-1/§V6-2/§V6-3), active-exit
                     tint + stop (§V6-6), search highlight + focus mode
                     (§V6-10/§V6-11) — the one new geometry-bearing component
  ExitStrip.qml    — NEW file (replaces RoutingBand.qml): §V6-7, 1.55·gu,
                     confirmation-only. RoutingBand.qml DELETED.
  SearchRow.qml    — placeholder/✕ contract (§V6-11/§V6-12)
  SectionLabel.qml — count + rule anatomy (§V6-15)
```

Carry-forward constraints (all §W-16 items): `ctx` passing never `root`;
plasmoid-context root-file-only; ~150ms deferred open work; one handler per
signal per file; `tools/check_qml.py` before install; timers only while
expanded; no new exec sources; **no new config keys**; `metadata.json` →
`0.6.0` with README Differences/Verified + ROADMAP in the same commit;
`control.test.js` / `model.test.js` / `port.test.js` / `search.test.js`
pass **unchanged** (control argv and the search engine are untouched).
New invariant from §V6-1: **no whole-object font binds** — rewrite the
remaining `font: Kirigami.Theme.smallFont` binds to member binds
(`font.pixelSize: Kirigami.Theme.smallFont.pixelSize`).

---

## 17. Carried forward from V5 untouched ([KEEP] — the builder's checklist)

| V5 rule | Status in v0.6 |
|---|---|
| §W-1 glance contract (3 questions, pinned chrome) | KEEP — questions unchanged; surfaces reorganized (§V6-7/§V6-14) |
| §W-2 structure tree (one lane, edge rows, offline toggle inside lane) | KEEP skeleton — heights per §V6-2/§V6-7/§V6-15/§V6-20 |
| §W-3 frame + single-site sizing + never-resizes law | KEEP verbatim |
| §W-4 type scale (T1–T4), smallFont floor, `disabledTextColor` = labels/disabled only | KEEP (color table superseded by §V6-13) |
| §W-5 field hierarchy + cut list (IPv6→tooltip, Tags/KeyExpiry/etc. nowhere, handshake cut) | KEEP — placement moves to slots (§V6-2/§V6-3) |
| §W-7 header self block single-render-site; self NOT a row; counts === chip counts | KEEP (identity grammar → §V6-14) |
| §W-8 strip order items 1–3 (§T-5 verbatim) + dismissal rules | KEEP verbatim |
| §W-9 search reveal contract (Ctrl+F, Esc ladder, popup-close clears, in-place filtering, offline matches dimmed) | KEEP (label/keyboard/highlight deltas §V6-9..§V6-12) |
| §W-10 offline block (toggle copy, showOffline seed, badge survives, `use` never offline) | KEEP verbatim |
| §W-12 edge states table | KEEP + 3 deltas (§V6-22) |
| §W-15 deviations 1/2/7/8 (no exit section; `ACTIVE`-on-traffic deleted; rich row; 400ms flash) | KEEP |
| §W-16 constraints (ctx, timers, tests, no new keys) | KEEP + font-bind invariant (§V6-24) |
| §W-19 risks (Breeze button min-height, 40/40 scroll accepted, tnum alt) | KEEP — see §19 for new risks |

---

## 18. Deviation ledger (deliberate, each with a reason)

1. **§T-4 label `use` → `use exit`.** Audit B2 [V]: unlabeled tiny target on
   a traffic-rerouting op. Tooltip and argv byte-identical.
2. **§T-4 `×` → labeled `stop` button on the row; band `×` deleted.** Audit
   B2/B3 [V]: two stacked ×'s in one column, one reading as "close popup".
   Tooltip `stop using exit node` byte-identical; argv `exit-clear`
   untouched.
3. **§W-6 both-modes band law retired.** Audit M3 [V]: ~60px of pinned
   chrome before content. None-mode fact moves to the identity line
   (§V6-14); engage/disengage shifts lane origin 28px — accepted because
   the frame itself never resizes and the shift is user-initiated feedback.
4. **`RUNNING` deleted from the default identity line.** Audit B4/M1 [V]:
   header/lane vocabulary collision; state remains readable via dot +
   exception words (`stopped`, `NEEDS LOGIN`).
5. **`ONLINE · 0` / `NO ONLINE PEERS` retired for the all-offline state.**
   Audit M5 [C] + measured 472px void: replaced by `OFFLINE · n` +
   aggregate line + auto-expand (§V6-17).
6. **Health text neutral→textColor, orange skin only.** Measured 4.14:1 —
   sub-AA at T3; the audit's readability complaint plus the WCAG hard limit
   force it (§V6-18).
7. **§V6-19 route-warning row marking is a substring heuristic.** The
   engine's health strings name no peers; the rule marks route-advertisers
   when a warning mentions "route", tooltip says what it is. Display-only;
   never presented as engine truth.
8. **Relative time in footer + last-seen.** Audit P1/P5 direction; absolute
   values preserved in tooltips — nothing is lost, one hover deep.
9. **`idle` appears in the TRAFFIC slot.** Absence of counters was
   ambiguous (no data vs. never connected); the word teaches that the
   column is live.
10. **Header dot stays green when 0 peers online.** Considered per audit M5
    direction, rejected: the dot reports THIS device's daemon state;
    tailnet emptiness is the lane's aggregate line's fact (§V6-17.5).

---

## 19. Wireframes (norm19 measured shape; slot map of §V6-1)

Default (19 online · 3 exit-capable · 1 active · 21 offline · gate on):

```
● this device · via tower · 100.71.87.72 · gdtower.horse-frog…      [🔍]
────────────────────────────────────────────────────────────────────
[vpn] all traffic routing through tower                      ← 28px, tinted
ONLINE  19 ─────────────────────────────────────────────────────────
▐● tower                        ⚠192.168.30.0/24  [vpn]EXIT NODE  [stop] ▌
  Linux · direct            100.101.135.11          ↓ 1.2 G · ↑ 340 M
 ● aicube                                                            (slot reserved)
  Linux · relay · dfw       100.101.135.4                            idle
 ● greg-tab                                                          (slot reserved)
  Android · relay · dfw     100.101.135.9                            idle
 ● nasbox                                     [vpn]exit        [use exit]
  Linux · direct            100.101.135.14                           idle
   ⋮ (fold cuts mid-row; 10px fade at lane bottom)
21 OFFLINE · SHOW
────────────────────────────────────────────────────────────────────
● 5s ago                                CONTROL ENABLED · gdeyoung [Disconnect]
```

No exit active (band gone, identity carries the fact):

```
● this device · direct · 100.71.87.72 · gdtower.horse-frog.ts.net  [🔍]
ONLINE  19 ──────────────────────────────────────────────────────────
 ● tower                                ⚠192.168.30.0/24  [vpn]exit [use exit]
  Linux · direct            100.101.135.11          ↓ 1.2 G · ↑ 340 M
```

Search, query `tow` (denominator, bold marks, keyboard hints):

```
[🔍 **tow**er works…                                    ] [✕]
MATCHES  2 OF 40 ───────────────────────────────────────────────────
 ● **tow**er                                [vpn]EXIT NODE      [stop]
  Linux · direct            100.101.135.11          ↓ 1.2 G · ↑ 340 M
 ● hos**t**-**o**ps-**w**in              (subsequence marks)  ⚠cidr
  Linux · direct            100.101.135.2                            idle
```

All-offline (auto-expanded; no void):

```
● this device · direct · 100.71.87.72 · gdtower.horse-frog.ts.net  [🔍]
OFFLINE  21 ────────────────────────────────────────────────────────
        0 of 21 peers online · showing all offline
 ● greg-galaxy                    (whole row 0.62)      last seen 3h
  macOS · offline           100.101.135.31                   last seen 3h
   ⋮ (dimmed rows fill the lane)
```

Health (bounded block + row marks) / armed / gate-off / in-flight (§T
machines verbatim, positions per §V6-18/§V6-8/§T-1/§T-4):

```
┌ ⚠ HEALTH · 2 ───────────────────────────────────────────────────┐
│ ⚠ accept-routes is off on this node while peers advertise routes │
│ ⚠ SELinux is preventing tailscaled from opening the SSH server…  │
└──────────────────────────────────────────────────────────────────┘
 ● watertower                  ⚠192.168.30.0/24                   ← marked
● 5s ago                                 CONTROL DISABLED         (no button)
```

---

## 20. Acceptance checklist (harness: virtual harness, scale 1 + host DPR; every item mechanically checkable)

**Frame & chrome**

1. Frame: identical 34·gu × min(38·gu, 0.9·avail) across all fixtures and
   during search, expand, op flight, data ticks (§W-18.1 carried).
2. Default state has **no band**: no hairline pair between header and
   section label (pixel: the y-gap header→label contains no 1px full-width
   rule). Active-exit fixture shows exactly one tinted 28px strip.
3. Pinned zones (header, health block, strip, search row, footer)
   y-stable while the lane scrolls; lane is the only scroll region.

**Slots (B1/M4)**

4. **Column axes:** across ≥5 consecutive rows, ADDRESS right edges within
   ±1px of each other; TRAFFIC right edges within ±1px; ROLE right edges
   and ACTION slot left edges constant; dot column one x (header dot
   included). Measure on the norm19 view crop.
5. Row pitch: every consecutive visible pair = 2.0·gu ±0.5px (no 32–40
   jitter).
6. Grep: no `font:` whole-object binds in changed files; `tnum` present on
   ADDRESS/TRAFFIC/counts/footer bindings; no hex literals in diffs.

**Exit semantics (B2/M3)**

7. Exactly one `use exit` button per online candidate row; one `stop` on
   the active row; zero bare `×`/`window-close-symbolic` glyphs popup-wide
   (grep + pixel).
8. Active-exit row: tint rectangle sample ≥8/255 per-channel delta vs
   surface; `EXIT NODE` label present; strip names the same host.
9. Stub log: `set --exit-node=<dns>` / `set --exit-node=` unchanged; one op
   at a time; `switching…` transient; watchdog re-enables (§W-18.8 carried).

**Color (B4)**

10. Default-view green census: green pixels exist **only** within STATUS
    slot x-bands (row dots + header dot). Badge/buttons/strip icon contain
    zero green. Count classes = 1 (vs as-built 4 / 814px).

**Search (B3)**

11. Query `tow`: label reads `MATCHES · 2 OF 40`; bold spans visible in
    result names (render diff vs unbolded, or rich-text assert); `zzz` →
    `NO MATCHES · “zzz”`; offline matches dimmed with last-seen.
12. Esc ladder: clear → collapse → blur (stub-focus asserts); `✕` clears
    only; Ctrl+F reveals+focuses; reopen clears+collapses.
13. Keyboard: ↑ from field focuses first result; ↑/↓ cycle; Enter on
    candidate logs `exit-set`; Enter on plain row no-op.

**States (M2/M5/M6/P\*)**

14. Section label: `ONLINE` T4 + `19` bold tnum + hairline ≥half row width.
15. Fold: with an overflowing list at scroll-top, the lane's bottom 10px
    shows the fade overlay AND ≥4px of a clipped row (partial glyphs).
16. All-offline fixture: aggregate line present; offline rows visible
    (auto-expanded); **no empty vertical band >40px** in the lane
    (projection scan between first and last content).
17. Health fixture: block border+bg tint present; warning text glyph-peak
    contrast ≥4.5:1 measured on the fixture crop; `HEALTH · 2` header;
    `⚠` marks present on route-advertising rows (watertower) and absent
    otherwise.
18. Footer: freshness matches `^\d+s ago$`; stale variant on stale
    fixture; rightmost footer ink ends ≥0.8·gu from popup right edge;
    `Disconnect` present+enabled when gate on, absent when gate off.
19. Offline toggle copy byte-identical; `exit` role icon survives
    collapse; `use exit` never on offline rows.

**Regression**

20. Light Breeze screenshot: all slots legible, tint/strip readable, no
    white-on-white (sample 6 points); scale-2 pass for slot alignment.
21. `git diff` on the compactRepresentation block: empty. Chip counts ===
    lane counts on every fixture.
22. All four test files pass unchanged; `tools/check_qml.py` clean;
    metadata 0.6.0 + README updated in the same commit.

---

## 21. Risks

| Risk | Mitigation |
|---|---|
| `stop` lives on a row that may be scrolled out of view | Tinted row is the loudest object in the lane (Von Restorff); strip names the host; search finds it in 2 keystrokes. If the user reports hunting, add a strip-level `stop` in v0.7 — the strip's right side is reserved by design. |
| Strip appear/disappear shifts lane content 28px on engage | Ledgered (§18.3); frame law intact; shift is the operation's feedback. Revert path: render strip in none-mode at 28px with the direct fact (one-line change). |
| Rich-text bold marking adds per-row cost on 40-peer tailnets | Marking runs only in search mode over `searchResults` (≤ a few rows); regex-escape + greedy scan is O(name × tokens). Negligible; measure in harness anyway. |
| `Text.RichText` + elide interplay (elide unsupported with RichText) | If elide is required (name > 270px zone), fall back: plain text + elide when the marked name would exceed the slot; bolding is dropped for that row only. Rule: never overflow, never wrap. |
| Auto-expand surprises a user who explicitly collapsed offline | Override applies only while online==0 and is described in the aggregate line ("showing all offline"); toggle still works; resets on popup close. |
| Route-warning heuristic marks a peer the warning isn't about | Tooltip states the basis; marks only appear for route-advertising peers when a route-class warning is live — the honest superset. |
| ACTION slot reserve costs 164px of name width on plain rows | Name zone remains 270px ≈ 37ch; census hostnames max ≈ 12ch. If long DisplayNames appear, IDENTITY elides — by design. |
| Breeze Button min-height floor (§W-19 carried) | Explicit 1.4·gu height + tight padding; documented exception path carried. |
| Light-theme `highlightColor` tint visibility | Tint at 0.12 over light surface is subtle by design; state is carried by `EXIT NODE` text + icon + `stop` button — never tint alone. |

---

*Spec ends. Built from: vault audit §7 (15 defects), PIL-measured as-built
geometry/contrast on the five harness fixtures, UX-SPEC-V5.md, the as-built
QML, and the Clearvoice brief discipline. Every changed string is in the
§V6-23 delta table; everything unlisted carries from V5.*

