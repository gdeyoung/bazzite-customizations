# KDE Port Roadmap — the Omarchy plugin suite on Bazzite

Decision 2026-10-26: build ALL ports as code-complete artifacts on branch
`kde-ports-batch`; **install nothing until Greg is back at the tower**. Install
steps live at the bottom as a punch list.

## Status — ALL BUILT 2026-10-26, branch `kde-ports-batch`, nothing installed

| Omarchy source | KDE target here | State | Notes |
|---|---|---|---|
| omarchy-sysmon | `plasma-sysmon/` | **SHIPPED** (master) | v0.6.0, installed + verified |
| omarchy-foyer (AI lanes) | `krunner-hermes/` | **BUILT + live-bus-verified** (ade218d) | DBus runner: `ai <q>` → LiteLLM one-row answer; `hr <task>` → hermes -z turn + notification. Verified on the live session bus without installing. |
| omarchy-weather | `plasma-weatherx/` | **BUILT** (2538283) | keyless Open-Meteo + Esri/RainViewer radar, pinned places; checker 0/0; live API e2e passed (placeholder coords only in repo) |
| omarchy-timepiece | `plasma-timepiece/` | **BUILT** (7c8d515) | Model/zones sha-identical; 37/37 JS tests; timer persists via KConfig |
| omarchy-tailfin | `plasma-tailfin/` | **BUILT** (2009575) | Model verbatim; 22/22 tests; read-only status view |
| omarchy-driveway | `plasma-driveway/` | **BUILT** (d002ff5) | engine byte-identical (sha256), py_compile OK; poll-only v0.1, wizards→config |
| omarchy-timemachine | `plasma-timemachine/` | **BUILT** (76dbee3) | engine sha256-ledgered, 24/24 tests; 5-tab popup |
| omarchy-ready-room | `plasma-readyroom/` | **BUILT** (83f441c) | gc-* sha-identical; read-only probes live-run OK; needs gpu-screen-recorder (absent) for replay |
| **plasma-stocktick** (new — no Omarchy source) | `plasma-stocktick/` | **BUILT** (2fdbac3) | First KDE-native plugin: Yahoo keyless quotes chip + watchlist + portfolio; checker 0/0, 5/5 tests, live-API verified. (No stock plugin existed on any Omarchy — checked.) |
| — (new, no Omarchy source) | `keyboard-shortcuts/` | **BUILT** (e783bb7) | hermes-keys.sh: Meta+Space/Return/H/Shift+H via kglobalaccel; no remapper needed |
| omarchy-game-center | — | skip | subsumed by plasma-sysmon (GPU VRAM/GTT already there) |
| omarchy-appdock | — | skip | reverse port; it *is* the KDE task manager on Hyprland |
| omarchy-ultrawide-bar | — | skip | KDE panel does partial-width/auto-hide/floating natively |
| omarchy-displayplus | — | skip | KScreen KCM native; hyprmoncfg editor is Hyprland-only |
| omarchy-powercore | — | parked | laptop-only (UPower/clamshell); revive if Bazzite goes on a laptop |
| omarchy-armoury | — | parked | asus_armoury kernel module; desktop has no ASUS hardware |
| omarchy-audiofx | — | parked | FX engine not installed on Omarchy yet; revisit after engine ships |
| omarchy-clearvoice | — | separate track | KDE frontend scoped in clearvoice-core skill (v3 plan) |

## Redesign queue (post-ship improvements)

| Target | Scope | State |
|---|---|---|
| `plasma-sysmon` v0.7 | **Full audit + UX review + redesign** (assigned 2026-10-30): wasted space in popup layout, process manager ("can be improved a lot"), section rhythm. Flow per the standing gate: harness screenshots + source audit → UX-agent redesign → harness validation at scale 1 + host DPR → present. | OPEN — kanban |

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
systemctl --user restart plasma-plasmashell.service
# add to panel: right-click panel → Add Widgets → <Name>
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

## CENTER-BAR LAYOUT (install day) — Greg's Omarchy arrangement
Target: **StockTick | timepiece clock (center anchor) | weatherx** — the
Omarchy center group (vivobook used tmn73.calendar centered; timepiece is our
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
