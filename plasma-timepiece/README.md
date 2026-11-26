# Plasma Time Piece

A date-time chip for the KDE Plasma 6 panel that expands into a calendar popup
with **color-coded world clocks**, a **countdown timer**, and a self-running
**pomodoro** — all of which survive a plasmashell restart.

Ported from the author's own [omarchy-timepiece](https://github.com/gdeyoung/omarchy-timepiece)
(Hyprland/Quickshell bar plugin) to native Plasma 6 — same model logic (ported
verbatim and unit-tested), same timer/pomodoro UX (design spec honored), zero
system mutations.

```
chip:    Monday Oct 26 4:20 PM · F 17:32     ← date + time (+ live timer/pomodoro suffix)
popup:   MARCH  26 hero date
         ET 5:20 PM  PT 2:20 PM  …          ← world clocks, categorical label hues
         2026 ▓▓▓▓▓▓▓▓░░░░░░ 81%            ← year progress rule
         W MO TU WE TH FR SA                 ← 6-row calendar, ISO week gutter,
           1  2  3  4  5  6  7                 today outlined, W heading toggles week start
         ‹ OCTOBER 2026 ›
         TIMER   [ TIMER | POMODORO ]        ← mm:ss hero, phase bar, 4-block cycle rail
```

## Why

The stock KDE clock shows no date by default — **date-in-chip is the point of
the fork**. Everything else came with it: the world-clock row, the countdown
timer, the pomodoro, and the date-mask behavior (`showDate: false` masks the
date out of *whatever* format the chip is in — `dddd MMM d h:mm AP` becomes
`dddd h:mm AP` — while keeping the day name; a format that is nothing but
date tokens is left unchanged rather than rendering an empty clock).

## Features

- **Chip** — date + time + optional live suffix: `· 12:34` while the timer
  runs, `· F 17:32` / `· B 3:10` / `· L 14:59` during pomodoro phases, `· done`
  for two minutes after the timer fires. Hover for the full tooltip.
- **Calendar** — always six rows (same height every month), ISO week numbers
  down a gutter, today outlined, year-progress rule under the hero. The `W`
  heading toggles the week start; the hero date is the "back to today" button
  once you've stepped away.
- **World clocks** — up to five zones, each a stable categorical hue on its
  label (cyan/amber/rose/blue/orange — deliberately no green/violet, so zones
  never masquerade as pomodoro phases); the time stays foreground bold. Times
  come from one read-only `TZ=<zone> date '+%-I:%M %p'` call per zone per
  minute, output shape-validated before display.
- **Countdown timer** — `−5M/+5M` steppers (1–600 min), START / PAUSE /
  RESUME / RESET; the readout is a 24px mm:ss hero (never a bare "10M").
- **Pomodoro** — START CYCLE runs focus/break alternating, every 4th break
  long (15 min); phases advance on their own, each flip fires a desktop
  notification (`notify-send`, present on KDE). 4-segment cycle rail = the
  set at a glance. Timer and pomodoro are mutually exclusive.
- **Restarts sanely** — run state (`timerEndsAt`, `pomodoroMode`, …) persists
  via `Plasmoid.configuration`; endsAt is absolute epoch-ms, so a plasmashell
  restart mid-run loses nothing.

The timer section follows the plugin's design spec (`design/timer-ux-spec.md`,
ported verbatim): phase color is always co-coded with the phase word (WCAG
1.4.1), digits stay foreground in every state, tabs hidden while anything
runs (mutual exclusion made visible).

## Settings

Right-click the chip (or panel → … → Configure Time Piece): world clocks with
a type-to-search city picker over the full tz database (518 zones, verbatim
`zones.js`; ET/PT/UTC aliases work), the date-in-chip toggle, the time format
string, the week start, and the timer/pomodoro defaults.

| Key | Default | Meaning |
|---|---|---|
| `clockFormat` | `dddd MMM d h:mm AP` | Chip format (Qt tokens; `ww` = ISO week, substituted by the widget) |
| `showDate` | `true` | Date in the chip — masks date tokens from any format |
| `worldClocks` | *(empty)* | `LABEL:Zone,…` (max 5) — the popup world-clock row |
| `weekStartDay` | *(locale)* | `sunday`…`saturday`; empty = locale default |
| `timerMinutes` | `10` | Idle timer preset (1–600) |
| `pomodoroFocusMin` / `pomodoroBreakMin` | `25` / `5` | Cycle lengths (long break fixed at 15, set at 4) |
| `timerRunning`, `timerEndsAt`, `timerRemainingMs`, `timerDoneAt` | *(transient)* | Live timer state — written by controls, fired by the applet |
| `pomodoroMode`, `pomodoroEndsAt`, `pomodoroCyclesDone` | *(transient)* | Live pomodoro phase state |

## Install

```bash
git clone https://github.com/gdeyoung/bazzite-customizations
cd bazzite-customizations/plasma-timepiece
./install.sh          # or: PLASMOID_ID=… DEST=… ./install.sh
```

No sudo, no compiling, no layering — installs to
`~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.timepiece` and survives
Bazzite/ostree updates. Then: right-click panel → **Enter Edit Mode** →
**Add Widgets** → search **Time Piece** → drag to the panel.

**Remove:** `kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.timepiece`
and restart plasmashell. Nothing is written outside the plasmoid install dir
and Plasma's own config.

## How it works

Pure QML — no compiled code, no daemons. `Model.js` and `zones.js` are
ported **verbatim** from the Omarchy plugin (pure JS; the full original unit
suite runs against them — see Tests). The container layer is rewritten for
Plasma 6: `PlasmoidItem` root, compact chip + popup as direct children, the
plasma5support `executable` dataengine for the two shell calls the widget
makes (`date` for zone times, `notify-send` for pomodoro flips). The
countdown/pomodoro fires in the applet itself (a QML `Timer`, as in Omarchy
where it ran in the shell process), so a fire never depends on the popup
being open.

## Tests

```bash
node --test test/timepiece.test.js
```

37 tests: the pure-`Model.js` suite from the Omarchy plugin (date masking,
world-clock parsing, zone search, timer math, pomodoro phase table — run
verbatim against the verbatim port), plus calendar-math sanity and wiring
pins adapted to the Plasma tree. **Status at commit time: 37 pass / 0 fail.**

## Verification status

Code-complete, **not installed** — no live-shell changes were made. Static:
`tools/check_qml.py plasma-timepiece` exits 0 (4 QML files, 0 errors,
0 warnings; `contents/config/config.qml` also checked under the same rules).
See "Install-day verification" below before installing.

### Install-day verification plan

1. `./install.sh`, then add the widget to the panel (Edit Mode → Add Widgets).
2. Chip shows date + time; hover shows the tooltip.
3. Open the popup: calendar grid renders 6 rows, today outlined; step months
   with the ‹ › pills; click the `W` heading to flip the week start.
4. Configure → add two world clocks (try typing `et`, `london`) → popup row
   shows both with hues; wrong zone names show `—`.
5. Timer: START → chip gains `· mm:ss`; let a 1-min timer fire → chip shows
   `· done` for 2 min, popup shows `00:00` + RESET; PAUSE/RESUME/RESET work.
6. Pomodoro: START CYCLE → chip shows `· F mm:ss`, popup rail fills; SKIP
   advances the phase and a notification appears; STOP clears.
7. Restart resilience: start a timer, `systemctl --user restart
   plasma-plasmashell.service` → the run resumes with correct remaining time.
8. Journal check: `journalctl --user -u plasma-plasmashell.service | grep -i
   timepiece` shows no QML errors naming our files.

## Provenance / lineage

Port of [omarchy-timepiece](https://github.com/gdeyoung/omarchy-timepiece)
@ `7e20cc9` (v0.5.0), which forked the first-party `omarchy.clock` shipped in
omarchy 4.0.5-1. `Model.js`, `zones.js`, and `design/timer-ux-spec.md` are
carried verbatim; the QML container layer is rewritten for Plasma 6
(PlasmoidItem, PlasmaComponents, Kirigami, KConfig XT). Upstream MIT — see
[LICENSE](LICENSE).

## License

MIT — upstream code (c) Omarchy; modifications (c) Greg DeYoung. See
[LICENSE](LICENSE).
