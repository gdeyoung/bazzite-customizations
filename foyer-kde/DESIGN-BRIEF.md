# DESIGN-BRIEF — Foyer for KDE, iteration loop v1

Surface: launcher overlay, 920×640, centered, KWin blur behind (prototype: HTML at
exact dimensions, self-contained, system fonts, no CDN). Mode: Operate.
Established world: Breeze Dark / Kirigami — inherited, not invented.

## Pinned (do not relitigate)
1. Root = branches ONLY that fan out "just like foyer" (L-16). Never loose
   leaf apps on root.
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
