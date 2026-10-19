# Bazzite Customizations

KDE Plasma customizations, tweaks, and plugins for [Bazzite](https://bazzite.gg/) /
Fedora Kinoite (immutable, rpm-ostree) — by [gdeyoung](https://github.com/gdeyoung).

Sibling of the [`omarchy-*`](https://github.com/gdeyoung?tab=repositories&q=omarchy)
family (Arch + Hyprland) and of [praxis](https://github.com/gdeyoung/praxis), the
fleet-lessons hub. Everything here follows the same rules: installable without
sudo or rpm-ostree layering (lives in `$HOME`), reversible, verified on real
hardware with measured numbers, and honest about the failures that shaped it.

## Contents

| Entry | What it does |
|---|---|
| [plasma-sysmon](plasma-sysmon/) | Live **M/C/N/D** system monitor for the KDE Plasma 6 panel — compact bar strip that expands into a tabbed task-manager popup (performance charts, GPU VRAM/GTT, disk gauges, killable process table, hardware inventory). Pure QML + shell probes, user-level install. |
| [voxtype-push-to-talk](voxtype-push-to-talk/) | Hold-to-talk dictation into any app on KDE Plasma Wayland, transcribed by a **remote WhisperX server** — no local model on the desktop. Full write-up + parameterized install script. |

## Related

- **[galaxybook5-pro-platform](https://github.com/gdeyoung/galaxybook5-pro-platform)** —
  internal-speaker fix for the Samsung Galaxy Book5 Pro on Linux (MAX98390 amps), written
  for this Bazzite machine; now also carries the Omarchy/Arch field report and the
  speaker-loudness findings. The hardware half of this repo's story.

## House rules

- **Immutable-friendly**: no system mutations; systemd user units, `~/.local`, XDG config only.
- **Numbers or it didn't happen**: every claim ships with how it was measured.
- **Failures are the content**: the gotchas that cost a failed attempt are documented, not hidden.
- **Nothing private ships**: no LAN specifics, hostnames, or credentials — endpoints are parameters.

## License

MIT — see [LICENSE](LICENSE). Individual entries credit their upstreams.
