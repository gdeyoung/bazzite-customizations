# PRODUCT.md — Foyer for KDE

## One sentence
A keyboard-first, fan-out launcher overlay for KDE Plasma 6 that unifies Foyer's
browsable menu tree with the Hermes fleet lanes in one instantly-open native
window — the thing KRunner's rows-only protocol could never be.

## Owner / scene
Greg, gdtower (Bazzite, Plasma 6.7.5, Qt 6, Wayland/KWin, Breeze Dark,
Super+Space muscle memory). Summoned dozens of times a day, hands never leaving
the keyboard, on a 2560×1440 display in a dim room. Open→action budget: under
two seconds; open→paint: under 150 ms.

## Mode: Operate
A tool surface. Scanability, consistency, native Plasma expectations, and the
real usage scene outrank expression. Brand lives in precise details.

## Why it exists (defect backlog — every item is a proven KRunner limit)
- 15-row render law (Milou `limit: 15`, shared across categories) → native
  window renders unlimited rows.
- Rows cannot nest → inline fan-out trees, the entire point of Foyer.
- Drill = async re-drive (~2 s) → instant in-place navigation, Backspace pops.
- Subtext renders only on the selected row → metadata always visible.
- Protocol cannot rewrite the query → the app owns the box, the tree, the chips.
- KRunner closes on Run → window persists; AI answers render in-place, tasks
  report progress in-place.
- No settings UI → proper settings (chips, menu-on-start, accent, lanes).
- Single-runner priming poison (§L-17) → gone; there is no other runner.

## Must stay true (pinned, do not relitigate)
- Owner directive L-16: top level = foyer's branches, they "fan out just like
  foyer does"; NEVER loose leaf apps on root.
- Root branches (r6): Apps · Settings · System · Update · About, plus the
  Hermes lanes as branches (AI, Fleet, Snippets, Help) — one tree.
- Lane grammar semantics: `ai`/`hr` questions-tasks, dictation folds
  ("ask hermes about X" → `ai X`), `ssh <alias>`, `;snippet`, handoffs,
  `ai model` switch, layered help. Recents show questions, never answers.
- Data sources: omarchy-style JSONC menu (+ user extension wins per-id),
  live .desktop splice under Apps, Kickoff favorites mirror (read-only),
  KCM list from kcm*.desktop, recently-used.xbel for recents.
- Safety: launch by desktop-id via kioclient (never Exec strings);
  destructive rows name consequences ("CLOSES OPEN APPS"); harness_mode stubs
  all power/update handlers.
- Visual world: Breeze Dark native (established world — inherit, don't invent
  a foreign one). Kirigami/KDE house style of the fleet's plasmoids.

## Success looks like
The daily driver on gdtower, retiring the KRunner `apps` lane as the primary
surface. Feels like Plasma's own surface — a KRunner that grew up.

## Wrong-feel (would make polish feel wrong)
Web-app-in-a-window chrome, macOS clone aesthetics, gamified motion,
animation for its own sake, telemetry, loose apps on root.

## Assumptions (inferred, labeled)
- Deliverable now is the DESIGN (iterated, critiqued, gallery-documented) with
  an interactive hi-fi prototype; native QML implementation follows as its own
  build from this spec.
- Accent: Breeze default blue (#1e92ff DecorationFocus in kdeglobals) unless
  the owner changes it.
- Prototype medium: self-contained HTML at exact launcher dimensions, no CDN,
  system fonts — it is a design artifact, not the shipped tech.
