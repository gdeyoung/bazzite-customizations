# DESIGN-BRIEF — Foyer for KDE, iteration loop v1 (amended R1.1 after research)

**Fidelity target (research-verified):** "Foyer" = the owner's own fork
`gdeyoung/omarchy-foyer` v0.4.2 (QML/Quickshell, 2314-line Runner.qml), itself
a fork of Omarchy's `omarchy.menu`. The KDE port reimagines THAT, not stock
Omarchy. Digest: scratch/foyer-kde/research-foyer.md (113 lines, sourced).

Surface: launcher overlay, ~920×640, centered, KWin blur behind (prototype:
HTML at exact dimensions, self-contained, system fonts, no CDN). Mode: Operate.
Established world: Breeze-family dark (host scheme = Vapor; its color VALUES
are identical to the Breeze Dark table below — verified) / Kirigami house.

## Implementation contract (R1.2 — USER-SPACE ONLY; no rpm-ostree, ever)
Standalone resident daemon in pure user space: `/usr/bin/python3` + PySide6
(system rpm 6.11.2, links the SAME Qt as the desktop) hosts FoyerRoot.qml
inside FoyerWindow.qml — a LayerShellQt Layer.Top surface via the
org.kde.layershell QML module shipped on the host (no compilation, no
devel packages, no layering). KWin assigns the layer surface the full
output; the 920×640 card centers inside it (fullscreen-launcher geometry,
whole-screen keyboard coverage) — harness-verified 2026-11-07. Blur via
KWindowEffects is DROPPED for v1 (needs PyKDE, absent; the 0.96α card
carries the design alone; revisit only if the loss is visible in daily
use). Warm start = Type=dbus systemd user unit + dbus-activation file in
~/.local/share/dbus-1/services (krunner's pattern) → summon = show() on a
warm engine. Hotkey = .desktop + kglobalaccel [services] (fleet precedent:
hermes-menu.desktop holds Meta+Space today; install takes it over ONLY
via an explicit --take-hotkey flag — never silently). Theme via
Kirigami.Theme/KColorScheme at runtime (verified live: accent #569fcc,
pos #7ea64b, neg #da4453). Also verified as a Plasma applet package
(harness/package) — the same FoyerRoot runs in both hosts; the applet path
is kept for gallery/QA, the daemon is the product.

## Foyer fork DNA (port these verbatim — the product's soul)
- Caret flow: typing keeps caret in the box; ENTER = top hit; ↓ enters
  results; ↑ from first row returns to box. Esc: clear query → back a level
  → close at root. Backspace/Left-on-empty = back.
- Root on open (menu-on-start default ON): the root tree as a captioned
  group + Favorites start group (★, Ctrl+P pins, 30 max, Kickoff mirror on
  KDE) + optional Recents group. NO loose ungrouped leaf rows on root
  (L-16 spirit, fork-compatible reading).
- One-line rows: label + dimmed detail INLINE on the same line (detail
  elides first). Mono type identity (fork uses monospace; KDE port: mono
  row labels, sans for prose answers).
- Category caption column (default ON): left ~120px right-aligned captions,
  opacity .6, group divider INSIDE the first row of each group.
- Tiered substring search (+ optional fuzzy ≥3 chars, 120ms debounce),
  prefix-claimed sources (ai: > kill cb ; : ssh = web: loc:), grouped
  results, web search FALLBACK ONLY.
- Card mechanics: frozen top edge on first keystroke (grows downward only),
  70% screen cap, mid-row fold with 55% row peek as the scroll affordance.
- Ctrl+1..9 quick-launch hints (rows 0-8, opacity .45) · Ctrl+P pin ·
  Ctrl+S Settings (in-launcher: width/rows/density/font/opacity/radius/
  border/accent/location 6-way/fuzzy/categories/menu-on-start/hints/
  per-source toggles) · Ctrl+, Sources · F1 Help · Delete = uninstall
  (confirm dialog).
- Guards (when/checked) batched async → Install/Remove state, ✓ rows.

## Pinned (do not relitigate)
1. Root = branches ONLY that fan out "just like foyer" (L-16). Never loose
   leaf apps on root — amended reading per fork research: captioned start
   GROUPS (Favorites ★, Recents) are not "loose"; ungrouped leaf rows are.
2. Root branches: Apps · Settings · System · Update · About + Hermes lanes
   (AI · Fleet · SSH · Snippets · Help) as tree branches (L-18 r6 extended).
3. Destructive rows name consequences in subtext ("CLOSES OPEN APPS") —
   subtext IS the confirmation (r6 verdict).
4. Recents show questions, never answers. Errors never cached.
5. Data: JSONC menu tree (+ext wins per id), live .desktop splice (250 apps /
   12 cats, real extract in real-data.json), Kickoff favorites mirror
   (read-only), 83 KCMs, recently-used recents.
6. Breeze Dark tokens only (kdeglobals 2026-11-07): bg #232629, raised
   #31363b, text #fcfcfc, inactive #a1a9b1, accent #1e92ff, hover #3daee9,
   neg #da4453, pos #27ae60, neutral #f67400. Base type 17px (owner portal
   directive). Noto Sans / Noto Sans Mono.
7. Every KRunner §L limit dies by design rule (see defect map).

## Defect map (KRunner constraint → native design rule)
| KRunner limit | Native rule |
|---|---|
| 15-row render law | unlimited rows, real scroll, SHOWING counts still render |
| rows cannot nest | inline fan-out; drill ≤1 frame, Backspace pops |
| ~2s re-drive drills | in-place pane/list swap, 140ms |
| subtext on selected only | subtext always visible |
| window closes on Run | window persists; answers/tasks render in-place |
| no settings UI | settings surface: chips, menu-on-start, density, lanes |
| query not rewritable | app owns box/tree/chips/breadcrumb |
| single-runner priming | no other runner exists |

## Keyboard contract (shared)
Type filters the whole tree · ↑↓ walk · Enter run/drill · Backspace pop
(then clear query) · Esc pop-to-root then close · Ctrl+1..5 branch jump ·
←→ pane/level traversal (variant-specific) · Alt+Enter = row's secondary
action (copy/pin). Every function reachable keyboard-only.

## The dealt hand (concept-seed key 35d933dc, indices 3·7·6)
- **V1 ATRIUM (leads)** — two-pane fan-out browser. Left rail (300px) = the
  foyer tree itself, inline fan-out, live counts; right pane (560px) = lens on
  the focused node: app grid / KCM list / power rows / AI answer card / peer
  tiles. Breadcrumb chips. Signature: the rail IS the menu tree, always warm.
- **V2 FOUR CORNERS** — bento quadrants: APPS ⊕ SYSTEM+SETTINGS ⊕ AI ⊕ FLEET
  as 2×2 raised cards; Tab/arrows jump quadrants; Enter drills a quadrant to
  full (zoom 0.96→1); typing filters globally into one results list.
  Signature: spatial cockpit; each domain has an address.
- **V3 THRESHOLD** — query-first single column: field + sectioned list;
  empty query = foyer root (LAUNCHER/FLEET/SYSTEM groups, branch rows with
  counts); → expands a branch inline (accordion fan-out, indented children
  push down); scope chips when drilled. Signature: KRunner discipline with
  nesting — one flow, zero chrome.

## States (every variant must render all)
empty-root · typed-with-matches · typed-no-match · drill mid-tree · AI
streaming · AI answer ready + actions · task running (progress) · destructive
selected (consequence emphasis) · peer offline (dim + dot) · settings ·
update running. Prototype interactive minimum: walk root, drill one branch
deep, type-filter, no-match state, one AI answer state.

## Convergence plan
Build all three at fidelity → camofox screenshots (dark, real data) →
three-judge critique (requirements / interaction architecture / craft) +
ai-tech council one-shot → converge (raises documented, folded from losing
structures where they win an axis) → v4+ polish iterations to green →
GALLERY.html + DESIGN.md + KDE implementation contract.

## Acceptance checklist (mechanical)
- [ ] No loose leaf app on root in any variant/state
- [ ] Every branch row shows a live count
- [ ] Every destructive row names its consequence, always visible
- [ ] ≥40-row list renders (scroll, not truncation)
- [ ] Every drill is in-place (no window swap), Backspace pops
- [ ] Keyboard-only path to: launch app, open KCM, ask AI, run power action,
      settings, close
- [ ] All colors from Breeze token table; base 17px; mono only for grammar
      (counts, kbd, lane prefixes, questions)
- [ ] Zero external requests; fonts system; icons authored SVG one weight
- [ ] The 8 defect-map rules each visibly true in the prototype
