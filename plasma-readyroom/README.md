# Plasma Ready Room

The pre-game ritual in one KDE Plasma 6 panel widget: **boot-to-Game-Mode**,
the game **session** toggles, **controller** inventory with battery and rumble
test, an **instant-replay** buffer with one-click clip saving, and desk-**gear**
batteries plus a GPU summary with a MangoHud profile switcher.

Ported from the author's own
[omarchy-ready-room](https://github.com/gdeyoung/omarchy-ready-room)
(Hyprland/Quickshell) to native Plasma 6 for the Bazzite gaming desktop —
same `gc-*` helper scripts (byte-identical), same behavior, container QML
rewritten for Plasma.

```
bar (compact):   ⬤ 2        ← gamepad glyph + pad count; battery-alert when a pad is low;
                             ← record glyph while the replay buffer runs. Click to open.
popup:           Session · Pads · Replay · Gear
```

**Status: v0.1.0 — code-complete, not installed.** Static-checked
(`tools/check_qml.py`, 0 errors), helpers syntax-verified and read-only
probes executed once on the target host (see Verification). Live install and
visual QA are install-day steps (see Install-day plan).

## Provenance

| | |
|---|---|
| Upstream | github.com/gdeyoung/omarchy-ready-room @ `e842207` (2026-10-17, "ReplayTab: kill the teardown TypeError — atomic replay accessors") |
| This port | `bazzite-customizations` → `plasma-readyroom/`, branch `kde-ports-batch` |
| Helpers | `contents/scripts/gc-*` are sha256-identical to upstream `bin/gc-*` (port law: verbatim); two port-only additions: `gc-gear-stats` (timeout wrapper) and `71-readyroom.rules` (upstream udev rule, relocated beside `gc-udev`) |
| License | MIT (LICENSE + THIRD_PARTY_NOTICES.md copied from upstream) |

## The tabs

- **Session** — *Boot into*: shows which session SDDM autologins into
  (Game Mode = `gamescope-session.desktop` vs Desktop = `plasma.desktop`)
  and toggles it by writing the same drop-in `/etc/sddm.conf.d/…` file
  `ujust toggle-gamemode` writes, via `pkexec` (polkit asks once). Then the
  game session: keep-awake, do-not-disturb, night light, performance power
  profile — engaged through `gc-session`, which only ever restores what it
  changed and puts it back on release. Sub-labels say who owns each switch
  right now (the upstream plugin's core idea, kept intact).
- **Pads** — connected controllers with connection type + driver, battery as
  five segments (xone's five buckets — no invented percentages) or a real
  percent (DualSense), a rumble test (`gc-rumble`), bounded live-input
  sampling (`gc-pads`), claimed-pad sentences ("Steam is using this
  controller"), and the Xbox Wireless Adapter section. Controls that cannot
  work on your hardware are absent, not disabled.
- **Replay** — arm/disarm the `gpu-screen-recorder` ring buffer (`gc-replay
  arm/disarm`), save the last N seconds (`gc-replay save`), buffer length /
  quality / storage settings, and the recent-clips list. The buffer's cost is
  stated up front. *Replay needs `gpu-screen-recorder` installed (Bazzite:
  `ujust install-gsr` or `rpm-ostree`/`brew`) — see Prerequisites.*
- **Gear** — desk-gear batteries via UPower (`gc-gear-probe`: mice, keyboards,
  headsets, earbuds, Bluetooth pads — absent, not zero, when asleep), a
  one-shot GPU/CPU/RAM summary (`gc-gear-stats` → `gc-stats`:
  nvidia-smi/amdgpu/RAPL chain), and the MangoHud profile switcher
  (`gc-mangohud`) which writes a managed block into `~/.config/MangoHud/
  MangoHud.conf` and never touches anything outside it.

## gdtower prerequisites (verified on-host)

| Component | Status on the target host |
|---|---|
| Plasma 6 | present (Bazzite KDE image, `kpackagetool6 2.0`) |
| Game Mode | `gamescope-session-steam.desktop` + `gamescope-session-ogui-steam.desktop` in `/usr/share/wayland-sessions/`; `gamescope 3.16.31`; SDDM autologin drop-ins in `/etc/sddm.conf.d/` |
| MangoHud | `mangohud` at `/usr/bin/mangohud`, rpm `terra-mangohud 0.8.4` (profile switcher works today) |
| NVIDIA | `nvidia-smi` present (RTX 5080 16 GB — gc-stats reported `vramTotalMb 16303`) |
| UPower | `upower` present (gear tab works) |
| `gpu-screen-recorder` / `gsr-cli` | **NOT installed** — Replay tab's arm/save will refuse with "gpu-screen-recorder is not installed" until added |
| `jq` | present (gc-replay/gc-session need it) |
| `inotify-tools` | not installed — upstream PadController used it for hotplug; this port polls instead (30 s while open) |
| Symbols Nerd Font | present at `/usr/share/fonts/nerd-fonts/` — all glyphs verified present (U+F02B4 gamepad, U+F044B record, U+F0083 battery-alert, U+F0208 eye, U+F0379 monitor, …) |

## Omarchy-only helpers on Bazzite

The verbatim helpers degrade honestly where Omarchy CLIs don't exist:

| Helper | Bazzite behavior |
|---|---|
| `gc-session` engage/release | stay-awake marker + DND + night light subcommands call `omarchy-*` CLIs → states read `unknown`/`free`, ownership refused, session still guards power profile + inhibitor; `release` from a terminal still works |
| `gc-binds` | Hyprland-only (`~/.config/hypr/bindings.lua`, `hyprctl`) — not wired into this port's UI; bind `…/scripts/gc-replay save` in KDE custom shortcuts instead |
| `gc-replay` monitor autodetect | falls back through `hyprctl monitors -j` (absent) → pass `--monitor` from config (`replayMonitor` key) or arm fails with "could not determine which monitor to capture" |
| `gc-clip-saved` | `-sc` hook for gsr: notification line calls `omarchy-notification-send` (guarded `\|\| true`) — path recording still works; replace with `notify-send` upstream-side later |
| `gc-udev`, `gc-thumb` | pure shell + root-optional — work as-is |

## Install

```bash
git clone https://github.com/gdeyoung/bazzite-customizations
cd bazzite-customizations/plasma-readyroom
./install.sh                      # or: DEST=… NO_RESTART=1 ./install.sh
```

No sudo for the widget itself, no compiling, no layering — installs to
`~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.readyroom` and survives
Bazzite/ostree updates. Then: right-click panel → **Enter Edit Mode** →
**Add Widgets** → search **Ready Room** → drag to the panel.

**Rollback:** `kpackagetool6 -t Plasma/Applet -r
com.gdeyoung.plasma.readyroom && systemctl --user restart
plasma-plasmashell.service` — user-level only; `gc-session release` first if a
session is engaged. Nothing else is left behind except: the replay clips
(yours to keep in `~/Videos/Clips`), the managed block in `MangoHud.conf`
(delete `### begin ready-room` … `### end ready-room`), and the optional udev
rule (only if you installed it).

## Config keys (KConfig XT, widget settings dialog)

| Key | Default | What it does |
|---|---|---|
| `startTab` | `session` | Tab shown when the popup opens |
| `panelWidth` | `380` | Popup width px (300–640) |
| `bootModeConfPath` | `/etc/sddm.conf.d/zz-steamos-autologin.conf` | SDDM drop-in the boot-mode toggle writes (parameterized; matches `ujust toggle-gamemode`) |
| `gameModeSession` | `gamescope-session.desktop` | Session file for Game Mode |
| `desktopSession` | `plasma.desktop` | Session file for the desktop |
| `sessionKeepAwake` / `sessionDnd` / `sessionNightlight` / `sessionPower` | `true` | Which switches a session may touch |
| `replaySeconds` | `300` | Buffer length s (60–900) |
| `replayStorage` | `disk` | `disk` \| `ram` |
| `replayQuality` | `balanced` | `low`/`balanced`/`high`/`ultra` |
| `replayAudio` | `desktop` | `desktop`/`both`/`none` |
| `replayDir` | *(empty)* | Clip folder; empty = `~/Videos/Clips` (no personal paths baked in) |
| `replayMonitor` | *(empty)* | Monitor name for gsr; empty = let `gc-replay` detect |
| `mangohudPosition` | `top-left` | Overlay corner written by the profile switcher |
| `mhCpu`/`mhGpu`/`mhRam`/`mhVram`/`mhTemps`/`mhPower` | on/off | MangoHud metrics in the managed block |

## Verification (done at port time — 2026-10-26, target host)

- `tools/check_qml.py plasma-readyroom` → **15 QML files checked, 0 errors,
  0 warnings** (exit 0).
- `bash -n` on 8 shell helpers, `python3 -m py_compile` on 5 python helpers —
  all OK.
- Read-only probes executed once, output-shape verified:
  - `gc-pad-probe` → `{"pads":[],"claimed":[],"dongles":[],"drivers":["hid_playstation"]}`
  - `gc-gear-probe` → `{"gear":[]}`
  - `gc-gear-stats` → hello `gpu:nvidia` + stats line with real 5080 numbers
    (`vramTotalMb 16303`, `watts 23`)
  - `gc-session status` / `gc-replay status` → valid JSON, `engaged:false`,
    `armed:false`
- Write-classified helpers (`gc-session engage/release`, `gc-replay
  arm/disarm/save`, `gc-rumble`, `gc-mangohud`, `gc-binds`, `gc-udev`,
  `gc-thumb`) were **not** executed — verified by reading + syntax check only.

## Install-day plan (NOT run at port time)

1. `./install.sh`; add widget to panel.
2. Chip: gamepad glyph renders (Symbols Nerd Font); tooltip sentence correct.
3. Popup compile test: add a desktop-containment instance once, check
   `journalctl --user -u plasma-plasmashell.service` for QML errors naming
   these files, remove it.
4. Session tab: `gc-session status` fields land (engaged/stayAwake/dnd
   states; expect `dnd:unknown` and night-light `false` on Bazzite — the
   omarchy CLIs are absent by design). Engage/release round-trip if desired.
5. Pads tab: plug in a controller, verify battery + `Test rumble` (writes
   FF effect — install-day only), live-input sampling line moves.
6. Replay tab: install `gpu-screen-recorder` first, then arm → REC glyph in
   chip, save → clip appears, `~/Videos/Clips` grows.
7. Gear tab: UPower rows for paired gear; `Apply MangoHud profile` writes
   the managed block in `~/.config/MangoHud/MangoHud.conf` (verify only the
   block changed); GPU summary shows NVIDIA numbers.
8. Boot mode: toggle Game Mode → check the drop-in content matches
   `ujust toggle-gamemode` output; reboot optional.

## Design notes / deltas from upstream

- **One dataengine, one handler**: every subprocess goes through a single
  `DataSource` (plasma5support 2.0, unaliased, `interval: 0`,
  connect→read→disconnect), routed by command marker — the Plasma analogue of
  upstream's per-controller `Process` objects. `onNewData` uses formal
  parameters; no `in connectedSources` gating.
- **Bounded live input**: Quickshell's `Process` can host a streaming
  `gc-pads` for the pads tab's lifetime; the Plasma popup cannot host a
  long-lived child, so the port samples ~7 s bursts (`timeout 1 gc-pads …`,
  auto-stop) and renders one honest line instead of the drawn input view.
  Upstream's `PadInputView`/`PadArt.js` silhouette art is not ported (v0.1.0).
- **No in-panel keybind editor**: `gc-binds` manages Hyprland's
  `bindings.lua`; on KDE the equivalent is a custom shortcut pointing at
  `<scripts>/gc-replay save` (documented in the Replay tab).
- **Overlay window not ported**: upstream's per-screen Quickshell overlay
  (StatsOverlay) has no Plasma-applet equivalent; the Gear tab's one-shot
  summary + MangoHud profile switcher cover the FPS case, which upstream
  already delegated to MangoHud.
- **Callback-property components** (`GcPill`, `GcToggle`, `GcButton`,
  `GcAfter`): Plasma fails a whole applet on a duplicated signal handler, so
  every repeated control emits through a `tap`/`action` function property
  instead of `onClicked` — this keeps "one handler per signal per file" true
  by construction.
- **Popup self-sizing**: pages are `ColumnLayout` children collapsing to
  height 0 when invisible, so the popup height binding tracks the visible
  page only (no StackLayout tallest-child trap, no fixed gridUnit constants).

## Lineage

Forked conceptually from the author's
[omarchy-ready-room](https://github.com/gdeyoung/omarchy-ready-room) (itself
forked from Austin Larson's dielerorn.gamecenter; idea credits in
THIRD_PARTY_NOTICES.md — all MIT). Same helpers, same rules — container
rewritten for Plasma 6 (PlasmoidItem, PlasmaComponents, Kirigami, KConfig XT).
