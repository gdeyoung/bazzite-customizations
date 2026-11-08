# UX-SPEC V8 — Omarchy-layout rebuild (owner directive 2026-11-08)

Owner verdict on v0.7: "better, but still not there. Need to have toggles for things.
Some of the text is being cut off because the pop-down box isn't wide enough. Look at
the original tailfin design from Omarchy and build it based on that. I really liked how
that one's laid out. It's not perfect. It needs more iteration too. And you can use the
design language that we've been building for apps on it."

Sources of truth:
- Omarchy original: gdeyoung/omarchy-tailfin @ 05fdbd7 (scratch clone), Panel.qml 1629 ln
- preview.png vision read (layout DNA extracted 2026-11-08)
- Fleet Design Language v2 (skill: fleet-design-language) — structure laws, toggle/control patterns
- Trayscale grammar kept where it already won (search, detail page, offline fold)

## V8-1 Layout DNA ported from Omarchy (the law)

1. **Tabs, title-case, text-only, always visible** — CONNECTION · EXIT NODES · MACHINES
   (Omarchy: Connection · Exit Nodes · Mullvad · Machines; Mullvad not a plasma tab —
   mullvad exit nodes list inside EXIT NODES as today). Renames: DEVICE→CONNECTION,
   PEERS→MACHINES. Active tab = raised rounded fill + bright text (v0.7 cells, retitled).
2. **Two-line rows everywhere** — primary line bright (name), secondary line dim
   (explanation/status). NO multi-column grids. The v0.7 6-column PeerRow (dot|name|
   addr|os|conn|role) is RETIRED — it is the text-truncation machine.
   Row anatomy (Omarchy InfoRow/ExitNodeRow/MachineRow): [glyph] [name / sub] [right rail].
3. **Right-rail controls on one vertical line** — toggles/radios/actions share the same
   right edge x; scan line for the eye.
4. **Caps section headers** — small, dim, letter-spaced (KEEP v0.7 treatment):
   THIS DEVICE / HEALTH / PREFERENCES / ROUTE ALL TRAFFIC THROUGH / TAILNET EXIT NODES.
5. **Hero card on CONNECTION** (PanelHero): status dot + self name + state phrase +
   **ToggleSwitch** (up/down) sitting right after the text block, NOT pinned to the far
   edge (preview.png: "toggle follows the name directly"). Busy state while op in flight.
6. **Footer summary on MACHINES**: "N online · N offline — hidden" + version. Omarchy
   has this; v0.7 folded it into the pinned header — move to footer strip.
7. **One accent meaning** — accent color = active/selected/enabled ONLY. Resolved from
   the Plasma theme (KDE accent), never hardcoded (fleet DL color law; host-first
   resolution). Status colors via theme (positive/warning/negative).

## V8-2 Toggles (the headline feature)

Real switch toggles, fleet-DL spec: horizontal pill track ~46×26 px, thumb circle,
checked = accent track + white thumb right; unchecked = theme-track + thumb left;
disabled = tint bg + dimmed (never zero-opacity); busy = 40% opacity pulse-less dim +
no input. NO on/off text labels in the switch.

| # | Toggle | Where | Op (Control.js) |
|---|--------|-------|-----------------|
| T1 | Connect/Disconnect (hero) | CONNECTION hero | existing `up`/`down` |
| T2 | Accept routed addresses | CONNECTION › PREFERENCES | new `pref-set --accept-routes` |
| T3 | Accept DNS | CONNECTION › PREFERENCES | new `pref-set --accept-dns` |
| T4 | Shields up | CONNECTION › PREFERENCES | new `pref-set --shields-up` |
| T5 | Allow LAN access (visible only when an exit node is set) | CONNECTION › PREFERENCES | new `pref-set --exit-node-allow-lan-access` |

- PREFERENCES toggles carry label + one-line dim description (Omarchy lines 743-782):
  T2 "--accept-routes: use subnet routes advertised by peers" · T3 "--accept-dns: use
  the tailnet DNS configuration" · T4 "Block incoming connections from the tailnet" ·
  T5 "While using an exit node, reach local devices directly".
- Each row: switch right rail, label/description left, full-row click target.
- Optimistic check + revert on failure via prefs re-probe (endControlOp already re-probes).
- Single-flight: one pref op at a time (`ctlBusy` gate, §T-2 law).
- **Control.js law preserved**: `pref-set` op allowlists exactly the four flags above;
  argv = ["tailscale","set","--flag=true|false"]; any other flag string yields null.
  No free-form argv path opens.

## V8-2b Clipboard (owner ask 2026-11-08: "can't even highlight to copy")

Trayscale parity, two layers:
1. **Selectable values** — every address/DNS value (detail IDENTITY rows,
   CONNECTION › THIS DEVICE rows) is a readOnly `selectByMouse` TextField;
   the v0.7 Label+I-beam could never actually be selected.
2. **One-gesture copy buttons** — MachineRow right rail (IP), detail
   IDENTITY rows (dns/ipv4/ipv6), THIS DEVICE rows. Wired to
   `ctx.copyToClipboard(text)` → `Control.clipboardArg` (CLOSED charset
   `^[A-Za-z0-9.:-]+$`; anything else yields null — shell metachars are
   structurally impossible) → existing read-only exec engine → `wl-copy`.

## V8-2c Mullvad exit selection (owner ask 2026-11-08: "if I have Mullvad
exit nodes turned on … select the Mullvad exit point")

EXIT NODES tab: candidates split by `Model.isMullvadPeer` (mullvad.ts.net
suffix) into TAILNET EXIT NODES + MULLVAD REGIONS sections. Mullvad rows
are PickerRows firing the SAME allowlisted `exit-set` op (target =
node DNSName); selected state matches `status.activeMullvadExit`.
Filter TextField appears when >8 regions (Omarchy parity). The section
renders only when mullvad nodes exist — add-on off = hidden, like Trayscale.

## V8-3 Width & geometry

- Frame width 34·gu → **40·gu** (~720 px @1×). Height law unchanged: min(38·gu, 0.9·avail).
- Body horizontal padding ~1.2·gu; inter-section gap > intra-section gap (Omarchy feel).
- Row heights: hero card ~3.4·gu; two-line list rows ~2.9·gu; toggle rows ~2.6·gu.
- Elide law: name elides with fixed px budget; sub line elides; horizontal scroll OFF
  (fleet DL overflow law). Address/IP strings never wrap mid-glyph (tnum where numeric).
- EXIT NODES rows get the Omarchy radio treatment: active node row = tinted card fill +
  right-rail radio dot (visual cousin of the toggle rail), one-gesture apply (§T-4 kept).

## V8-4 Tab contents

**CONNECTION** (was DEVICE): hero card (T1) → action/error line → THIS DEVICE (two
InfoRows: os+self name/DNS · self IP + "N of M machines online", copy buttons) →
HEALTH (list, acknowledge-style dim, no button — plasma has no ack op) → PREFERENCES
(T2–T5 toggles) → READ-ONLY (key expiry, advertised routes — the non-toggle facts).

**EXIT NODES**: state card (routing pill grammar kept) → ROUTE ALL TRAFFIC THROUGH
caps header → None (direct) two-line row → Suggested row (when advertised) → TAILNET
EXIT NODES caps header → node rows (name/IP two-line, active = tinted). Search stays
in MACHINES only (Omarchy puts search on Machines/Mullvad, not exit).

**MACHINES** (was PEERS): search row → pinned count header → two-line rows
[glyph | name + "role · ↓rx ↑tx" or "os · offline" | right rail: copy button] →
offline fold → footer strip "N online · N offline — hidden · v0.8.0". Row-click →
detail page (StackView push/pop kept as-is; detail page unchanged this pass except
width relaxation).

## V8-5 What does NOT change

- PopupShell chrome discipline (fillHeight law), StackLayout tab container, hand-rolled
  tab cells (PC3.TabBar/SwipeView still banned), fresh-open tab reset, search-over-all,
  rate derivation in main.qml, Model.js/Control.js purity (argv allowlist), harness
  fixture matrix, gallery-per-iteration, safe-restart install law.

## V8-6 Verification gates

1. node --test 69+ (new: pref-set allowlist accepts 4 flags + rejects others; ToggleRow
   composition locks; tab-title locks CONNECTION/EXIT NODES/MACHINES).
2. Harness v8: ≥6 states — connection-tab (hero+toggles), exit-tab, machines, machines
   search, detail, offline-fold-expanded — 15/15 pixel pairs distinct, GEO unique,
   QML-ERR 0. Fixture matrix: norm19h, norm19, zero19, gateoff, LIGHT=1, SCALE=2.
3. Pixel audit: two-line row pitch ≥ 2.9·gu; no ink at frame right edge (no clipping);
   toggle track present at expected rail x (scan for ~46×26 accent blob when checked).
4. Text-truncation check: longest fixture peer name + IP renders fully at 40·gu (measure
   elide ellipsis absence on top rows in norm19h shot).
5. CC technology-architecture critique at end (council bench per cc-trigger scoping).
6. Gallery v0.8 section + README Verified section + commit + install via safe-restart.

## V8-7 File plan

- NEW `contents/ui/ToggleRow.qml` (label+desc+Switch right rail, busy/disabled states)
- NEW `contents/ui/HeroCard.qml` (status dot, name, phrase, T1 switch)
- REWRITE `PopupShell.qml` (tabs/retitles, 40·gu, footer strip on MACHINES)
- REWRITE `DeviceTab.qml` → `ConnectionTab.qml` (hero, prefs toggles)
- REWRITE `PeerRow.qml` → `MachineRow.qml` (two-line, right rail copy btn)
- REWRITE `PeersTab.qml` → `MachinesTab.qml` (footer, retitled sections)
- PATCH `ExitTab.qml` (two-line rows, caps headers, tinted active)
- PATCH `Control.js` (pref-set op), `main.qml` (tab ids/rename wiring, prefs→toggles)
- DELETE nothing else; `metadata.json` → 0.8.0; tests/port.test.js v8 locks.
