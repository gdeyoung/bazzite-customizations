# KDE Port Roadmap — the Omarchy plugin suite on Bazzite

Decision 2026-10-26: build ALL ports as code-complete artifacts on branch
`kde-ports-batch`; install nothing until the owner is back at the tower.

**2026-11-26: `kde-ports-batch` is merged into `master`.** `master` is now the KDE
plugin suite (Foyer launcher, Hermes KRunner, nine plasmoids, keyboard shortcuts,
harness + tools, docs) and is the default branch on GitHub. New work branches off
`master`; `kde-ports-batch` is kept for history only.

## Status — tree versions and the live tower install, both verified 2026-11-26

"Tree" = `metadata.json` on `master`. "Installed" = `~/.local/share/plasma/plasmoids/`
on the tower, byte-compared against the tree. Where they differ, the **tree is the
newer copy** (the installed copy simply has not been re-installed since); nothing on
disk is ahead of the repo.

| Omarchy source | KDE target here | Tree | Installed on the tower | Notes |
|---|---|---|---|---|
| omarchy-sysmon | `plasma-sysmon/` | v0.7.0 | v0.7.0 — only `install.sh` differs (installed copy predates the no-restart sweep) | v0.7/v0.8 redesign DONE: fixed 960×640 frame, real process manager, Hardware table, unified type scale |
| omarchy-foyer (AI lanes) | `krunner-hermes/` | v0.8.1 | v0.8.1 — code byte-identical | DBus runner: `ai <q>` → LiteLLM answer, `hr <task>` → hermes -z turn; UX-spec'd (UX-SPEC.md), unit-tested, harness-gated, live-bus verified |
| omarchy-foyer (launcher) | `foyer-kde/` | — | installed — `foyer.service` active, files byte-identical | LayerShellQt overlay daemon, Meta+Space; design of record CONVERGED-DESIGN.md. Data lanes are a static snapshot — live wiring (.desktop splice, ICMP fleet probe, AI lane) is the open work |
| omarchy-weather | `plasma-weatherx/` | v0.1.0 | v0.1.0 — byte-identical | keyless Open-Meteo + Esri/RainViewer radar, pinned places; placeholder coords only in repo |
| omarchy-timepiece | `plasma-timepiece/` | v0.1.0 | v0.1.0 — only `install.sh` differs | center slot (replaced the stock clock; config kept for rollback); popup width-authority fix; harness-verified at scale 1 + 2 |
| omarchy-tailfin | `plasma-tailfin/` | v0.8.0 | v0.8.0 — only a gallery timestamp differs | v0.8 Omarchy-layout rebuild (CONNECTION · EXIT NODES · MACHINES), real toggles, Mullvad exit regions; control surface stub-only — first real op is the user's |
| omarchy-driveway | `plasma-driveway/` | v0.1.0 | not installed | engine byte-identical (sha256); poll-only v0.1, wizards → config |
| naolselemon/mosaic (3rd-party, MIT) | `plasma-mosaic/` | v0.1.0 | not installed | engine vendored byte-identical (ledger in PORT-NOTES.md); 145/145 tests; real-HOME E2E 28.6 GB / 22 apps |
| omarchy-timemachine | `plasma-timemachine/` | v0.1.0 | not installed | engine sha256-ledgered, 24/24 tests; 5-tab popup |
| omarchy-ready-room | `plasma-readyroom/` | v0.1.0 | not installed | gc-* sha-identical; read-only probes live-run OK; needs gpu-screen-recorder (absent) for replay |
| — (KDE-native) | `plasma-stocktick/` | v2.0.0 | v2.0.0 — installed copy LACKS the `seedMarkets()` popup-seed fix | Yahoo keyless quotes chip + watchlist + portfolio; checker 0/0, live-API verified |
| — (KDE-native) | `plasma-panelpad/` | v1.0.0 | v1.0.0 — byte-identical | invisible fixed-width panel spacer |
| — (KDE-native) | `keyboard-shortcuts/` | v2 | n/a (script) | hermes-keys.sh: Meta+Space/Return/H/Shift+H; `[services]` groups, /App-query preloads; no remapper needed |
| omarchy-clearvoice | **clearvoice-core** (separate repo) | separate track | — | KDE frontend = Plasma plasmoid + PipeWire recorder in `clearvoice-core/plasmoid`; the Omarchy frontend stays `omarchy-clearvoice` |
| omarchy-game-center | — | skip | — | subsumed by plasma-sysmon (GPU VRAM/GTT already there) |
| omarchy-appdock | — | skip | — | reverse port; it *is* the KDE task manager on Hyprland |
| omarchy-ultrawide-bar | — | skip | — | KDE panel does partial-width/auto-hide/floating natively |
| omarchy-displayplus | — | skip | — | KScreen KCM native; hyprmoncfg editor is Hyprland-only |
| omarchy-powercore | — | parked | — | laptop-only (UPower/clamshell); revive if Bazzite goes on a laptop |
| omarchy-armoury | — | parked | — | asus_armoury kernel module; desktop has no ASUS hardware |
| omarchy-audiofx | — | parked | — | FX engine not installed on Omarchy yet; revisit after engine ships |

Install-day follow-up for the four widgets whose installed copy trails the tree
(sysmon, timepiece, stocktick, tailfin): `kpackagetool6 -t Plasma/Applet -u <repo-dir>`
then swap the widget instance — no shell restart.

## Redesign queue (post-ship improvements)

| Target | Scope | State |
|---|---|---|
| `plasma-sysmon` v0.7/v0.8 | **Full audit + UX review + redesign** (assigned 2026-10-30): fixed 960×640 frame, real process manager (search/sort/kill + footer action bar), neofetch Hardware table, unified type scale. Harness-gated at scale 1 + DPR 2 both versions; shipped v0.8 (`5210b4f`, installed 2026-10-30 15:31). | **DONE** |
| `plasma-stocktick` polish (banked from UX review) | QML Text axis labels outside Canvas, runtime axisW via FontMetrics, tile strip 62→64, chart padT 8/padB 20 | backlog (optional) |

Meta sources: `omarchy-recipes` (discipline) and `omarchy-skills` (agent
skills) have no KDE artifact — their KDE equivalents are this repo + the
`plasma-plasmoid-development` skill.

## Verification ladder (every port)
1. `tools/check_qml.py <dir>` → 0 errors (static).
2. Probe executes once → strict JSON (read-only probes only).
3. Node suites: run with EXPLICIT file args (`node --test tests/model.test.js`) —
   directory args silently run 1 phantom failing test on this node.
4. Install-day: heartbeat advances, journal clean, screenshots, panel placement
   (`references/panel-widget-placement.md` recipe in the skill).

## INSTALL PUNCH LIST (run only when at the tower)
Per widget, after review merge:
```
cd ~/work/bazzite-customizations/<widget>
kpackagetool6 -t Plasma/Applet -i .            # or -u if upgrading
# NO plasmashell restart (banned: it bounces the panel mid-session; the shell
# reloads updated packages itself). New widget: add it via the scripting API
# (skill plasma-plasmoid-development, "Panel placement"). Upgrade: swap the
# instance — widgetById(<id>).remove(); panel.addWidget("<pluginId>") — and
# clear the compiled-QML cache first: rm -rf ~/.cache/plasmashell
# verify: /tmp/<id>-hb.json advances; journal clean; screenshot chip+popup
```
KRunner runner additionally:
```
cd ~/work/bazzite-customizations/krunner-hermes
./install.sh            # copies daemon+desktop+unit, writes config (asks/args)
systemctl --user enable --now hermes-runner.service
systemctl --user restart plasma-krunner.service
# Alt+Space → "ai ping the litellm proxy" / "hr status of the nas backup"
```
Rollback per widget: `kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.<id>`;
runner: `./uninstall.sh`.

## CENTER-BAR LAYOUT (install day) — the owner's Omarchy arrangement
Target: **StockTick | timepiece clock (center anchor) | weatherx** — the
Omarchy center group (host-11 used tmn73.calendar centered; timepiece is our
richer clock). Two methods, both verified paths:
1. Interactive: panel Edit Mode → drag timepiece to the middle until it pins
   to the centered group; drop StockTick just left, weatherx just right.
2. Scripted: `AppletOrder=` edit per
   plasma-plasmoid-development/references/panel-widget-placement.md — stop
   plasmashell, rewrite order (StockTick;timepiece;weatherx within the
   center group) + physical groups, start, re-verify via evaluateScript
   geometry.x ascending.
Current panel reference (pre-change snapshot 2026-10-26): containment 2,
includes com.gdeyoung.plasma.sysmon + stock weather widget (id 7/21) — the
stock weather widget is removed/replaced by weatherx on install day.
