---
title: "Quickshell Framework Capabilities on KDE Plasma 6 — Late-2026 Dossier"
date: 2026-11-12
researcher: fleet subagent (kde-simplicity-research lane 13)
scope: Quickshell framework, packaging, module ecosystem, alternative-shell landscape (NOT end-4dots-kde, NextKde/KOS, quickshell-kde architecture, Omarchy plugins)
source_urls:
  - https://quickshell.org/
  - https://quickshell.org/about
  - https://quickshell.org/changelog
  - https://quickshell.org/docs/v0.3.2/guide
  - https://quickshell.org/docs/v0.3.2/guide/install-setup
  - https://quickshell.org/docs/v0.3.2/guide/faq
  - https://quickshell.org/docs/v0.3.2/guide/introduction
  - https://quickshell.org/docs/v0.3.2/types
  - https://quickshell.org/docs/v0.3.2/types/Quickshell/PanelWindow
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/WlrLayershell
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/BackgroundEffect
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/ScreencopyView
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.WindowManager
  - https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.SystemTray/SystemTray
  - https://github.com/quickshell-mirror/quickshell
  - https://api.github.com/repos/quickshell-mirror/quickshell
  - https://api.github.com/repos/quickshell-mirror/quickshell/releases
  - https://github.com/quickshell-mirror/quickshell/issues/910
  - https://github.com/quickshell-mirror/quickshell/issues/1340
  - https://github.com/quickshell-mirror/quickshell/issues/1190
  - https://github.com/quickshell-mirror/quickshell/pull/566
  - https://git.outfoxxed.me/quickshell/quickshell-examples
  - https://packages.fedoraproject.org/pkgs/quickshell/quickshell/
  - https://src.fedoraproject.org/rpms/quickshell
  - https://src.fedoraproject.org/rpms/quickshell/raw/rawhide/f/quickshell.spec
  - https://copr.fedorainfracloud.org/api_3/package/list?ownername=errornointernet&projectname=quickshell&with_latest_build=True
  - https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/qu/quickshell/package.nix
  - https://archlinux.org/packages/extra/x86_64/quickshell/json/
  - https://aur.archlinux.org/packages/quickshell-git
  - https://formulae.brew.sh/api/formula/quickshell.json
  - https://github.com/elkowar/eww
  - https://github.com/noctalia-dev/noctalia-shell
  - https://github.com/kevichi7/DankMaterialShell
  - https://github.com/wayle-rs/wayle
  - https://danklinux.com/docs/dankmaterialshell/installation
  - https://kde.org/announcements/megarelease/6/
  - https://www.neowin.net/news/after-21-years-of-waiting-kde-plasma-is-finally-adding-this-long-requested-feature/
  - https://www.phoronix.com/forums/forum/linux-graphics-x-org-drivers/wayland-display-server/1484927-wayland-merges-new-screen-capture-protocols
---

# Quickshell Framework Capabilities on KDE Plasma 6

Technical capability dossier for the Foyer campaign context: can Quickshell serve as a
Plasma-6 shell platform on Bazzite (immutable rpm-ostree Fedora 45), and what are the
framework-level facts? Fleet-known constraints apply: user-space only, no PyKDE,
never QA on the live desktop.

## 1) Project State & Governance

**Current version: v0.3.2, released 2026-10-08** ([quickshell.org](https://quickshell.org/) banner, [changelog](https://quickshell.org/changelog), confirmed via [GitHub releases API](https://api.github.com/repos/quickshell-mirror/quickshell/releases)).

Release history (all six releases, from the changelog + releases API):

| Tag | Date | Notes |
|-----|------|-------|
| v0.1.0 | 2025-06-13 | "Initial release" |
| v0.2.0 | 2025-07-27 | root-relative `qs.` imports, Bluetooth module |
| v0.2.1 | 2025-10-12 | Qt 6.10 support; what Fedora 45 ships |
| v0.3.0 | 2026-05-04 | largest delta: polkit, idle, ext-workspace, blur, network (see §2) |
| v0.3.1 | 2026-08-21 | crash-fix release |
| v0.3.2 | 2026-10-08 | Qt 6.12 support; crash fixes |

Cadence is **irregular, roughly 2–4 months between releases** (6 releases in ~16 months), with a `master` branch that moves continuously (last push to the mirror 2026-10-22 per GitHub API).

**Repo topology.** The canonical forge is outfoxxed's own — `git.outfoxxed.me/outfoxxed/quickshell` (this is the URL the install docs use for the flake: [install-setup/Nix](https://quickshell.org/docs/v0.3.2/guide/install-setup)). GitHub `outfoxxed/quickshell` now 301-redirects to **`quickshell-mirror/quickshell`** (repo id 766993934, `fork: false`), i.e. the GitHub org was renamed to `quickshell-mirror` and is explicitly a mirror of the self-hosted forge. Mirror stats (GitHub API, 2026-11-12): **3,228 stars, 259 forks, 837 open issues, not archived, actively pushed**.

**Maintainer & governance.** Sole maintainer **outfoxxed**; community support via Matrix space `#quickshell:outfoxxed.me` bridged to a Discord server ([Usage Guide](https://quickshell.org/docs/v0.3.2/guide)). No foundation, CLA, or formal governance documents were found (searched repo + site). The project's own description: "Flexible toolkit for making desktop shells with QtQuick, for Wayland and X11" (GitHub API).

**License: LGPL-3.0** (GitHub API `license.spdx_id`).

**Language mix** (GitHub languages API, bytes): C++ 1,819,296 · QML 67,466 · CMake 55,768 · Nix 10,077 · Just 1,468 · GLSL 1,030. So: a **large C++ engine** (the Qt/Wayland integration layer, ~96% of code) exposing a **QML-only configuration surface**. Shell authors write QML; they never compile anything. This is the load-bearing fact for Bazzite: a shell config is pure user-space QML, but the `qs` binary itself must be packaged.

**Stability policy (project's own words).**
- Install page NOTE: "Quickshell is still in a somewhat early stage of development. There will be breaking changes before 1.0, however a migration guide will be provided." ([install-setup](https://quickshell.org/docs/v0.3.2/guide/install-setup))
- FAQ, "What will breaking changes look like": changes "can span the APIs exposed by Quickshell, as well as best practice across all APIs, but will not change the language syntax or anything exposed by Qt… Migration guides will be provided between each release version." ([FAQ](https://quickshell.org/docs/v0.3.2/guide/faq))
- Empirically, breaking changes land in minor bumps (0.2.0 and 0.3.0 both have "Breaking Changes" changelog sections; patch releases 0.2.1/0.3.1/0.3.2 do not). Pre-1.0 semver discipline is real but the project is explicit that it is not stable yet.

**Build requirements.** Documented in [BUILD.md on the canonical forge](https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md) (not re-fetched this pass). From the changelog "Packaging Changes" (v0.3.0): `glib` + `polkit` deps when building polkit-agent support; `vulkan-headers` build-time dep for the Vulkan screencopy backend; `cpptrace` replaces breakpad as the crash handler; **`libdrm` is now an unconditionally required direct dependency**. Qt window: 6.10 support added in 0.2.1, **Qt 6.12 support added in 0.3.2** — so 0.3.x tracks current Qt (Fedora 45's Qt 6.11-era stack is in-range). Optional runtime addons per install docs: `qtsvg`, `qtimageformats`, `qtmultimedia`, `qt5compat` (gaussian blur effects).

**Self-description of scope**: "Quickshell is a relatively low-level tool compared to simple status bars like Waybar. When writing a Quickshell configuration, you are not just changing styles and layouts, but practically programming" ([about](https://quickshell.org/about)). It is a toolkit, not a desktop: bars, widgets, lockscreens, and display managers ([about](https://quickshell.org/about)).

## 2) 0.2 → 0.3 Delta

Full changelog captured from [quickshell.org/changelog](https://quickshell.org/changelog) (all six releases, single page). Material changes, KDE-relevance flagged:

### v0.2.0 (2025-07-27) — config-system release
- **Root-relative imports**: `import qs.path.to.module` replaces `root:/` imports, supported by qmlls (LSP). `.qmlls.ini` auto-managed at shell root.
- **Bluetooth module** (BlueZ: connect/disconnect, info, non-authenticated pairing; authenticated pairing explicitly not in 0.2).
- `HyprlandToplevel` + Hyprland window-management APIs; `Quickshell.execDetached()`; `Process.exec()`; notification inline replies; `//@ pragma Internal`.
- Breaking: no relative paths above the shell dir; `PanelWindow` Automatic exclusion mode adds exclusion zone for single-anchor panels; `QT_QUICK_CONTROLS_STYLE`/`QT_STYLE_OVERRIDE` ignored unless `//@ pragma RespectSystemStyle` (this is the theming-relevant change — see §6).
- Rename: `Quickshell.shellRoot` → `Quickshell.shellDir`.

### v0.2.1 (2025-10-12) — maintenance
- Real-time tracking of desktop-entry changes; Qt 6.10 support; pipewire/greetd/monitor crash fixes. This is the version in Fedora 45 proper (fleet-verified: `quickshell-0.2.1^git20260209-5.fc45` via dnf on gdtower).

### v0.3.0 (2026-05-04) — the release that changes the KDE story
New features (changelog wording, KDE-relevance annotated):
- **Polkit agent support** — a Quickshell config can now be the polkit authentication agent, previously the job of `polkit-kde-agent` in a Plasma session.
- **Wayland idle inhibitors + idle timeouts** (ext-idle-notify family).
- **Inhibiting wayland compositor shortcuts for focused windows** (shortcut-inhibit).
- **Network management support** (NetworkManager backend, PR #96).
- **Generic `WindowManager` interface implementing ext-workspace** — first compositor-agnostic workspace abstraction beyond Hyprland/I3/Sway (KDE-relevant: KWin's workspace protocol support determines whether this works on Plasma — see §4).
- **ext-background-effect window blur support** — real compositor blur behind surfaces where the compositor implements the protocol (KDE-relevant: KWin's implementation status — see §4/§8).
- **Vulkan support for screencopy** (`ScreencopyView` can now render via a Vulkan backend; still the wlr-screencopy family — see §4 for the KWin gap).
- IPC signal listeners (IPC can now push events, not just call functions); IPC ops filter instances to the current display connection by default.
- Quickshell version checking + version-gated preprocessing (`//@ pragma Version`); system-icon-theme detection for icons; per-corner radius on `Region`; `ColorQuantizer` region selection (accent-color extraction); dialog window support on `FloatingWindow`; move/resize event handling; minimized/maximized/fullscreen props on `FloatingWindow`; PipeWire reconnect + peak detection (audio meters); focus grabbing from popup windows; Hyprland lua-config support.
- **Breaking**: config paths are no longer canonicalized — **shell id is derived from the symlink path**, so Nix-style symlinked configs get a new shell id (and thus new default state/cache dirs) on upgrade; explicit shell ids avoid this.
- Packaging: `glib`+`polkit` deps (polkit build), `vulkan-headers` (build), `libdrm` unconditional, `cpptrace` replaces breakpad, `CRASH_REPORTER` cmake var → `CRASH_HANDLER`.
- Env/pragma surface grew: `QS_DISABLE_FILE_WATCHER`, `QS_DISABLE_CRASH_HANDLER`, `QS_CRASHREPORT_URL`, `QS_APP_ID`, `QS_DROP_EXPENSIVE_FONTS`, `DefaultEnv` pragma; unrecognized pragmas no longer a hard error (forward-compat for configs across versions).

### v0.3.1 (2026-08-21) — stability pass
- ~25 crash fixes, notable for always-on shells: session-lock crashes on sleep/wake/DPMS/unlock; crashes on monitor unplug (`WindowsetProjection.screens`); IPC calls from children of a crashed-and-relaunched process; `qs kill` now waits; `JsonAdapter`, `ScreencopyView` failure paths, X11 `PanelWindow` hide crash. Zero new features.

### v0.3.2 (2026-10-08) — current
- Qt 6.12 support; Hyprland's new workspace address format; fixes: PAM subprocess misbehavior crashes, reentrant session-lock creation crashes, networking state after NetworkManager restart, accessibility info for Quickshell windows, `WlSessionLockSurface.screen` null on monitor plug.

### What did NOT change 0.2→0.3 (negative findings, same changelog)
- No new first-class compositor integration: the Hyprland module remains the only deep WM integration (I3/Sway via the I3 module); the generic path is ext-workspace/layer-shell only.
- No clipboard service appears anywhere in the 0.2/0.3 changelogs (no `wl-clipboard`-style or data-control protocol integration announced).
- No change to screen-capture protocol family beyond the Vulkan backend (no PipeWire-desktop-portal capture announced for `ScreencopyView`).
- No theming system added in 0.3 (see §6).

## 3) Distribution & Packaging Matrix

| Channel | Package | Version | Evidence |
|---------|---------|---------|----------|
| Fedora 45 (official) | `quickshell` | `0.2.1^git20260209.dacfa9d-5.fc45` | [packages.fedoraproject.org](https://packages.fedoraproject.org/pkgs/quickshell/quickshell/) releases table; fleet-verified live via dnf on gdtower |
| Fedora 44 (official) | `quickshell` | `0.2.1^git20260209.dacfa9d-5.fc44` | same page |
| Fedora Rawhide (official) | `quickshell` | `0.2.1^git20260209.dacfa9d-6.fc46` | same page — **Rawhide has NOT moved to 0.3.x** |
| COPR `errornointernet/quickshell` | `quickshell` | **0.3.2-1** (src.rpm), chroots incl. `fedora-45-x86_64`, `fedora-44-x86_64`, rawhide, epel-10, aarch64 | [COPR api_3 package list](https://copr.fedorainfracloud.org/api_3/package/list?ownername=errornointernet&projectname=quickshell&with_latest_build=True); auto-rebuilds from [ErrorNoInternet/rpm-packages](https://github.com/ErrorNoInternet/rpm-packages) |
| COPR (same) | `quickshell-git` | tracks master | [install-setup/Fedora COPR](https://quickshell.org/docs/v0.3.2/guide/install-setup) (COPR HTML is behind an Anubis bot-wall; verified via API instead) |
| nixpkgs master | `quickshell` | 0.3.2 | [pkgs/by-name/qu/quickshell/package.nix@master](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/qu/quickshell/package.nix) |
| nixpkgs release-26.05 | `quickshell` | 0.3.0 | same file @release-26.05 |
| nixpkgs release-25.11 | `quickshell` | 0.2.1 | same file @release-25.11 |
| Arch official (`extra`) | `quickshell` | **0.3.2-1** (x86_64, committed 2026-10-08) | [archlinux.org packages JSON](https://archlinux.org/packages/extra/x86_64/quickshell/json/) |
| AUR | `quickshell-git` | 0.3.0.r0.g59e9c47-1, 18 votes | [AUR RPC](https://aur.archlinux.org/rpc/v5/info?arg[]=quickshell-git) (no plain `quickshell` in AUR — official repo carries releases) |
| Homebrew | — | **no formula, no cask** | formulae.brew.sh API checked 2026-11-12, both 404 |
| Debian unstable/testing | `quickshell` | (version not checked) | [install-setup/Debian](https://quickshell.org/docs/v0.3.2/guide/install-setup) |
| Ubuntu PPA `avengemedia/danklinux`, openSUSE OBS `home:AvengeMedia:danklinux`, Gentoo GURU `gui-apps/quickshell`, Guix `(gnu packages wm)` | `quickshell` (+ `-git` variants on PPA/OBS) | (not checked) | same install page |

**Fedora spec facts** ([src.fedoraproject.org/rpms/quickshell rawhide spec](https://src.fedoraproject.org/rpms/quickshell/raw/rawhide/f/quickshell.spec)): `Version: 0.2.1` with git snapshot `%global commit dacfa9de… commitdate 20260209`; License `LGPL-3.0-or-later and BSD-3-Clause and HPND-sell-variant`; maintainers **ngompa, errornointernet** ([packages page](https://packages.fedoraproject.org/pkgs/quickshell/quickshell/)). There is no spec in the upstream repo — packaging lives in Fedora dist-git, as usual.

**Fleet-relevant reading of the matrix:**
- Bazzite (F45 base) gets **0.2.1-era** quickshell from official repos; everything that changed the KDE story in §2 (polkit agent, ext-workspace WindowManager, BackgroundEffect, idle/shortcut inhibit) is **0.3-only → COPR or build-from-source**.
- The COPR `fedora-45-x86_64` chroot exists, but on rpm-ostree that means layering (fleet-prohibited) or distrobox (session-integration caveats), or a manual user-space build per [BUILD.md](https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md) — note 0.3.0 made `libdrm` an unconditional dep and added `vulkan-headers` as build-time dep, plus `glib`+`polkit` when polkit support is on.
- The COPR is also the build home of the DankLinux ecosystem (it companion-builds `breakpad`/`cpptrace`, and DMS docs point users there for `quickshell-git`, `matugen`, etc. — [danklinux install docs](https://danklinux.com/docs/dankmaterialshell/installation)), so it tracks upstream releases closely (0.3.2-1 built within days of the tag).

## 4) KWin Compatibility

**What Quickshell itself says about KDE: almost nothing, by design.** The docs describe Quickshell as compositor-agnostic toolkit plumbing: windowing via "Wayland and X11", WM integrations "for Hyprland, I3, and Sway" ([about](https://quickshell.org/about)). The FAQ's only WM-compat guidance is "Work with an unsupported WM": roll your own IPC over `Socket`/`Process` ([FAQ](https://quickshell.org/docs/v0.3.2/guide/faq)). There is **no compositor support matrix page** in the 0.3.2 docs, no KWin detection code documented, and no KDE-specific code path mentioned anywhere. `PanelWindow` is documented as the platform-independent wrapper, with `WlrLayershell` as its Wayland backing using [zwlr_layer_shell_v1](https://wayland.app/protocols/wlr-layer-shell-unstable-v1) ([WlrLayershell docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/WlrLayershell)).

**Protocol-by-protocol on KWin (fleet fact: host libkwin 6.8.2; layer-shell since Plasma 5.20 — parent-verified):**

| Quickshell surface | Protocol(s) | KWin status |
|---|---|---|
| `PanelWindow`/`WlrLayershell` | `zwlr_layer_shell_v1` | **Works** — KWin implements since 5.20 (fleet-verified); anchors, margins, exclusive zones, layers all map |
| `WindowManager` module (0.3.0) | `ext-workspace-v1` only ("Support will be expanded in future releases" — [WindowManager docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.WindowManager)) | **Works on Plasma ≥ 6.7** — KWin adopted ext-workspace for per-screen virtual desktops in Plasma 6.7 ([Neowin on KDE TWIP 2026-04-18](https://www.neowin.net/news/after-21-years-of-waiting-kde-plasma-is-finally-adding-this-long-requested-feature/)); fleet's 6.8.2 qualifies. QS↔KWin binding not directly confirmed in the tracker |
| `BackgroundEffect` (0.3.0) | `ext-background-effect-v1` ("requires the compositor support the protocol" — [docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/BackgroundEffect); landed via [PR #566](https://github.com/quickshell-mirror/quickshell/pull/566)) | **Not available** — no evidence found that KWin implements ext-background-effect-v1; Plasma's own blur applies to Plasma surfaces (the existence of force-blur effect forks like [kwin-effects-forceblur](https://github.com/taj-ny/kwin-effects-forceblur) shows stock KWin doesn't blur arbitrary layer-shell clients). Flagged unverified at primary source |
| `ScreencopyView` — monitor capture | `wlr-screencopy-unstable` **or** `ext-image-copy-capture-v1` + `ext-capture-source-v1` ([docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/ScreencopyView)) | **Conditional** — KWin does not implement wlr-screencopy (wlroots protocol); the newer ext pair was [merged into wayland-protocols](https://www.phoronix.com/forums/forum/linux-graphics-x-org-drivers/wayland-display-server/1484927-wayland-merges-new-screen-capture-protocols) and is the plausible KWin path, but **KWin's implementation version was not verifiable this pass** (search polluted) — treat as untested |
| `ScreencopyView` — window capture | `hyprland-toplevel-export-v1` only | **Broken on KWin** — Hyprland-only by construction ([docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/ScreencopyView)) |
| `WlSessionLock` | ext-session-lock | Works — KWin implements ext-session-lock; QS also guards crashes when unsupported ([#66](https://github.com/quickshell-mirror/quickshell/issues/66)) |
| `IdleInhibitor`/`IdleMonitor` (0.3.0) | ext-idle family | Expected to work (KWin implements ext-idle-notify); not directly verified |
| `Toplevel`/`ToplevelManager` | wlr-foreign-toplevel-management | Unverified on KWin — no docs statement; no tracker confirmation |
| `Quickshell.Hyprland`, `Quickshell.I3` | Hyprland IPC, i3 IPC | N/A on KWin (Hyprland/I3/Sway only) |
| X11 windowing | — | Works (PanelWindow on X11 per changelogs), irrelevant for Plasma 6 Wayland sessions |

**Upstream issue evidence naming KWin/KDE/Plasma** (tracker search 2026-11-12: `kwin` 7 hits, `kde` 41, `plasma` 15 — mostly crash reports; KDE-specific substantive ones):
- [#910](https://github.com/quickshell-mirror/quickshell/issues/910) (open): SIGSEGV in `WlrLayershell::disownWindow` on compositor-initiated layer-surface close (sleep/resume, monitor changes). Filed on Hyprland, but a commenter reproduced **on KWin / Plasma 6.7.5, quickshell-git 0.3.1, running the caelestia shell KDE port** — confirms real-world Quickshell-on-KWin usage and that this crash class is not Hyprland-specific.
- [#1340](https://github.com/quickshell-mirror/quickshell/issues/1340) (open): SIGSEGV when the DRM link drops on DPMS off→on; comments include a repro on **KDE Plasma 6 / KWin 6.8.2 with caelestia-kde** on top.
- [#1283](https://github.com/quickshell-mirror/quickshell/issues/1283): crash on "Fedora KDE 44" (but running sway — illustrates that "KDE" hits are often just distro names).
- Positive signal: users are running Quickshell shells (caelestia-kde) on Plasma 6.7/6.8 KWin sessions at all — as early adopters hitting edge bugs, not as a supported path.

**wlroots vs KWin, summarized:** Quickshell's center of gravity is the wlroots/Hyprland protocol family. On KWin you keep: layer-shell panels, session lock, idle, SNI tray, notifications, MPRIS, PipeWire, UPower, Bluetooth, Networking (NM), polkit (0.3+), ext-workspace (Plasma 6.7+). You lose or risk: window thumbnails/capture of individual windows (`hyprland-toplevel-export`), wlr-screencopy-based fake blur (only ext-image-copy-capture path might rescue monitor capture), real compositor blur (`ext-background-effect` not evidenced in KWin), and all Hyprland-module features (focus grabs, layer rules as Hyprland concepts, toplevels, workspace IPC).

## 5) Official Module Ecosystem

**What ships in the binary (the definitive list — [Module Listing, docs v0.3.2](https://quickshell.org/docs/v0.3.2/types)):**

| Module | Provides |
|---|---|
| `Quickshell` | Core: `PanelWindow`, `FloatingWindow`, `QsWindow`, `Variants`, `Scope`, `SystemClock`, `ShellRoot`, icon/desktop-entry APIs |
| `Quickshell.Io` | `Process`, `Socket`, `SocketServer`, `FileView`, `StdioCollector`, `SplitParser`, `IpcHandler` |
| `Quickshell.Wayland` | `WlrLayershell`, `WlSessionLock(+Surface)`, `Toplevel(Manager)`, `ScreencopyView`, `BackgroundEffect`, `IdleInhibitor`, `IdleMonitor`, `ShortcutInhibitor` |
| `Quickshell.WindowManager` | Generic `WindowManager`/`Windowset`/`ScreenProjection` over ext-workspace-v1 |
| `Quickshell.Hyprland` | Hyprland IPC: workspaces, toplevels, events, focus grabs |
| `Quickshell.I3` | i3/Sway IPC |
| `Quickshell.Bluetooth` | BlueZ |
| `Quickshell.Networking` | NetworkManager (0.3.0) |
| `Quickshell.DBusMenu` | DBusMenu (tray menus) |
| `Quickshell.Services.SystemTray` | SNI tray host: `SystemTray` singleton + `SystemTrayItem` |
| `Quickshell.Services.Notifications` | notification-daemon implementation |
| `Quickshell.Services.Pipewire` | audio nodes, volumes, peak meters |
| `Quickshell.Services.Mpris` | media players |
| `Quickshell.Services.UPower` | battery |
| `Quickshell.Services.Pam` | PAM auth (lockscreens) |
| `Quickshell.Services.Greetd` | greeter/DM building |
| `Quickshell.Services.Polkit` | polkit agent (0.3.0) |
| `Quickshell.Widgets` | bundled widget primitives (e.g. `ClippingWrapperRectangle`, `IconImage`) |

**What does NOT ship: a bar, dock, launcher, wallpaper, menu, OSD, clipboard, or power-menu.** Those are all config-level code. The [official examples repo](https://git.outfoxxed.me/quickshell/quickshell-examples) (100% QML, 18 commits, last commit 2025-07-28) contains only seven small demos: `activate_linux`, `focus_following_panel`, `lockscreen`, `mixer`, `reload-popup`, `volume-osd`, `wlogout`. So "the official module list" = the 18 QML modules above, versioned **with the engine release** (no independent versioning); configs gate engine features with `//@ pragma` + version checks added in 0.3.0 ([changelog](https://quickshell.org/changelog)).

**Install mechanics (all verified from [Introduction — Config Files](https://quickshell.org/docs/v0.3.2/guide/introduction)):**
- Configs are discovered as `~/.config/quickshell/<name>/shell.qml` (any XDG config dir); pick with `qs -c <name>`; arbitrary paths/raw files with `qs -p/--path`.
- There is **no module registry and no `qs install`** — distribution of shells is `git clone` into that directory (this is how Caelestia/Illogical-Impulse/noctalia-class setups distribute), or Nix (`quickshell.packages.<system>.default`, and `<pkg>.withModules [...]` to add extra QML modules to the engine's import path — [install-setup/Nix](https://quickshell.org/docs/v0.3.2/guide/install-setup)).
- Live reload on save is the dev loop; the FAQ warns against process-per-widget (memory) — a shell is one process.

**SNI/tray and the plasmashell collision.** SystemTray IS an official module: "Referencing the SystemTray singleton will make quickshell start tracking system tray contents" ([SystemTray docs](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.SystemTray/SystemTray)) — i.e., Quickshell instantiates its own StatusNotifierItem host/watcher, confirmed by tracker work on QS's watcher ([#1190](https://github.com/quickshell-mirror/quickshell/issues/1190) watcher keeps items that disconnect during registration; [#777](https://github.com/quickshell-mirror/quickshell/pull/777) SNI fallback handling; [#1096](https://github.com/quickshell-mirror/quickshell/issues/1096), [#1317](https://github.com/quickshell-mirror/quickshell/issues/1317), [#862](https://github.com/quickshell-mirror/quickshell/issues/862) real-world item quirks). The SNI design allows exactly one `org.kde.StatusNotifierWatcher` on the session bus; plasmashell's tray normally owns it in a Plasma session. Upstream documents nothing about Plasma co-existence, so the expected behaviors are: QS fails to acquire the watcher name (no tray items in QS) or, after plasmashell restarts, ownership flips and items migrate — **collision mechanics on a live Plasma session are inferred from the SNI design, not verified upstream**. Safer fleet posture: run the QS surface tray-less, or disable the Plasma tray, but never assume both trays show the same items.

## 6) Theming Reality

**Fleet's prior finding still holds in 0.3.2: there is no Breeze/Kirigami integration, and Quickshell actively walls off system styling.** Since 0.2.0, `QT_QUICK_CONTROLS_STYLE` and `QT_STYLE_OVERRIDE` are **ignored** unless the config opts in with `//@ pragma RespectSystemStyle` ([changelog v0.2.0 breaking changes](https://quickshell.org/changelog)). Nothing in the 0.3.x changelogs or the 18-module list adds a theme engine; Kirigami is not a dependency anywhere (deps are Qt6 + Wayland stack — §1). With `RespectSystemStyle`, a QtQuick Controls style installed on the host (Plasma ships a Breeze QQC2 style) can be picked up — that is the entire native-theming surface, and it is opt-in and undocumented for KDE.

What the engine does give themers as of 0.3: system icon-theme detection + `Quickshell.iconPath()` (0.3.0), `ColorQuantizer` region selection (accent extraction from images, 0.3.0), and per-corner `Region` radii. Theming beyond that lives entirely in shells:
- **DankMaterialShell**: theme registry + theme browser + `dms://` URI scheme ([commit history](https://github.com/kevichi7/DankMaterialShell)), Material-You palette generation via `matugen` from wallpaper ([danklinux install docs](https://danklinux.com/docs/dankmaterialshell/installation)).
- **Noctalia**: "theme/palette support, template application" as a first-class config feature ([README](https://github.com/noctalia-dev/noctalia-shell)).
- **Wayle**: color-token theme files + themes docs ([wayle.app/guide/themes](https://wayle.app/guide/themes)), with a community Catppuccin port ([GaetanQu/wayle](https://github.com/GaetanQu/wayle)).
- No cross-shell "qs themes" standard or `QuickshellConfiguration` framework exists; nothing in the docs or tracker suggests one.

## 7) Alternative Shell Landscape (what can replace/augment Plasma panels)

| Option | Runtime | Config | Maturity / activity (2026-11) | Install path | Targets KWin? |
|---|---|---|---|---|---|
| **Plasma 6 native shell** | KWin+plasmashell (QML/Kirigami) | GUI + `plasma-org.kde.plasma.desktop-appletsrc` | Shipping, 6.8.x era | built-in | **Yes (is KWin's shell)** |
| **Plasmoids (Plasma 6)** | Plasma 6 QML (PlasmaCore/QQC2) | per-widget | mature ecosystem | Get New Widgets / `~/.local/share/plasma/plasmoids` | **Yes** |
| **Quickshell configs** (Caelestia, Illogical-Impulse, zephyr, …, caelestia-kde) | Quickshell (C++ engine + QML) | QML, hot reload | engine 0.3.2; shells vary | git clone into `~/.config/quickshell`, `qs -c` | Layer-shell works on KWin; unsupported, see §4/§8 |
| **DankMaterialShell / dux-shell** | **Quickshell + Go backend** (QML 63% / Go 29%) | QML + `dms` CLI/IPC + GUI settings | very active (3,700+ commits; moved to duxlabs-dev org) | Arch `extra/dms-shell`, COPR (Fedora), Nix flake, OBS/PPA | **No** — "works best with niri, Hyprland, Sway, MangoWC, labwc, Scroll, Miracle WM… other Wayland compositors work with reduced features" ([README](https://github.com/kevichi7/DankMaterialShell)) |
| **Noctalia** | **native C++/Wayland/OpenGL ES — no Qt, no GTK** (rewritten off Quickshell) | TOML, hot reload, GUI overrides | very active, 12.0k★ | docs.noctalia.dev installer; meson build | **Not listed** — supports Niri/Hyprland/Sway/Scroll/Mango/Labwc/dwl; "other compositors may run Noctalia but can have reduced workspace, window, output, or session-action integration"; uses ext-workspace-v1 where present ([README](https://github.com/noctalia-dev/noctalia-shell)) |
| **Wayle** (HyprPanel successor) | **Rust + GTK4/Relm4** (gtk4-layer-shell) | TOML + `wayle-settings` GUI + CLI | young/pre-release, 1.0k★, active (pushed 2026-11-02) | AUR `wayle-bin`; cargo install; repology packages | **No** — requires wlr-layer-shell (KWin has it), but compositor modules target "Hyprland, Niri and Mango; Sway planned" ([README](https://github.com/wayle-rs/wayle)) |
| **EWW** | Rust + GTK3 | Yuck | 12.8k★, maintained | cargo/distros | Renders on KWin but broken there per fleet research (always-on-top, eww#393 open — fleet-known, not re-verified this pass) |
| **AGS (Aylur's GTK Shell)** | GTK layer-shell | JS | credible community option | distros/AUR | not re-verified this pass |

Context anchors: HyprPanel ARCHIVED 2026-04-27, Wayle is its pre-release successor (fleet-known). Plasma 6's own shell absorbed most "modern panel" asks natively: floating panels by default, redesigned panel settings, "Dodge Windows" auto-hide ([KDE MegaRelease 6](https://kde.org/announcements/megarelease/6/)); per-screen virtual desktops landed in Plasma 6.7 via ext-workspace ([Neowin](https://www.neowin.net/news/after-21-years-of-waiting-kde-plasma-is-finally-adding-this-long-requested-feature/)); Overview (Meta) is stock. Any panel-replacement proposal now competes against a Plasma shell that already floats, centers, dodges, and does per-screen desktops.

## 8) Known KWin Failure Modes

**Keyboard interactivity of layer surfaces.** `PanelWindow.focusable` defaults false; the underlying `WlrKeyboardFocus` modes are None/OnDemand/Exclusive ([PanelWindow](https://quickshell.org/docs/v0.3.2/types/Quickshell/PanelWindow), [WlrLayershell](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/WlrLayershell)). A tracker search for "keyboard interactivity" returns **zero** issues — no open KWin-specific keyboard-focus complaint cluster upstream. Launchers/spotlights need Exclusive or OnDemand+click; 0.3.0 added "support for grabbing focus from popup windows". KWin-specific behavior (e.g. Exclusive stealing from other surfaces, IME quirks) is **unverified — test in the nested kwin harness before trusting**.

**Focus stealing.** `aboveWindows: true` is the PanelWindow default (Top layer) — a mis-set layer or Exclusive keyboard focus will visually/interactively fight Plasma's own Top-layer surfaces (this is generic layer-shell semantics, not a KWin bug, but it is the co-existence hazard with plasmashell's panels).

**Exclusive-zone / reserved-space conflicts with the Plasma panel.** Both plasmashell and a QS `PanelWindow` with `exclusionMode: Auto/Normal` reserve struts on their anchors; two shells on the same edge → double reservation (gap stacking). QS knobs: `exclusiveZone`, `exclusionMode` (Auto default), margins ([PanelWindow docs](https://quickshell.org/docs/v0.3.2/types/Quickshell/PanelWindow)); note 0.2.0 changed Automatic exclusion for single-anchor panels and 0.2.0 margins-opposite-anchor now count into the zone. Fleet practice of "companion chrome on a free screen edge" sidesteps this entirely.

**Multi-monitor / DPMS / hotplug — the evidenced KWin crash class:**
- [#1340](https://github.com/quickshell-mirror/quickshell/issues/1340) (open): shell SIGSEGV when the DRM link drops (DPMS off ≥1–2 min then on), reproduced on **Plasma 6 / KWin 6.8.2** with a quickshell shell.
- [#910](https://github.com/quickshell-mirror/quickshell/issues/910) (open): SIGSEGV in `WlrLayershell::disownWindow` on compositor-initiated close (resume from sleep, screen changes), reproduced on **KWin / Plasma 6.7.5**.
- Related fixed-in-engine monitor churn: 0.3.0 "worked around Qt bug causing crashes when plugging and unplugging monitors", nulls in `Toplevel.screens` after unplug; 0.3.1 `WindowsetProjection.screens` unplug crash + `qs kill` semantics; 0.3.2 `WlSessionLockSurface.screen` null on monitor plug ([changelog](https://quickshell.org/changelog)).
- Sanctioned multi-monitor pattern: `Variants { model: Quickshell.screens }` per-screen PanelWindows ([Introduction](https://quickshell.org/docs/v0.3.2/guide/introduction)) — exactly the shape #910's KWin repro crashed on unplug.

**Scaling / DPR.** No KWin-specific fractional-scaling issue surfaced in the tracker this pass (`IconImage` blur [#128](https://github.com/quickshell-mirror/quickshell/issues/128) is compositor-agnostic). Noctalia explicitly advertises fractional-scale handling; Quickshell relies on Qt6 Wayland fractional-scale. **Untested on the fleet's KWin 6.8.2 + mixed-DPR rigs — harness test item.**

**Blur / compositing.** No compositor blur behind QS surfaces on KWin (ext-background-effect-v1 not evidenced — §4), and the fake-blur fallback (live `ScreencopyView` of the monitor behind the bar) needs capture protocols KWin may only partially provide and is Hyprland-pattern in practice. Plan for opaque/flat surfaces on Plasma, or theme-level transparency without blur.

**Crash/failure behavior of a QS shell in a Plasma session.** One process per config; a crash removes all its surfaces at once and **releases the exclusive zones** (windows snap into the vacated space). Mitigations: systemd user unit with `Restart=on-failure`; crash handler is cpptrace with `QS_CRASHREPORT_URL`/`QS_DISABLE_CRASH_HANDLER` env knobs (0.3.0); `qs kill` waits for exit (0.3.1); IPC from children of a crashed+relaunched instance fixed (0.3.1). The engine's release cadence itself (0.3.1 and 0.3.2 being wall-to-wall crash fixes for sleep/wake, DPMS, monitor unplug, PAM, session-lock paths) is the honest signal: always-on shells on laptop-style power events are the bleeding edge.

## 9) Implications For The Fleet (Foyer campaign)

1. **The framework verdict hasn't flipped: Quickshell on KWin remains companion chrome, not a Plasma panel replacement.** What changed with 0.3.x is that the *service* gap narrowed (polkit agent, idle, network, ext-workspace, notifications/tray all engine-provided), so a Quickshell side-surface on Plasma is more self-sufficient than the fleet previously assessed. The *surface* gaps that block panel-replacement are unchanged and mostly KWin-side: no ext-background-effect blur, no per-window capture, SNI watcher collision with plasmashell, and the open monitor-event crash class (#910/#1340) that lands exactly on DPMS-capable fleet hardware.
2. **Version discipline matters more than the fleet thought:** Fedora 45's official package is a 0.2.1 git snapshot — a shell written against 0.3 docs (WindowManager, Polkit, Idle*) will not run on it. On Bazzite, any 0.3-based work must pin the COPR 0.3.2 or a user-space build, which collides with the no-layering rule → decide explicitly (distrobox vs `~/.local` build vs a documented policy exception) before the campaign writes configs that assume 0.3.
3. **KWin's own protocol adoption is doing the converging:** layer-shell (5.20+), ext-workspace (6.7, shipping on the fleet's 6.8.2). Anything the fleet builds on `PanelWindow` + `WindowManager` is protocol-legitimate on Plasma 6.7+; anything reaching for Hyprland-flavored protocols (toplevel-export, hyprland focus grabs) is dead on arrival on KWin — keep those behind version/compositor guards (`this.WlrLayershell != null` null-check pattern from the docs).
4. **The ecosystem's KDE energy is real but thin:** caelestia-kde exists and is what surfaced both KWin crash reports; the big shells (DMS/dux, Noctalia, Wayle) explicitly do not target KWin, and Noctalia has *left* the Quickshell runtime entirely (native C++/GLES) — a warning that betting a long campaign on QS-shell portability is betting on a moving target with breaking changes promised before 1.0.
5. **QA posture stands:** nested kwin harness only; add DPMS on/off and monitor-unplug cycles to the harness suite, since those are the evidenced Plasma-session killers; test SNI tray behavior only with the Plasma tray explicitly disabled.

## 10) Unverified / Open Questions

- **KWin ext-image-copy-capture-v1 support** (which Plasma version, if any): determines whether `ScreencopyView` monitor capture works at all on Plasma. Web search was too polluted to pin; check `wayland-info` on the nested harness — one command settles it.
- **KWin ext-background-effect-v1**: no implementation evidence found; likewise `wlr-foreign-toplevel-management` (QS `Toplevel`) on KWin. Both need a local `wayland-info` pass.
- **QS `WindowManager` actually binding on KWin 6.7/6.8**: protocol prerequisites align, but no upstream report confirms the binding works in practice.
- **SNI watcher collision behavior on a live Plasma session** (who wins, what plasmashell does on QS takeover): inferred from the single-watcher design; not documented upstream.
- **Keyboard-interactivity quirks of KWin 6.8** with OnDemand/Exclusive layer surfaces: no tracker signal either way; untested by fleet.
- **Fractional scaling/DPR on KWin** for QS surfaces: no signal; untested.
- **Governance details** (CLA, contribution policy, funding): no docs found; not chased further.
- **AGS current state on KWin**; eww#393 current state (API rate-limited this pass — fleet-known only).
- **Debian/Ubuntu/openSUSE/Gentoo/Guix exact versions**: documented as packaged, versions not checked (low fleet relevance).

## Checked vs Not-Checked

**Checked (primary sources):** quickshell.org home/about/changelog; docs v0.3.2 guide (install-setup, faq, introduction), type pages (module listing, PanelWindow, WlrLayershell, BackgroundEffect, ScreencopyView, WindowManager, SystemTray); GitHub API for quickshell-mirror/quickshell (repo meta, languages, releases/tags, license) + outfoxxed redirect; issue tracker searches (kwin/kde/plasma/keyboard interactivity/blur/screencopy/StatusNotifierWatcher) with bodies+comments for #910, #1340; quickshell-examples forge repo; Fedora packages page + dist-git spec (rawhide/f45); COPR via api_3; nixpkgs package.nix on master/release-26.05/release-25.11; Arch packages JSON + AUR RPC; Homebrew formula+cask API (absence); READMEs of eww, noctalia-shell, DankMaterialShell, wayle (+ repo-search for Wayle); KDE MegaRelease 6 page; Neowin on Plasma 6.7 ext-workspace; Phoronix on ext-image-copy-capture merge into wayland-protocols.

**Not checked:** sibling-lane topics fenced out (end-4dots-kde, NextKde/KOS, quickshell-kde architecture, Omarchy plugin ecosystem); BUILD.md contents (linked, not fetched); Debian/Ubuntu/OBS/GURU/Guix versions; live COPR repo listing via HTML (Anubis-walled; API used instead); eww#393 and AGS states (rate limit); KWin source tree for protocol implementations; any runtime/harness testing (this is a desk dossier — the nested-kwin verification items in §10/§9 are the follow-ups).

