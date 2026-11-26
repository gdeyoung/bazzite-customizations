# FOYER for KDE — converged design (v4)

One sentence: **Foyer — the owner's own Omarchy launcher — reborn as a native
Plasma 6 overlay: a stable 12-branch rail that live-previews a content lens,
a field that is also the ask box, and consequences written on every row.**

Provenance: V1 Atrium body (interaction judge: "every branch holds a fixed
screen position") + V3 Threshold grammar (requirements judge: 8/10, best
no-match state) + V2 raises (always-visible consequence subtext, fleet
liveness at root) + verified fork DNA (gdeyoung/omarchy-foyer v0.4.2 —
caret flow, tiered search, caption column, settings page, Ctrl+N hints).
Judge scores R1: V3 8 · V1 7 · V2 4 (V2 structurally blocked on L-16).

## The shape (920×640, LayerShellQt overlay, KWin blur)

- **Rail (300px), 12 stable rows, never scrolls at root.**
  LAUNCHER: Apps 250 · Favorites ★ · Recents · Settings 83 · System 5 ·
  Update · About — FLEET: AI local-fast · Fleet 13↑ · SSH 14 · Snippets ·
  Help. Unselected labels #a1a9b1; selection = #31363b fill + 2px accent
  left edge. Ctrl+1..9 jump (fork parity; Ctrl+0/usage-dynamic noted open).
- **Lens (620px)** live-previews every rail walk — zero-commit browsing.
  Scope trail mono (FOYER / APPS › GAMES / FLEET · 13 UP · 1 DOWN).
  Lists ≤12 = one-line rows (label + inline dim detail, detail elides
  first); >12 = 2-col grid (Settings KCMs, Games). Fold-peek scroll.
- **Field = ask box.** Caret flow (fork): typing keeps caret; ⏎ top hit;
  ↓ into results; ↑ back to box. Esc clears → pops → closes. ⌫ pops before
  clearing. No-match renders an inert `Ask Hermes: <q>` row — **the model
  is never called without an explicit Enter** (council fold #1).
- **AI lane:** ask card → STREAMING (caret, Copy disabled) → ANSWERED
  (Copy = Alt+⏎, Continue in chat, MODEL · local-fast). Answers are
  **read-only text + copy; the AI emits no actions** (council fold #2).
  Recent questions render as questions only; answers never cached.
- **System/Update rows name consequences in subtext, always visible:**
  "closes open apps" in neutral orange on Log Out / Reboot / Shut Down /
  Apply staged deployment; "enter locks now" plain on Lock/Sleep. The
  subtext IS the confirmation.
- **Settings (Ctrl+S) in-launcher** (fork parity): width 420/680/920
  (≤560 collapses rail to the fork's caption column), density 24/28/34,
  opacity, radius, location, fuzzy/categories/menu-on-start/hints,
  per-source toggles, AI endpoint display (source of truth:
  hermes-runner config).

## Craft law (applied, vision-verified)

Tokens from KColorScheme at runtime — never hardcode (host scheme Vapor ≡
Breeze Dark values, verified). Sans for labels/verbs; mono only for counts,
kbd caps, prefixes, hostnames, model ids, scope trail. Flat #31363b tiles +
initials, 1px a1a9b1@30% border — no gradients, no glow, no card nesting.
Two state marks: rail selection = fill + left edge; lens focus = 2px accent
outline, no fill. Hairlines a1a9b1@15–30%. Bottom scroll padding; counts
reconcile with rendered rows exactly. Root lens fits without scroll (38px
rows). Empty states are designed (Favorites/Recents/Snippets show how to
fill them). Streaming ≠ ready.

## Data (all real, gathered this session)

250 apps / 12 categories from the live .desktop scan; 30 of 83 KCMs; 14
SSH aliases from ~/.ssh/config; fleet liveness from an actual ICMP probe
(13 UP, nas DOWN, timestamped); AI config from hermes-runner (local-fast
via aicube:4000, 45s, 700 chars, copy-on-⏎). No lorem anywhere.

## Council verdict (ai-tech, folded)

Ship deterministic first; AI lane gated and explicit. Folded: (1) no
auto-AI on no-match — already the design, now documented as contract;
(2) AI output read-only; (3) injection hygiene — retrieved text renders
inert, never interpolated into prompts; (4) per-branch data contracts:
apps = .desktop watcher, KCMs = static, fleet = probe-on-open, recents =
xbel watch, favorites = kickoffrc watch (empty today — shown honestly);
(5) budgets: deterministic p95 < 100 ms, AI first token < 300 ms, paint
< 150 ms, open→action < 2 s; (6) Ctrl-slot asymmetry noted open.
Rejected (this is a personal fleet tool, not a shipped product): resident
1–3B intent-router/classifier machinery — the fork's proven pattern (one
OpenAI-compatible call to his own LiteLLM) is the whole AI lane.

## Build (research-verified)

Qt6/QML daemon · org.kde.layershell (installed) · KWindowEffects::
enableBlurBehind (PlasmaCore.Dialog's own call) · Type=dbus systemd user
unit + dbus-activation file (krunner's warm-start pattern, sub-150 ms) ·
hotkey .desktop + kglobalaccel [services] (hermes-ask.desktop precedent;
Exec caches at registration, lands next login) · QQuickStyle org.kde.breeze
+ kdeglobals colors · NOT a plasmoid. Build gap: layer-shell-qt-devel +
KF6-devel not yet layered on Bazzite — first native-build task.
Phase 1: deterministic core (everything but AI streaming). Phase 2: AI
lane via hermes-runner prefixes (ai / hr). Phases are build order, not
feature flags — the design ships whole.

## R4 addendum — the user-space build (2026-11-07, supersedes the C++ plan)
The C++ LayerShellQt daemon required rpm-ostree layering (layer-shell-qt-devel,
KF6-devel) — wrong for this host. Rebuilt as pure user space with zero
compilation, verified in the nested-kwin harness the same day:

- **Host**: `/usr/bin/python3` + PySide6 6.11.2 (system rpm, same Qt 6.11 as
  the desktop) → QQmlApplicationEngine → FoyerWindow.qml (org.kde.layershell
  attached properties) → FoyerRoot.qml, unchanged from the applet build.
- **Window**: Layer.Top overlay; kwin assigns the surface the full output and
  the 920×640 card centers inside (measured 916×636 at (242,182) on a
  1400×1000 output) — fullscreen-launcher geometry, whole-screen keyboard.
- **Control**: DBus gdeyoung.foyer (toggle/showUI/hideUI/driveState); hidden
  surface = 0 UI pixels (verified), reshow = byte-identical state.
- **Warm start**: systemd user unit Type=dbus + dbus-activation file →
  first summon starts the daemon, later summons are a warm show().
- **Hotkey**: gdeyoung-foyer.desktop + kglobalaccel [services]; Meta+Space
  currently belongs to hermes-menu — takeover is flag-gated
  (harness/install.sh --take-hotkey), never silent.
- **Dropped**: KWindowEffects blur (PyKDE absent; 0.96α card stands alone).
- **Verified**: 13/13 unique frames, 11 states + hide/show roundtrip,
  fleet 13 green UP + red DOWN dots, system destructive oranges, rail
  38px pitch — same evidence bar as R3.
- Remaining: live-data wiring (.desktop splice, ICMP, hermes-runner AI
  lane), real-session install (explicit go from Greg), dependency-map node
  at install time.
