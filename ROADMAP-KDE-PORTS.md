# KDE Port Roadmap — the Omarchy plugin suite on Bazzite

Decision 2026-10-26: build ALL ports as code-complete artifacts on branch
`kde-ports-batch`; **install nothing until Greg is back at the tower**. Install
steps live at the bottom as a punch list.

## Status

| Omarchy source | KDE target here | State | Notes |
|---|---|---|---|
| omarchy-sysmon | `plasma-sysmon/` | **SHIPPED** (master) | v0.6.0, installed + verified |
| omarchy-foyer (AI lanes) | `krunner-hermes/` | build | DBus runner: `ai <q>` → LiteLLM one-row answer; `hr <task>` → hermes -z task + notification. Apps/calc/timers stay native KRunner. |
| omarchy-weather | `plasma-weatherx/` | build | keyless Open-Meteo + Esri/RainViewer radar, pinned places |
| omarchy-timepiece | `plasma-timepiece/` | build | date-in-chip clock, world-clock row, countdown + pomodoro |
| omarchy-tailfin | `plasma-tailfin/` | build | tailscale status chip + device panel (Trayscale already covers app use) |
| omarchy-driveway | `plasma-driveway/` | build | USB/SMB/NFS/sshfs/rclone one-click mounts; python lib ports verbatim |
| omarchy-timemachine | `plasma-timemachine/` | build | rsync backup chip + 5-tab popup; engine scripts port verbatim |
| omarchy-ready-room | `plasma-readyroom/` | build | gaming panel: session toggles, pad battery/test, replay, MangoHud profiles |
| omarchy-game-center | — | skip | subsumed by plasma-sysmon (GPU VRAM/GTT already there) |
| omarchy-appdock | — | skip | reverse port; it *is* the KDE task manager on Hyprland |
| omarchy-ultrawide-bar | — | skip | KDE panel does partial-width/auto-hide/floating natively |
| omarchy-displayplus | — | skip | KScreen KCM native; hyprmoncfg editor is Hyprland-only |
| omarchy-powercore | — | parked | laptop-only (UPower/clamshell); revive if Bazzite goes on a laptop |
| omarchy-armoury | — | parked | asus_armoury kernel module; desktop has no ASUS hardware |
| omarchy-audiofx | — | parked | FX engine not installed on Omarchy yet; revisit after engine ships |
| omarchy-clearvoice | — | separate track | KDE frontend scoped in clearvoice-core skill (v3 plan) |

Meta sources: `omarchy-recipes` (discipline) and `omarchy-skills` (agent
skills) have no KDE artifact — their KDE equivalents are this repo + the
`plasma-plasmoid-development` skill.

## Verification ladder (every port)
1. `tools/check_qml.py <dir>` → 0 errors (static).
2. Probe executes once → strict JSON (read-only probes only).
3. Install-day: heartbeat advances, journal clean, screenshots, panel placement
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
