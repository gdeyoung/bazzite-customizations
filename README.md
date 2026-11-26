# Bazzite Customizations — KDE Plasma 6 plugins

KDE Plasma customizations, tweaks, and plugins for [Bazzite](https://bazzite.gg/) /
Fedora Kinoite (immutable, rpm-ostree) — by [gdeyoung](https://github.com/gdeyoung).

This is the **KDE side** of the fleet's desktop plugins: native Plasma 6 ports of the
[`omarchy-*`](https://github.com/gdeyoung?tab=repositories&q=omarchy) family
(Arch + Hyprland / Quickshell), plus a few KDE-native additions. Same probes, same
behavior, different shell — the Omarchy originals stay in their own repos; the KDE
versions live here, one directory per plugin (`plasma-*`, `foyer-kde`,
`krunner-hermes`). Sibling of [praxis](https://github.com/gdeyoung/praxis), the
fleet-lessons hub. Everything here follows the same rules: installable without
sudo or rpm-ostree layering (lives in `$HOME`), reversible, verified on real
hardware with measured numbers, and honest about the failures that shaped it.

## Contents

### KDE Plasma 6 ports of `omarchy-*` plugins

| Omarchy original (Quickshell / Hyprland) | KDE version — here | What it does |
|---|---|---|
| [omarchy-sysmon](https://github.com/gdeyoung/omarchy-sysmon) | [plasma-sysmon](plasma-sysmon/) | Live **M/C/N/D** panel strip → tabbed task-manager popup: performance charts, GPU load/VRAM/GTT, disk gauges, killable process table, fastfetch-grade hardware inventory. |
| [omarchy-tailfin](https://github.com/gdeyoung/omarchy-tailfin) | [plasma-tailfin](plasma-tailfin/) | Tailscale chip (state + online/peer count) → device list with exit nodes, subnet routes, self identity and health warnings. |
| [omarchy-weather](https://github.com/gdeyoung/omarchy-weather) | [plasma-weatherx](plasma-weatherx/) | Weather glyph + temperature → tabbed popup: here + pinned places, details grid, remaining-hours strip, 7-day forecast, sun times, keyless radar map. |
| [omarchy-timepiece](https://github.com/gdeyoung/omarchy-timepiece) | [plasma-timepiece](plasma-timepiece/) | Date-time chip → calendar popup with color-coded world clocks, a countdown timer and a pomodoro. |
| [omarchy-driveway](https://github.com/gdeyoung/omarchy-driveway) | [plasma-driveway](plasma-driveway/) | Every drive one click away: USB/local disks, SMB/NFS/sshfs shares, rclone cloud remotes — mounted state, usage and health. |
| [omarchy-timemachine](https://github.com/gdeyoung/omarchy-timemachine) | [plasma-timemachine](plasma-timemachine/) | Backup status chip → five-tab Time Machine panel over the bundled rsync engine + local btrfs snapshots. |
| [omarchy-ready-room](https://github.com/gdeyoung/omarchy-ready-room) | [plasma-readyroom](plasma-readyroom/) | Boot-to-Game-Mode, session toggles, controller inventory/test, instant-replay buffer, gear batteries + MangoHud profile switcher. |
| [omarchy-foyer](https://github.com/gdeyoung/omarchy-foyer) | [foyer-kde](foyer-kde/) | The front door on Plasma: keyboard-first fan-out launcher overlay (browsable menu tree + live all-source search + Hermes lanes). Design of record: [CONVERGED-DESIGN.md](foyer-kde/CONVERGED-DESIGN.md). |
| [naolselemon/mosaic](https://github.com/naolselemon/mosaic) (3rd-party, MIT) | [plasma-mosaic](plasma-mosaic/) | Read-only application-storage explorer: where each app keeps config/data/cache/state, measured, with evidence labels. |

### KDE-native (no Omarchy source)

| Entry | What it does |
|---|---|
| [krunner-hermes](krunner-hermes/) | **Hermes KRunner runner** — `ai <question>` / `hr <task>` from Super+Space; zero-compile DBus runner. The rows-only sibling of foyer-kde. |
| [plasma-stocktick](plasma-stocktick/) | Stock chip + Markets/Watchlist/Portfolio popup (Yahoo, keyless); layout modeled on the Omarchy `5d0tal1gat0r.stocks` plugin. |
| [plasma-panelpad](plasma-panelpad/) | Invisible fixed-width panel spacer — exact, scriptable gaps between widgets. |
| [keyboard-shortcuts/](keyboard-shortcuts/) | `hermes-keys.sh` — the Meta+Space/Return/H binds as kglobalaccel `[services]` entries; no remapper needed. |
| [voxtype-push-to-talk](voxtype-push-to-talk/) | Hold-to-talk dictation into any app on KDE Plasma Wayland, transcribed by a **remote WhisperX server** — no local model on the desktop. |

Port status (tree vs installed), declined ports and the install-day punch list live in
[ROADMAP-KDE-PORTS.md](ROADMAP-KDE-PORTS.md); harness + tooling in [tools/](tools/);
specs and research in [docs/](docs/). The **Clearvoice** KDE frontend (Plasma plasmoid +
PipeWire recorder) ships in [clearvoice-core](https://github.com/gdeyoung/clearvoice-core),
next to its Omarchy sibling.

## Screenshots

Every plugin, full desktop, from the nested virtual Plasma harness (`tools/popup-harness/`) — Breeze Dark,
demo data only (no real hosts, accounts or endpoints). Click through for the per-plugin shots.

| Plugin | Popup open | Plugin | Popup open |
|---|---|---|---|
| [plasma-sysmon](plasma-sysmon/docs/screenshots/desktop.png) | Performance tab · [processes](plasma-sysmon/docs/screenshots/processes.png) | [plasma-driveway](plasma-driveway/docs/screenshots/desktop.png) | Shares tab |
| [plasma-tailfin](plasma-tailfin/docs/screenshots/desktop.png) | Machines tab (stub fixture) | [plasma-timemachine](plasma-timemachine/docs/screenshots/desktop.png) | fresh-install state |
| [plasma-weatherx](plasma-weatherx/docs/screenshots/desktop.png) | Here tab (seeded places) | [plasma-readyroom](plasma-readyroom/docs/screenshots/desktop.png) | Session tab · [gear](plasma-readyroom/docs/screenshots/gear-tab.png) |
| [plasma-timepiece](plasma-timepiece/docs/screenshots/desktop.png) | calendar + world clocks | [plasma-mosaic](plasma-mosaic/docs/screenshots/desktop.png) | storage explorer |
| [plasma-stocktick](plasma-stocktick/docs/screenshots/desktop.png) | Markets tab | [krunner-hermes](krunner-hermes/docs/screenshots/answer.png) | `ai` query sent |
| [foyer-kde](foyer-kde/docs/gallery/GALLERY.html) | design gallery: native QML + daemon overlay, every state | [plasma-panelpad](plasma-panelpad/) | invisible by design — no shot |

## House rules

- **Immutable-friendly**: no system mutations; systemd user units, `~/.local`, XDG config only.
- **Numbers or it didn't happen**: every claim ships with how it was measured.
- **Failures are the content**: the gotchas that cost a failed attempt are documented, not hidden.
- **Nothing private ships**: no LAN specifics, hostnames, or credentials — endpoints are parameters.

## License

MIT — see [LICENSE](LICENSE). Individual entries credit their upstreams.
