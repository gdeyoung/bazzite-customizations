---
title: "NextKde / KOS Desktop Shell — Technical Dossier"
date: 2026-11-12
lanes: kde-simplicity-research
verdict: "A serious, fast-moving, largely single-driver project that REPLACES Plasma chrome via Quickshell + compiled C++ services + custom KWin effects. Real counterexample to 'Quickshell can only be companion chrome' — but it buys the takeover with compiled KWin effect binaries and a platform daemon, exactly the parts a Bazzite no-layering rule forbids."
source_urls:
  - https://github.com/NextKde/NextKde
  - https://github.com/NextKde
  - https://api.github.com/repos/NextKde/NextKde
  - https://raw.githubusercontent.com/NextKde/NextKde/main/README.md
  - https://github.com/NextKde/NextKde/tree/main/docs
---

# NextKde / KOS Desktop Shell — Technical Dossier

## 1) Repo Reality

All metadata from the GitHub API on 2026-11-12/13 ([repos/NextKde/NextKde](https://api.github.com/repos/NextKde/NextKde)):

| Field | Value |
|---|---|
| Owner | `NextKde` GitHub **Organization** (created 2026-09-23; bio: "A Quickshell desktop for KDE Plasma, with a floating dock, liquid glass, desktop widgets, and native KWin integration") ([org](https://github.com/NextKde)) |
| Stars / forks | **863 / 70**; 27 open issues |
| License | **GPL-3.0**; the bundled KWin glass effect carries its own license ([README](https://github.com/NextKde/NextKde#license), `kwin/glass-effect/LICENSE`) |
| Created | 2025-11-07 (repo), org spun up 2026-09-23 |
| Last push | 2026-11-13T04:10Z — active the morning this dossier was written |
| Default branch | `main` |
| Releases | `v0.1.0` (2026-10-19) and `v0.1.1` (2026-10-20) only; source tarball + SHA256SUMS + validation reports ([releases](https://github.com/NextKde/NextKde/releases)) |
| Repo size | ~242 MB git size (heavy image/asset history) |
| Topics | `kde`, `kde-plasma`, `liquid-glass`, `macos`, `quickshell` |

**Contributors:** 33 listed by the API ([contributors](https://api.github.com/repos/NextKde/NextKde/contributors)). Heavily concentrated: `SuceV587` 1,396 commits (~77%), then `dumingqiao` 91, `Arcment` 81, `eacheat53` 63, `skjsbsnq` 59, `jingying32` 57 — i.e. a second tier exists (5 people with 50+ commits, several with Chinese-display-name commit identities like `liubw`, `amaoliu`, `Kaijun Su` in the recent window), but this is functionally a **single-driver project with a small active bench**, not a community-maintained one.

**Commit cadence:** the most recent 100 commits span only **2026-10-31 → 2026-11-13** (~7/day sustained; newest: "feat(motion): add interruptible springs to shared interactions"). Full 3-month histogram in §12 verification notes — development is daily and continuous. GitHub Actions even includes a `block-ai-coauthor.yml` workflow (`.github/workflows/`), i.e. the maintainer polices AI-attribution noise in commits.

## 2) Identity & Lineage

- **NextKDE** is the project/brand; the **"KOS Desktop Shell"** is the shell component inside it. The repo description reads: *"NextKde (KOS Desktop Shell) is a modern desktop shell project. It replaces or enhances parts of Plasma's native interface, providing an integrated user interface that combines a top panel, application dock, launcher, global search, notification center, and system settings."* ([repo](https://github.com/NextKde/NextKde)). The README's own words: *"NextKDE's **KOS Desktop Shell** brings the bar, dock, launcher, search, notifications, and settings together on KDE Plasma 6 Wayland."*
- **What KOS stands for:** the repo never expands the acronym in the README; the tooling and service names are all `kos-*` (`kosctl`, `kos-platform.service`, `kos-shell.service`). Not independently verified as an expansion of anything — treat "KOS" as a brand, not an acronym with a documented meaning.
- **Not a fork.** `fork: false`, no parent, and it is not a derivative of Caelestia/noctalia/DankMaterial (different codebase: custom `platform/` C++ daemon, own `kwin/` effects, own settings app). Lineage is: Quickshell (framework) + KDE Plasma 6 (host environment). README badge line: `Plasma 6 / Wayland · Quickshell 0.3.x · Qt 6`.
- **Origin:** the README's install snippet still says `git clone https://github.com/SuceV587/NextKde.git` ([README get-started](https://github.com/NextKde/NextKde#get-started)) — the project started as `SuceV587/NextKde` and was transferred into the `NextKde` org in Sept 2026. The org now hosts a whole app family: `NkMusic`, `NkNotes`, `NkShot`, `NkPhotos`, `NkMail`, `kos-apps` (Calendar/Calculator/Weather), `ListenFree`, `nextkdeAppDemo` (QML component gallery), `appCatalog` (signed app-store catalog), `depthrelease` (wallpaper model provenance) ([org repos](https://github.com/NextKde?tab=repositories)).
- **Relationship to other shells:** none claimed. It positions against macOS explicitly (topic `macos`, "macOS appearance", "Apple Music inspired navigation" in NkMusic's description) — it is a "make KDE look/behave like macOS" project built on Quickshell rather than a Plasma theme.

## 3) Component Inventory — what ships

Shell QML feature modules (`shell/desktop/modules/`, 346 files) plus apps and native code ([tree](https://github.com/NextKde/NextKde/tree/main/shell/desktop/modules), [ProjectArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/ProjectArchitecture.md)):

| Component | Status | Evidence |
|---|---|---|
| Top bar + system menus | **Ships**: `modules/bar/` — `Bar.qml`, `BarAutoHideController`, `GlobalMenu.qml` (in-bar app menu), `AppMenuService`, status area | `shell/desktop/modules/bar/` |
| Control Center | **Ships**: `ControlCenterCard/Glass/Panel/Service/Slider/Toggle.qml`, Wi-Fi/BT/battery/network panels | `shell/desktop/modules/bar/` |
| Floating dock | **Ships**: `modules/dock/` — magnification (`DockMagnification.mjs`), auto-hide, music player + desktop lyrics, pins persisted in state dir | `shell/desktop/modules/dock/` |
| Launcher / app grid | **Ships**: `modules/applauncher/` — fullscreen launcher, folders (folder-open blurs root page via MultiEffect) | [AppearanceArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/AppearanceArchitecture.md) |
| Global search (spotlight) | **Ships**: `modules/quicksearch/` — README markets "app search" + "global search"; Settings has a `spotlight` nav icon | README, `apps/settings/icons/navigation/spotlight.svg` |
| Notifications | **Ships**: `modules/notifications/` — `NotificationCenter.qml`, history service, per-app policy, sounds, activation controller. KOS registers as the **notification daemon owner** ("KOS's notification owner can be blocked by another notification daemon") | [GettingStarted.md §desktop-takeover](https://github.com/NextKde/NextKde/blob/main/docs/GettingStarted.md) |
| System tray (SNI) | **Ships**: implemented in the C++ daemon — `platform/src/daemon/PlatformServerTray.cpp` — with QML-side identity resolution (`modules/bar/TrayIdentity.mjs`) | platform tree |
| Overview | **Ships**: `modules/overview/` + custom KWin integration: the Glass effect composes desktop+dock into Overview/Present-Windows thumbnails (`kwin/glass-effect/src/overviewpreview.cpp`) | [WindowAppearance.md](https://github.com/NextKde/NextKde/blob/main/docs/WindowAppearance.md) |
| Wallpaper engine | **Ships, ambitious**: `modules/wallpaper/`, `docs/WallpaperArchitecture.md`, plus a **depth engine** — ONNX-based monocular depth (`services/ai/`, "LiquidAI" `DepthGenerator`, `SpatialAssetGenerator`) driving `shell/native/spatial3d` 3D wallpaper meshes | `docs/DepthEngine.md`, org repo `depthrelease` |
| Desktop files/icons | **Ships**: `modules/deskcenter/` — "open, rename, copy, move, delete, choose an application" (README); Plasma folder-view is disabled during takeover | README + GettingStarted |
| Lock screen | **Ships, optional**: `apps/lockscreen/` (LockScreen.qml, WakeAuthentication.qml, media/lyrics widgets) installed via `kosctl install lockscreen`; SDDM theme present but **"has no supported installer"** | GettingStarted.md |
| Settings | **Ships**: `apps/settings/` — separate Qt Quick app (C++ `src/`), ~20 pages (Bar, Dock, Launcher, Wallpaper, Fonts, Theme, Notifications, Power, Shortcuts, Services, Glass debug, …) | `apps/settings/pages/` |
| Session/logout menu | **Ships**: bar logo menu does "settings and session actions" (README); lockscreen `SessionMenu.qml`; `PlatformServerPower.cpp` in the daemon | README, platform tree |
| Input method | **Ships**: fcitx Kimpanel bridge (`platform/fcitx-panel/`, `KimpanelBridge.cpp`, `InputMethodIntegration.md`) | platform tree |
| Companion apps | Calendar/Calculator/Weather (org repo `kos-apps`), NkMusic, NkNotes, NkShot, NkPhotos, NkMail (planned), ListenFree — installed as **signed Flatpak bundles from GitHub Releases** via an app-store catalog | README, org repos |

**Stubs/planned:** Mail and File Manager are explicitly "planned for the future" (README). README "Next steps": per-screen layouts, consistent multi-display widgets, accessibility. Nothing in the core shell looked like a placeholder in tree/docs inspection; the risk is breadth churn, not stubs.

**Verbatim README claims** ([README.md](https://github.com/NextKde/NextKde#readme)):
> "**NextKDE's KOS Desktop Shell** brings the bar, dock, launcher, search, notifications, and settings together on KDE Plasma 6 Wayland. It works with KWin, NetworkManager, PipeWire, BlueZ, and systemd."

> "Top bar & system menu — app menus, system status, and the NextKDE logo menu for settings and session actions." / "Control center — Wi-Fi, Bluetooth, volume, brightness, screenshots, and Do Not Disturb."

> "A floating dock, window previews, app search, and a fullscreen launcher." / "Liquid glass, soft-light and frosted materials, or a tonal Material Design interface."

> "Use a **KDE Plasma 6 Wayland** session with **KWin 6.6+**, **Quickshell 0.3.x**, and **Qt 6.6+**. Installation builds the platform service, Settings, KWin effects, and window decoration."

That last sentence is the tell: this is not a drop-in QML config — the installer **compiles C++** (platform daemon, settings app, six KWin plugins) on the target machine.

## 4) "Liquid Glass" Implementation

It is a **real compositor effect chain, not a translucency theme** — three layers:

1. **Compositor side — `kwin/glass-effect/`**: a fork of [4v3ngR/kwin-effects-glass](https://github.com/4v3ngR/kwin-effects-glass), itself a fork of Plasma's stock blur effect ([glass-effect README](https://github.com/NextKde/NextKde/tree/main/kwin/glass-effect)). Ships GLSL shaders: `downsample.glsl`/`upsample.glsl`/`gaussian.glsl` (separable multi-pass blur), **`snells-glass.glsl`** — refraction via Snell's law, credited to [PKMNPlatin/kwin-effects-snell-glass](https://github.com/PKMNPlatin/kwin-effects-snell-glass) — plus `noise.glsl` (grain), `oklab.glsl` (perceptual tinting), `onscreen_rounded.glsl`. Also LightlyShaders lineage for CMake. This is the same family of KWin blur-fork tech as LightlyShaders/forceblur, extended.
2. **Custom Wayland protocols — `shell/native/surface-shape/`**: the shell side defines **`kos-surface-shape-v1.xml`** and **`kos-window-controls-v1.xml`** — private protocol extensions the KWin plugins implement, so Quickshell surfaces tell KWin their glass contour/shape and window-control geometry instead of relying on legacy blur-region hints. `surfaceshapemanager.cpp` on the KWin side consumes them.
3. **QML side**: 17 shader files in `shell/desktop/shaders/` (`scene_liquid.frag`, `squircle.frag`, `stage_plate/tilt/round.frag` …) compiled to `.qsb` — Qt Quick scene shaders for cards/stage surfaces — plus `MultiEffect` blur for launcher folders ([AppearanceArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/AppearanceArchitecture.md)). Presets: `liquid` / `soft` / `frosted`, and a separate Material (tonal) style with its own blur policy.

Extra depth beyond blur: `kwin/kos-bridge/` does continuous superellipse window corners ("exponent 2 + 2·smoothness"), inward outlines, contact shadows, GPU texture sharing with fences, a 256 MiB corner cache, and Overview thumbnail composition of dock+desktop with bounded glass ([WindowAppearance.md](https://github.com/NextKde/NextKde/blob/main/docs/WindowAppearance.md)). Effect chain ordering is explicit: Glass(20) → dock/stage animation(50) → Bridge(100).

So: "liquid glass" = gaussian blur + Snell refraction + noise + OKLab tint running **inside KWin**, driven by a private surface-shape protocol from the shell. Genuinely beyond what a pure layer-shell Quickshell config can do on stock KWin — which is exactly why they forked the compositor plugins.

## 5) Settings Architecture

- **Persistence = JSON in Quickshell's state dir, not KConfig.** `Quickshell.stateDir/appearance/config.json` (schema **33**, with source-serialized migrations), `appearance/icon-appearance.json` (schema 1), `~/.config/kos/window-appearance.json` (schema 2, KWin-bridge side). Writes are debounced through `JsonConfigStore` → platform `state.write` → `QSaveFile` (atomic) — "rather than a QML shell command" ([AppearanceArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/AppearanceArchitecture.md)).
- **Settings UI is a separate process** (`apps/settings/`, `kos-settings`, .desktop file `kos-settings.desktop.in`), which "communicates with Shell IPC only" and "never imports Shell internals" — it calls a versioned `appearance-settings` IPC endpoint on the shell and receives complete snapshots ([ProjectArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/ProjectArchitecture.md)). That's a cleaner split than most Quickshell shells, which embed settings pages in-shell.
- **Wired to real behavior:** yes — validated/clamped values, per-preset optical values, style switch (`windows12`/`macos`/`material`) and glass preset (`liquid`/`soft`/`frosted`) change compositor-side material via the tokens/protocol; KWin-side knobs land in `kwinrc` via `kwriteconfig --notify false` during install.
- **KConfig is read, not owned:** the shell resolves Plasma wallpaper config "through the current `plasmashellrc` ShellPackage" and font settings integrate with Plasma 6.6–6.8, but the shell's own settings do not live in Plasma's KConfigXT infrastructure.
- Palette generation is local: CAM16/HCT "monet" plus `chinese`/`japanese` traditional-color palettes in `shared/qml/colorize/` pure JS, explicitly no external `matugen`.

## 6) Compositor Coupling & Panel Replacement

**Coupling: maximal — this is a KWin-specific shell.**
- Requires **KWin 6.6+**; CI builds the KWin plugins against 6.6/6.7/6.8 SDKs ([ProjectArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/ProjectArchitecture.md)); the docs state native plugins must be rebuilt after KWin/Qt upgrades.
- Six project-owned KWin plugins: `glass-effect`, `kos-bridge` (window appearance + compositor-drawn window buttons), `kos-decoration` (a native KWin **window decoration plugin**), `dock-window-animation`, `context-menu-input`, `kwin-effects-stageanim` — plus `window-bridge.js`, a KWin QtScript loaded by the platform daemon.
- Private Wayland protocols (`kos-surface-shape-v1`, `kos-window-controls-v1`) only their KWin side speaks. None of this runs on sway/Hyprland/Niri.
- Services order after `plasma-kwin_wayland.service`; shell runs as `qs --no-duplicate -c kos` from `kos-shell.service`.

**Panel replacement: full takeover, not coexistence.** From [GettingStarted.md § "Desktop takeover and optional lockscreen"](https://github.com/NextKde/NextKde/blob/main/docs/GettingStarted.md):
> "Core installs `org.kos.desktop` and saves Plasma's previous ShellPackage before selecting the wallpaper-only desktop. DeskCenter owns files; Plasma no longer duplicates panels/folder view. Changes apply next login; uninstall restores the prior shell."

I.e. they ship their own **Plasma ShellPackage (look-and-feel/desktop containment)** that reduces plasmashell to a wallpaper-only shell — panels and folder view are gone — with the previous package backed up and restored on uninstall. That's the cleanest known mechanism for "replace Plasma panels without killing plasmashell," and it sidesteps the GHNS/KConfigXT losses only by keeping plasmashell alive as a wallpaper service. KWin shortcuts are de-conflicted in code (`platform/src/daemon/KWinShortcutConflicts.cpp`).

**Takeover mechanics verified in `tools/kosctl`** (a 2,254-line bash script): it reads the current `plasmashellrc [Shell] ShellPackage` key (`kreadconfig6`), backs it up, installs `kos_shell_id=org.kos.desktop`, and writes `ShellPackage=org.kos.desktop` back with `kwriteconfig6` — the script comments note "desktop containments are carried over, rewritten to the wallpaper-only" package, and that `plasma-apply-lookandfeel`/systemsettings resolve the same key ([tools/kosctl](https://github.com/NextKde/NextKde/blob/main/tools/kosctl)). No plasmashell kill, no panel-hiding hacks: plasmashell is *re-pointed* at a shell package that simply has no panels.

## 7) Runtime & Install

- **Launch chain** ([ProjectArchitecture.md](https://github.com/NextKde/NextKde/blob/main/docs/ProjectArchitecture.md)): three systemd `--user` units — `kos-shell.service` (`/usr/bin/qs --no-duplicate -c kos`, `KillMode=process`, `QS_DISABLE_FILE_WATCHER=1`), `kos-platform.service` (`~/.local/libexec/kos-platform daemon`), `kos-data.service` (Go daemon on `$XDG_RUNTIME_DIR/kos-data.sock`). All `PartOf=`/`WantedBy=graphical-session.target` and ordered **after `plasma-kwin_wayland.service`** because Plasma marks the session active before the Wayland socket is ready. Shell Requires platform, Wants data.
- **Install:** `./tools/kosctl update && doctor && install && start`. Deploys user-owned products under `~/.local`, copies the shell to **`~/.config/quickshell/kos`**, enables units for next login, never touches the running session; `kwinrc` edits use `kwriteconfig --notify false`. Uninstall removes binaries/units/shell but preserves state (`$XDG_STATE_HOME/quickshell/kos`). Everything is user-space **except** it must compile KWin plugins + C++/Go binaries against the host's Qt/KWin/KF6 `-devel` packages.
- **Requirements:** Plasma 6 Wayland, **KWin 6.6+**, **Quickshell 0.3.x**, Qt 6.6+, plus KF6/KWin dev packages, Go, CMake/Ninja, ONNX Runtime/OpenCV for the spatial wallpaper mode (`KOS_BUILD_SPATIAL=OFF` to skip).
- **Packaging:** full **Nix flake + `services.kos` NixOS module** ("Fully declarative — no manual steps", flake description: *"KOS Desktop Shell - iPadOS-style desktop for KDE Plasma 6"*) ([flake.nix](https://github.com/NextKde/NextKde/blob/main/flake.nix)); distro guides for Arch (primary), Debian 13, Ubuntu 26.04, openSUSE TW, and **Fedora 44 (community-contributed, "not official Fedora runtime acceptance")** — the Fedora recipe installs `quickshell kwin-devel libplasma-devel kdecoration-devel kf6-*-devel` etc. and `kosctl install` can pull missing build deps via dnf ([GettingStarted.md#fedora-44](https://github.com/NextKde/NextKde/blob/main/docs/GettingStarted.md)). **No AUR package** (AUR RPC: 0 results), no COPR/Flathub hosting; optional apps arrive as signed Flatpak *bundles* from GitHub Releases, not a Flatpak remote.
- **Bazzite verdict:** not installable under a no-layering rule as-is. It needs a compiler + `-devel` headers matching host KWin (host runs KWin 6.8.2) and Quickshell 0.3.x (Fedora dnf carries 0.2.1; COPR `errornointernet/quickshell` has 0.3.2). The only rule-compliant route would be a distrobox/toolbox build container with `~/.local` deployment — untested upstream — or the Nix flake. Live issue [#329](https://github.com/NextKde/NextKde/issues/329) shows the glass effect currently failing on **KWin 6.8.2 + NVIDIA** with shader `#version` conflicts — the exact host config — which underlines the fragility of compiled-plugin coupling.

## 8) Functional Gaps vs Plasma (what a KDE user loses/keeps)

| Plasma function | NextKde handling |
|---|---|
| KRunner | **Replaced, narrowly.** `modules/quicksearch/` offers app search, a window switcher, and clipboard history (modes: `app`/`window`/`clipboard` in `QuickSearch.qml`). No evidence of KRunner plugin bridging, web search, converters, or runner plugins. KRunner itself isn't killed — shortcuts register cooperatively through **KGlobalAccel QActions** in kos-platform (`ShortcutsService.qml` publishes defaults like `Meta+Space` launcher, `Meta+V` clipboard, `Meta+Tab` overview), so stock `Alt+Space`/`Alt+F2` KRunner should still fire. |
| Notifications | **Replaced.** KOS registers as the freedesktop notification-daemon owner; Plasma's notification popups/DAW history are gone (docs warn another daemon can block KOS's owner). Full reimplementation: history, per-app policy, sounds, DND. |
| SNI system tray | **Replaced.** `PlatformServerTray.cpp` implements the StatusNotifier host; `TrayIdentity.mjs` does icon/identity resolution with monochrome template mapping. |
| Panel/widgets | **Replaced** by bar + dock + widgets; Plasma activities have **no counterpart** found anywhere in tree/docs (virtual-desktop Overview exists at `Meta+Tab`). |
| Screen edges | No Plasma edge-integration; instead auto-hide bar/dock + KWin effects (`dock-window-animation`, `context-menu-input` routes desktop context-menu input). |
| Global menu | **Replaced** with its own in-bar global menu (`GlobalMenu.qml` + `PlatformServerAppMenu.cpp`). |
| GHNS / Plasma themes | Gone by construction (no panels). Wallpaper theming is own system (`ThemePackFormat.md`); fonts integrate with Plasma 6.6–6.8 only. |
| Lock/login | Lock screen reimplemented as optional package (`WakeAuthentication.qml` — auth mechanism not verified); **SDDM theme ships with no supported installer**. |
| Discover | Apps update through their own signed-catalog agent ("Discover is not promised to detect these GitHub bundle updates") — a parallel app universe. |

## 9) Community Traction

- **863 stars / 70 forks / 27 open issues** as of 2026-11-13 ([repo](https://github.com/NextKde/NextKde)). For calibration: quickshell itself is 3.2k stars, noctalia 12.0k, caelestia-dots/shell 13.4k — NextKde is younger and smaller but rising fast in its first weeks of public releases (v0.1.0/0.1.1 on 2026-10-19/20).
- **Cadence vs support:** 600 commits since 2026-08-12 (508 in Oct, 92 in Nov ≈ 7/day) vs only ~11 non-PR issues in the last-100-items window — a build-heavy project with light user-support load so far. Recent issues are mostly **Chinese-language** (#371, #363, #328), matching the Chinese-first website ([nextkde.github.io](https://nextkde.github.io/.github/)); audience is currently CN + curious onlookers.
- **Coverage found:** one YouTube walkthrough (PT-BR): ["NextKDE - Seria um novo KDE Plasma?" — Prof. Juliano Ramos](https://www.youtube.com/watch?v=bR3t-iWOtqY). **Zero Hacker News stories** (Algolia search empty). Reddit search blocked from this host — unverified. Minor directory listings only (reporank.net, TrendForge, OpenToolsHub, GitReverse).
- **Works-today vs coming-soon:** core desktop works via source install (with real bug reports flowing, e.g. [#345](https://github.com/NextKde/NextKde/issues/345) battery popup glitch, [#329](https://github.com/NextKde/NextKde/issues/329) NVIDIA glass failure); Mail + File Manager "planned", multi-display layouts and accessibility listed as next steps (README). The v0.1.x release assets even include self-authored "validation" reports — engineering hygiene is unusually high (CI with KWin 6.6/6.7/6.8 SDK builds, CTest layers, qmllint, a `block-ai-coauthor.yml` workflow).
- The project website's honesty is notable: *"玻璃不是装饰。它在 KWin 合成器里折射你窗口后面的光"* — "Glass is not decoration. It refracts the light behind your windows **in the KWin compositor**" ([site](https://nextkde.github.io/.github/)).

## 10) Comparable Shells Landscape (Quickshell niche)

- **noctalia-shell** (noctalia-dev) — 12.0k★, MIT; sleek general-purpose Wayland shell (Hyprland-first), layer-shell chrome, no KWin-specific plugins ([repo](https://github.com/noctalia-dev/noctalia-shell)).
- **Caelestia shell** (caelestia-dots) — 13.4k★, GPL-3.0; "fluid, morphing shell" tied to the Caelestia dotfiles ecosystem (Arch/Hyprland-centric) ([repo](https://github.com/caelestia-dots/shell)).
- **DankMaterialShell** — Material-3 Quickshell shell with an active plugin ecosystem (wallpaperengine, docker-manager, emoji-launcher plugins verified); main-repo location unverified this session.
- **Vicinae** — a launcher-centric Quickshell surface with extensions bridging *into* noctalia/DMS (e.g. `brpaz/vicinae-noctalia`, `Costeer/vicinae-dms-integration`), evidencing an IPC-extension pattern NextKde also adopts.
- Sibling research lanes already cover `end-4dots-kde` (ladybug-me) and `quickshell-kde` (SnTR370) — deliberately omitted here.
- **NextKde's unique position:** the only shell in this list that goes **compositor-native on KWin** — private Wayland protocols, six KWin plugins, a decoration plugin, and a KGlobalAccel-registered shortcut story — instead of staying compositor-agnostic. It is "KDE Plasma 6 + Quickshell fused," not "Quickshell chrome over any compositor."

## 11) What The Fleet Can Steal (porting lessons for Bazzite/Plasma 6)

1. **The `plasmashellrc [Shell] ShellPackage` re-point is the legitimate panel-takeover primitive.** Backup the key, install a wallpaper-only shell package (`org.kos.desktop` pattern), write the key with `kwriteconfig6 --notify false`, restore on uninstall. Pure user-space (kwriteconfig6 + a package in `~/.local/share/plasma/…`), no plasmashell killing, no rpm-ostree layering, reversible per-login. This is the strongest known counter-technique to the "Quickshell can only be companion chrome" conclusion — the panel disappears while plasmashell keeps providing wallpaper + KWin integration.
2. **KGlobalAccel via a small daemon** (QActions under one component, Exec lines targeting `qs ipc call`) buys real global shortcuts that coexist with KDE's shortcut infra — no panel needed, no fighting over Meta.
3. **systemd unit ordering for Plasma 6 Wayland:** `After=plasma-kwin_wayland.service` + `PartOf=/WantedBy=graphical-session.target`, `KillMode=process` on the shell unit so restarted shells don't kill children; pinned `StateDir` pragma so `qs -c` and `qs -p` share state ([shell.qml](https://github.com/NextKde/NextKde/blob/main/shell/shell.qml)).
4. **Settings pattern worth copying:** JSON in `Quickshell.stateDir` with schema versioning + migrations, debounced atomic writes (`QSaveFile`), and a *separate* settings process driving the shell over IPC snapshots — kills the "settings page inside the shell process" reload problem.
5. **The QML-only glass subset is portable; the compositor subset is not.** `squircle.frag`/`scene_liquid.frag`/`stage_*.qsb` + `MultiEffect` blur + OKLab-tinted translucency deliver a convincing "liquid glass" feel on stock KWin blur with zero compiled deps. The refraction (`snells-glass.glsl`), continuous corners, and compositor-drawn buttons require forked KWin plugins — fragile against KWin point releases (see #329 on 6.8.2/NVIDIA, the fleet's exact KWin) and off-limits under the no-compiled-deps rule.
6. **SNI host + notification-daemon ownership from a helper daemon** (here C++; the fleet could do it from Quickshell's own `SystemTray`/`NotificationServer` QML APIs) is the full tray/notification replacement path — NextKde proves it can be done to Plasma-grade, but also shows the cost: their daemon is ~50 source files.
7. **Chinese-market lesson:** a polished bilingual site + demo GIFs + releases with validation artifacts got an OS-level project from 0→863★ in weeks with no Reddit/HN presence at all.

## 12) Unverified / Open Questions

- **What "KOS" expands to** — never stated in repo, docs, or site; possibly nothing (brand).
- **Aug–Sep 2026 commit gap** (0 commits in the 3-month window before Oct's 508): private development then public push, or history rewrite? Repo `created_at` is 2025-11-07 but the org appeared 2026-09-23; cause unknown.
- **Reddit/HN reception** — Reddit blocked from this host (403), HN empty; only one PT-BR YouTube demo found. Real Western-community traction unmeasured.
- **Lock-screen auth mechanism** (`WakeAuthentication.qml`) — PAM? authenticator stub is all that's visible in tests; not verified.
- **QuickSearch depth** — code shows app/window/clipboard modes; whether file search or anything KRunner-plugin-like exists deeper in the module is unverified.
- **How `org.kos.desktop` shell-package files are generated/installed** — kosctl comments say containments are "carried over, rewritten"; the package-generation step wasn't traced end-to-end.
- **DankMaterialShell main repo location/star count** — 404s on the remembered path; plugin repos confirm it exists.
- **Fedora/Bazzite real-world success** — the Fedora 44 recipe is explicitly "community-contributed… not official Fedora runtime acceptance"; no Bazzite report found.
- **Star-history timeline** (growth curve) — not scraped.

---

## Checked vs Not-Checked

**Checked (primary sources):** GitHub API repo/org/contributors/releases/tags/commits/issues; README.md + README install section verbatim; full git tree (1,713 paths); `docs/ProjectArchitecture.md`, `GettingStarted.md` (incl. Fedora 44 recipe), `AppearanceArchitecture.md` (first half), `WindowAppearance.md` (first half); `kwin/glass-effect/README.md`; `tools/kosctl` (ShellPackage takeover grep); `shell/shell.qml`; `QuickSearch.qml`, `ShortcutsService.qml` heads; `flake.nix`; module inventories for bar/dock/notifications/quicksearch/applauncher/overview/wallpaper/stage/platform; AUR RPC (no package); HN Algolia (no stories); YouTube oEmbed (one PT-BR demo); nextkde.github.io text; star counts for noctalia/caelestia/quickshell.

**Not checked:** Reddit threads (403), KDE Discuss (JS-walled), lock-screen auth internals, kosctl full 2.2k-line flow, NixOS module full body, DepthEngine/WallpaperArchitecture docs, appCatalog signing details, actual runtime behavior on any machine, glass-effect upstream repo diffs, DMS main repo.

