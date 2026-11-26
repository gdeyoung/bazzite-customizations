# KDE Plugin Simplification + UX Pattern Upgrade — Synthesis Report

**Date:** 2026-11-04 · **Method:** 4 parallel research dossiers (171 sources), hinge claims
independently verified on this host (dnf repo probes, `strings` on libkwin 6.8.2, binary inventory).
**Dossiers:** `01-kde-devex-simplification.md` (56 src) · `02-ease-vectors-quickshell-hyprland.md` (35) ·
`03-widget-ux-pattern-bank.md` (39) · `04-dashboard-ux-evidence.md` (41).

---

## 1. The answer, in one paragraph

The Quickshell/Hyprland ease advantage is **not a framework gap — it is ~12 compounding loop-shorteners,
and KDE already wins 6 of them** (zero-build QML packages, KConfigXT schema→auto-UI, one-click store
distribution, uninstall symmetry, per-monitor placement, sandbox-safe iteration). The genuine gaps —
sub-second save→see reload, edit-time error surfacing, one-command scaffolding, LSP wiring — are **all
closable fleet-side in ≤1 day each, with zero dependency on upstream KDE**. Upstream hot-reload into a
live plasmashell does not exist anywhere (verified: Qt never re-evaluates loaded QML;
`QML_DISABLE_DISK_CACHE` is a stale-cache fix only). The KDE-native parity loop is
`plasmawindowed` (already on this host) / `plasmoidviewer -a <folder>` (needs one plasma-sdk layer) —
which is exactly how KDE's own widget-docs maintainer iterates. And the bridge question resolved
favorably: **KWin has implemented layer-shell since Sept 2020** (verified in this host's libkwin
symbols), and **Quickshell is in stock Fedora 45 repos** — so Quickshell companion chrome is a
one-command, protocol-viable lane for the things plasmoids fundamentally cannot do (process spawning).

## 2. Premise corrections (things we believed that are now known false)

| Prior belief | Reality (source) |
|---|---|
| Quickshell not in Fedora repos; would need layering/build on Bazzite | **FALSE** — `quickshell-0.2.1^git20260209-5.fc45` in stock Fedora 45 (verified live: dnf on the tower); COPR `errornointernet/quickshell` carries 0.3.2 |
| KWin layer-shell support is new/uncertain | **FALSE** — implementing commit `f8dd1c61` landed 2020-09-03 (Plasma 5.20 era); hardened continuously through 2026 (keyboard interactivity, reserved-space precedence, popup integration tests); symbols confirmed in host libkwin 6.8.2 |
| `hyprland/hyprland-plugin-template` is the on-ramp | That repo **404s**; real template is hyprland-community, stale since 2023. Actual on-ramp: read PluginAPI.hpp + copy a small official plugin |
| hig.kde.org is the widget UX reference | It **redirects to a 2025 topic rewrite** at develop.kde.org/hig with **no plasmoid-specific pages**; KDE's px type table was retired. Shipped-applet source is the real pattern authority (documented with file:line in dossier 03) |
| Apple "menu bar extras" HIG page governs tray-class design | **Retired** — folded into "The menu bar" + MenuBarExtra API docs |
| HyprPanel is the AGS panel to watch | **Archived 2026-04-27**; successor Wayle is pre-release |

## 3. Recommendations (ranked, worth-it cases only)

### R1 — BUILD the `plasma-dev` loop tool (~1 day, biggest felt win)
`inotifywait`-watch → `kpackagetool6 -u` → evaluateScript remove/re-add (pattern already fleet-proven
on 6.7.5) → journal tail filtered by plugin id, errors printed next to the editor. Plus `plasma-new`
scaffold from `tools/porting-template` (metadata.json + main.qml + config stub + checker pre-wired).
**Worth it:** closes the #1 and #3 ease vectors (save→see, single-tree source of truth + edit-time
errors) for all 12 existing widgets and every future port. No upstream dependency. Skipping this and
migrating frameworks instead would lose KRunner/GHNS/KConfigXT for a worse-positioned ecosystem.

### R2 — LAYER plasma-sdk (and optionally qt6-qtdeclarative-devel) — needs your OK
`rpm-ostree install plasma-sdk` (6.8.2, stock Fedora) unlocks `plasmoidviewer -a <folder>`:
zero-install source-folder runs, `-l topedge -f horizontal` panel emulation, `QT_SCALE_FACTOR=2` DPR
testing, ~1–2s relaunch. Adding `qt6-qtdeclarative-devel` brings qmlls/qmllint → catches
"property value set multiple times"/undefined-property classes at edit time (with
`-I /usr/lib64/qt6/qml`; maintainer-confirmed workflow).
**Worth it:** popup-geometry work currently requires the full harness; plasmoidviewer gives a
seconds-class loop for everything except real panel context. Cost: two standard Fedora packages on an
immutable base — boring, reversible (`rpm-ostree uninstall`). Say go and I'll layer + verify.

### R3 — ADOPT the UX pattern bank (done — apply the punch list next)
The bank now lives in the skill (`plasma-plasmoid-development/references/widget-ux-patterns.md`):
P1–P13 widget patterns + dashboard/live-data rules + the V1–V10 verdict map. Three shipped-rule
corrections with external evidence:
- **V6 refinement (KDE HIG):** row remove controls should be *visible, not hover-only* →
  persistent-muted × that intensifies on hover.
- **V7 classification:** armed-confirm is *stricter than every shipped precedent* (plasma-nm
  disconnects with a single click). Keep it ONLY for blast-radius/slow-recovery actions (VPN kill,
  process kill); instantly-reversible state flips get single-click + state-flipping label.
- **Palette fix (computed, WCAG):** `#f4405c` fails 4.5:1 as small *text* on cards (3.72 on #2a2e35)
  → use `#ff6680` there; green/red luminance separation is only 1.87:1 → glyph+label redundancy is
  mandatory, not optional.
Concrete widget punch list: stocktick — tnum sweep + delta triple-encoding (▲+sign+color) + 3-sig-digit
columns; sysmon — debounce re-sorts ("cpu lazy" pattern), label Irix-vs-Solaris CPU normalization,
flash-on-change 300–800ms; tailfin — persistent-× refinement; all — verdict column leftmost in tables.
**Worth it:** this is the "step up the UX patterns" ask made systematic — future widgets start from
evidence instead of iterating through rejections.

### R4 — BUY Quickshell as a companion lane (selective, not a migration)
`rpm-ostree install quickshell` works today. Use it ONLY where plasmoids are structurally blocked:
**process spawning** (Plasma QML cannot spawn processes — agent HUDs, one-shot CLI surfaces),
free-edge overlays, rapid-experiment chrome. Constraints that stand: no Kirigami/Breeze theme
integration (manual colors), SNI tray duty must stay with Plasma (watcher collision), taskbar/workspace
modules are Hyprland/i3-only. **Worth it:** the Foyer-class "agent integrated into the OS" feel on
Bazzite without abandoning the Homeport principle; it composes with KDE rather than replacing it.

### R5 — SKIP list (recommended against, with reasons)
- **Framework migration** (panel/launcher → Quickshell): loses KRunner, GHNS, KConfigXT; two-launcher
  UX; theme mismatch. Prior Foyer verdict upheld by new evidence.
- **hyprpm-equivalent plugin-manager CLI:** real gap but small for pure-QML widgets (no build step to
  manage). Revisit only if C++ widgets enter the fleet.
- **KWin C++ effects lane:** higher barrier than Hyprland plugins (no ABI guard, full Frameworks
  build) — keep to KWin JS scripts, which reload via `qdbus org.kde.KWin /KWin reconfigure` with zero
  restarts and cover workspace/clients/edges/shortcuts/animations.
- **EWW/AGS/Ironbar/nwg-panel on Plasma:** EWW renders-but-broken (always-on-top, #393 open); the rest
  are untested or wlroots-scoped on KWin. Quickshell is the only candidate that is Qt-native, hot-
  reloading, SNI-capable AND in this host's repos.

## 4. The 12 ease vectors (scorecard)

KDE parity today: zero-build (V1), uninstall symmetry (V6), store/copy-paste adoption user-side (V7),
config-schema→UI (V8, **a KDE win** — Quickshell has no config-UI concept), per-monitor placement
(V10, imperative), sandbox iteration (V12, DIY = our harness).
Genuine gaps: **hot reload (V2), edit-time errors (V4), plugin-manager CLI (V5), LSP wiring (V11),
developer snippet culture (V7 dev-side)**. All but V5 closable by R1/R2/R3 in ≤1 day each.

## 5. UX headline upgrades (dossiers 03+04)

- Popup IA decision is **data-shaped, now with rules**: homogeneous collections → flat sectioned list
  + header search (plasma-nm shape); heterogeneous control surfaces → 2–4 tabs (HIG ceiling: tabs
  "scale poorly beyond 4 or 5"); pick-and-inspect → master-detail, one back level (systemtray).
- **Glance unit = number + trend + verdict** per tile; one preattentive channel per alert dimension;
  verdict column leftmost (F-pattern, 232-user eyetracking).
- **Sparklines by Tufte's own numbers:** band height ≈ text x-height (12–20px @17px base), aspect ~6:1,
  bank 45°, end-dot + printed current value, shaded normal-range band, never axes/ticks.
- **Live-surface mechanics:** tnum (`font.features: ({"tnum": 1})`, Qt ≥6.6) kills digit jitter;
  1–5s refresh reads live, <500ms table repaints read twitchy (btop maintainer: ≥2000ms for meaningful
  slopes); flash changed cells 300–800ms (change blindness is why); debounce re-sorts.
- **Empty/stale discipline:** per-cause PlaceholderMessage (plasma-nm's 5-state matrix is the model);
  "—" placeholder rows are Grafana's own null default; one dead source fails only its tile; "as of"
  stamps everywhere (our V8 is fleet-original — keep it, pair STALE with a refresh affordance).

## 6. What this changes going forward

1. Widget dev loop: R1 tool + R2 layer = Quickshell-class iteration on KDE, verified against how KDE
   upstream itself iterates.
2. Every new widget design pass starts from the pattern bank (P1–P13) — the UX-agent gate consumes it.
3. Quickshell becomes a sanctioned *companion* lane for agent-facing chrome that needs process spawn /
   fast experiments — not a replacement surface.
4. Skills updated and pushed: `plasma-plasmoid-development` (fast-iteration section + UX bank pointer
   + new `references/widget-ux-patterns.md`), `omarchy-plugin-porting` (premise corrections + bridge
   verdict), `design-systems-nux` (pointer). Vault note: `fleet/research/kde-plugin-simplification-2026-11.md`.

## 7. Verification status

Host-verified this session: quickshell/plasma-sdk/qt6-qtdeclarative-devel in F45 repos (dnf);
`zwlr_layer_shell_v1` symbols in /usr/lib64/libkwin.so.6; kpackagetool6/plasmawindowed/
plasma-interactiveconsole present; qmlls/qmllint absent until -devel layered. NOT yet verified:
plasmoidviewer behavior on this host (blocked on the layer), Quickshell-on-Plasma behavior end-to-end
(protocol-proven, upstream-unendorsed — treat as experiment), plasma-sdk RPM layer size.
Unverified/flagged items in each dossier's gaps section are labeled there.
