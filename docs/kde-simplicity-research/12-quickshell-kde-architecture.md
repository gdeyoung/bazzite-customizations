---
title: "quickshell-kde (SnTR370) — Technical Dossier: Compositor-Isolated Quickshell Shell for KDE Plasma 6"
date: 2026-11-12
researcher: Hermes subagent (lane 4: quickshell-kde deep-dive)
source_urls:
  - https://github.com/SnTR370/quickshell-kde
  - https://api.github.com/repos/SnTR370/quickshell-kde
  - https://api.github.com/repos/SnTR370/quickshell-kde/git/trees/main?recursive=1
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/README.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/docs/ARCHITECTURE.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/docs/KWIN_INTEGRATION.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/docs/MODULES.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/docs/CONFIGURATION.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/DEVELOPMENT.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/ATTRIBUTION.md
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/services/kwin/KWinService.qml
  - https://raw.githubusercontent.com/SnTR370/quickshell-kde/main/services/kwin/WindowService.qml
  - https://quickshell.org/docs/v0.3.0/
---

# quickshell-kde — Architecture Dossier

> Headline claim under test: *"a modern Quickshell desktop shell built for KDE Plasma 6 that isolates
> compositor-specific functionality to work cleanly with KWin."* This dossier verifies how that
> isolation actually works, because the pattern — not the shell — is the transferable asset for the
> fleet's dual-target (Hyprland + KDE) plugin work.

---

## 1) Repo Reality

All figures from the GitHub API on 2026-11-12 ([repo metadata](https://api.github.com/repos/SnTR370/quickshell-kde)):

| Dimension | Value |
|---|---|
| Owner | `SnTR370` — Davut Can Bostan; account created 2025-01-20, **1 public repo total**, 1 follower ([user API](https://api.github.com/users/SnTR370)) |
| Created | 2026-08-28 |
| Last push | 2026-11-07 (`pushed_at`) — active 5 days before this dossier |
| Stars / forks / watchers | **2 / 1 / 2** |
| License | MIT ([LICENSE](https://github.com/SnTR370/quickshell-kde/blob/main/LICENSE)) |
| Language / size | QML, 907 KB |
| Releases | **None** (no tags, no releases via [API](https://api.github.com/repos/SnTR370/quickshell-kde/releases)) |
| Issues | **0 open, 0 ever filed** ([issues API](https://api.github.com/repos/SnTR370/quickshell-kde/issues?state=all)) |
| PRs | 2, both closed, both the author's own feature merges (#1 `feat/kwin-foundation`, #2 `feat/shell-experience`, both 2026-08-28) |
| Contributors | 1 (SnTR370, 37 commits) ([contributors API](https://api.github.com/repos/SnTR370/quickshell-kde/contributors)) |
| CI / tests | **None on main** — no `.github/` in the [full tree](https://api.github.com/repos/SnTR370/quickshell-kde/git/trees/main?recursive=1); DEVELOPMENT.md lists "Comprehensive automated test suite and CI workflow" as a *future* Milestone 3 item |

**Activity shape.** All 37 commits on `main` carry the date **2026-08-28** — the entire shell was
built and merged in a single day ([commits API](https://api.github.com/repos/SnTR370/quickshell-kde/commits?per_page=40)).
Development did not stop: the repo has **25 branches** with heavy recent pushes —
`test/colosseum-isolation-wave2`, `fix/ui-stabilization-wave1`, `feat/arena-installer` (all pushed
2026-11-06/07), `test/core-reliability-gates` (2026-11-06), `fix/post-audit-remediation` (2026-10-31),
`feat/rush-orchestrator` (2026-10-30) ([events API](https://api.github.com/repos/SnTR370/quickshell-kde/events)).
Branch names (`rush-*`, `arena-*`, `colosseum-*`) strongly suggest agent-driven or gamified
development sprints running on a private loop, merged nowhere yet — `main` has not moved since
2026-08-28 while work continued on side branches for ~10 weeks.

**Verdict: live solo hobby project, not a community shell.** One author, zero external
participation, no releases, no issue tracker usage, no CI. But the engineering discipline on `main`
(real docs, attribution file, honest limitation notes) is well above typical dotfile dumps, and the
commit cadence shows sustained investment. The README's `git checkout feat/shell-experience`
instruction is stale — that branch was merged into `main` via PR #2 on 2026-08-28
([README](https://github.com/SnTR370/quickshell-kde/blob/main/README.md)).

---

## 2) Compositor-Isolation Architecture — the headline claim, verified

### 2.1 What it is NOT

It is **not** a multi-compositor abstraction with runtime backend selection. There is:

- **no** `compositor/` namespace or interface with per-compositor implementations,
- **no** conditional QML imports choosing a backend,
- **no** config-driven compositor selection,
- **no** Hyprland/wlroots code path at all — ATTRIBUTION.md states the opposite direction: all
  Hyprland (`hyprctl`), Niri (`niri msg`) and MangoWC (`mmsg`) calls inherited from upstream
  `ekremx25/quickshell` were **removed** and replaced by one KWin adapter
  ([ATTRIBUTION.md](https://github.com/SnTR370/quickshell-kde/blob/main/ATTRIBUTION.md)).

### 2.2 What it IS: a single-backend adapter singleton, enforced by convention

The isolation is a **service-adapter pattern**: every compositor interaction in the shell is
confined to two QML singletons in `services/kwin/`, exported through `qmldir`:

```
services/qmldir:
  singleton KWinService 1.0 kwin/KWinService.qml
  singleton WindowService 1.0 kwin/WindowService.qml
```
([services/qmldir](https://github.com/SnTR370/quickshell-kde/blob/main/services/qmldir))

The rule is written down and enforced by review, not by the language:

> "UI components in `modules/` MUST NOT directly invoke compositor-specific shell commands
> (`hyprctl`, `niri msg`, `qdbus`, etc.). All compositor interactions must be mediated by the
> singleton `KWinService` located in `services/kwin/KWinService.qml`."
> — [DEVELOPMENT.md §1](https://github.com/SnTR370/quickshell-kde/blob/main/DEVELOPMENT.md)

Stated payoffs: (1) maintainability — D-Bus/protocol changes touch one layer; (2) testability —
UI modules inspectable without a live compositor; (3) safety — no ad-hoc shell injection from UI
files. The layering diagram in [docs/ARCHITECTURE.md](https://github.com/SnTR370/quickshell-kde/blob/main/docs/ARCHITECTURE.md)
is `UI modules → singleton services → (KWin D-Bus / protocols | XDG config JSON)`.

### 2.3 Runtime capability detection (real code)

`services/kwin/KWinService.qml` detects the session from environment variables and **guards every
function** on the result ([source](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/KWinService.qml)):

```qml
// Compositor detection
readonly property string xdgDesktop: Quickshell.env("XDG_CURRENT_DESKTOP") || ""
readonly property string kdeSession: Quickshell.env("KDE_FULL_SESSION") || ""
readonly property bool isKWin: xdgDesktop.toLowerCase().indexOf("kde") !== -1 || kdeSession === "true"
readonly property bool isWayland: (Quickshell.env("WAYLAND_DISPLAY") !== "") ||
                                  (Quickshell.env("XDG_SESSION_TYPE") === "wayland")
...
function setCurrentDesktop(idOrIndex) {
    if (!root.isKWin) return;      // <-- every adapter method no-ops off-KDE
    ...
}
```

On a non-KDE session the shell still renders (bar, dock, launcher, themes all work — they bind to
Quickshell native services), but desktop/window/brightness KWin features silently disable. That is
the whole "isolation": **one seam, clearly named, everything else compositor-blind.**

### 2.4 The transport choice: `qdbus6` subprocess + regex parsing, not native D-Bus

This is the most opinionated (and most fleet-relevant) decision. KWinService does not use native
QML D-Bus bindings; it shells out to the `qdbus6` CLI through Quickshell's `Process`/`SplitParser`
and **regex-parses the `--literal` D-Bus output**:

```qml
Process {
    id: desktopsListProc
    command: ["qdbus6", "--literal", "org.kde.KWin", "/VirtualDesktopManager",
              "org.kde.KWin.VirtualDesktopManager.desktops"]
    property string buf: ""
    stdout: SplitParser { onRead: data => { desktopsListProc.buf += data; } }
    onExited: exitCode => { if (exitCode === 0 && desktopsListProc.buf.trim().length > 0)
                                root.parseDesktopsLiteral(desktopsListProc.buf); }
}
...
const regex = /\[Argument:\s*\([ui]ss\)\s*(\d+),\s*"([^"]+)",\s*"([^"]+)"\]/g;  // parse a(uss) tuples
```
([KWinService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/KWinService.qml))

Write-paths use fire-and-forget `Quickshell.execDetached(["qdbus6", ...])`. Consequences:

- **Plus:** zero compiled dependencies, zero C++ build, works on any distro with `qt6-tools` —
  exactly the fleet's user-space-only constraint.
- **Minus:** string-parsing `qdbus --literal` output is fragile across `qdbus6` versions and locales,
  and there is no signal subscription — so state stays fresh via **polling timers** (3000 ms for
  virtual desktops, 2500 ms for windows, both documented in-code as fallbacks for changes made
  outside Quickshell, e.g. KWin global shortcuts) ([KWinService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/KWinService.qml)).

### 2.5 The window-management hack: KRunner's D-Bus interface

`services/kwin/WindowService.qml` lists and activates windows **through KWin's KRunner plugin**
rather than a toplevel-management protocol:

```qml
command: ["qdbus6", "--literal", "org.kde.KWin", "/WindowsRunner", "org.kde.krunner1.Match", ""]
...
function activateWindow(windowId) {
    Quickshell.execDetached(["qdbus6", "org.kde.KWin", "/WindowsRunner",
                             "org.kde.krunner1.Run", windowId, ""]);
}
```
([WindowService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/WindowService.qml))

DEVELOPMENT.md is explicit about why: under standard KWin Wayland sessions
`zwlr_foreign_toplevel_manager_v1` is restricted, so the shell piggybacks on the sanctioned
`org.kde.krunner1` Match/Run interface (the same one KDE's own krunner uses) and regex-parses the
`(sssida{sv})` tuples. Clever, sanctioned-surface, and again — pure user-space.

### 2.6 Full KWin D-Bus surface (documented + verified in code)

From [docs/KWIN_INTEGRATION.md](https://github.com/SnTR370/quickshell-kde/blob/main/docs/KWIN_INTEGRATION.md)
and the two adapter files:

| Interface | Path | Used for |
|---|---|---|
| `org.kde.KWin.VirtualDesktopManager` | `/VirtualDesktopManager` | list/create/remove desktops, `current`, `count` |
| `org.kde.KWin` | `/KWin` | `activeOutputName()`, `setCurrentDesktop`, `nextDesktop`/`previousDesktop`, `showDesktop` |
| `org.kde.krunner1` (KWin WindowsRunner) | `/WindowsRunner` | enumerate + activate windows (taskbar/dock duty) |
| `org.kde.Shutdown` | `/Shutdown` | logout / reboot / shutdown |
| `org.kde.ScreenBrightness` | (per-display paths) | brightness get/set + `BrightnessChanged` signals (BrightnessService) |

Notably **absent**: KWin scripting API (`/Scripting`, QJS), `kglobalaccel`, KConfigXT, Plasma's
`org.kde.plasmashell` interfaces. The shell is a pure layer-shell + D-Bus citizen.

### 2.7 Assessment of the claim

"Isolates compositor-specific functionality" is **accurate but modest**: it's one KWin-only adapter
module rather than a swappable backend system. For the fleet's purpose this is still the valuable
shape — the seam exists, it's named, documented, and the UI layer demonstrably contains zero
compositor strings. A Hyprland twin adapter (`HyprlandService` implementing the same QML property/
signal surface over `hyprctl -j`) would slot in beside it; nothing in `modules/` would need to know.
What's missing for true dual-target is an interface contract (same properties/signals guaranteed by
both adapters) — today that contract is implicit.

---

## 3) Module Inventory

From the [real file tree](https://api.github.com/repos/SnTR370/quickshell-kde/git/trees/main?recursive=1) (108 entries) and [docs/MODULES.md](https://github.com/SnTR370/quickshell-kde/blob/main/docs/MODULES.md). Completeness judged from code size + commit messages, not README claims.

| Module | Files | State |
|---|---|---|
| **Bar** (`modules/bar/`) | Bar.qml (6.3 KB) + 8 slot modules | Complete: multi-edge (top/bottom/left/right), 3 slot areas, per-monitor filtering, blur. Slot layout is config-driven `Loader` over `Repeater` ([Bar.qml](https://github.com/SnTR370/quickshell-kde/blob/main/modules/bar/Bar.qml)) |
| **Dock** (`modules/dock/`) | Dock.qml (9.6 KB), DockItem, DockMenu | Most-developed module: autohide w/ edge triggers + delays, running indicators, multi-window cycling, context menus w/ window lists, pin/unpin |
| **Launcher** (`modules/launcher/`) | LauncherWindow.qml (11.6 KB) | Complete: fullscreen/centered overlay, in-memory search, category filter, session buttons |
| **Notifications** (`modules/notifications/`) | ToastHost, NotificationCard | Complete but **opt-in** (server disabled by default; toasts only render when enabled) |
| **OSD** (`modules/osd/`) | OSDHost, VolumeOSD, BrightnessOSD | Complete: reacts to PipeWire volume + KDE ScreenBrightness changes |
| **Media** (`modules/media/`) | MediaPopup.qml | Complete popup player (MPRIS) |
| **Settings** (`modules/settings/`) | SettingsWindow.qml (**34.5 KB** — largest file in repo) | Complete GUI for themes, bar, dock, outputs, session |
| **NOT present** | — | No wallpaper, no lock screen, no logout greeter, no clipboard manager, no widgets/clocks-on-desktop, no color-picker, no screencast. Deliberate: README positions it as chrome *around* Plasma's desktop, not a replacement for plasmashell's desktop containment |

Services inventory mirrors this: applications (XDG indexer), audio (PipeWire), battery (UPower),
brightness (KDE D-Bus + sysfs), config (JSON store), core (JsonStore + Log.js), kwin (the two
adapters), mpris, network (Quickshell.Networking), notifications, theme (design tokens + 4 presets).

Two Python helpers exist precisely where QML is weak, exploiting Quickshell's ability to spawn
processes (which Plasma QML cannot): [`scan_apps.py`](https://github.com/SnTR370/quickshell-kde/blob/main/services/applications/scan_apps.py)
(fast XDG + Flatpak .desktop indexer emitting JSON; run by ApplicationService) and
[`discover_displays.py`](https://github.com/SnTR370/quickshell-kde/blob/main/services/brightness/discover_displays.py)
(parallel `qdbus6` probe of `org.kde.ScreenBrightness` per-display objects).

---

## 4) KWin Integration Surface

**Mechanism: layer-shell for windows + qdbus6 CLI for control. Nothing else.**

- **Windowing:** every surface is a Quickshell `PanelWindow` (i.e. `zwlr_layer_shell_v1`), anchored
  per screen via `Variants { model: Quickshell.screens }`, `WlrLayershell.layer: WlrLayer.Top`,
  `exclusiveZone` set so KWin reserves struts like a real panel ([Bar.qml](https://github.com/SnTR370/quickshell-kde/blob/main/modules/bar/Bar.qml)).
- **Blur:** `BackgroundEffect.blurRegion` — the `ext_background_effect_manager_v1` protocol KWin
  exposes for third-party layer-shell clients (same route Hyprland shells use; works on KWin ≥ 6.1
  era Plasma) ([Bar.qml](https://github.com/SnTR370/quickshell-kde/blob/main/modules/bar/Bar.qml)).
- **Control plane:** all KWin state flows through the D-Bus table in §2.6, invoked via `qdbus6`.
- **Brightness signal subscription:** a long-running `dbus-monitor` subprocess whose stdout is
  regex-parsed for `BrightnessChanged` / `DisplayAdded` / `DisplayRemoved`
  ([BrightnessService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/brightness/BrightnessService.qml)).
- **Explicitly unused:** KWin scripting API (`org.kde.KWin /Scripting`, QJS), `kglobalaccel`,
  KConfigXT, plasma-workspace QML imports, `org.kde.plasmashell` D-Bus, `zwlr_foreign_toplevel_manager_v1`
  (restricted under KWin — worked around via KRunner, §2.5).

**Compositor-agnostic in practice?** Partially. The UI renders on any wlroots-compatible compositor
that implements layer-shell (Hyprland, Niri, Sway included) because layer-shell is the only hard
Wayland dependency of the *views*. But the moment you touch desktops, windows, brightness, or OSD
you hit `isKWin` guards and `qdbus6` calls that no-op or fail elsewhere. Running under Hyprland you
would get: bar with clock/network/battery/audio/media/tray, dock with pinned apps (launch works),
launcher — but no workspaces, no running-app indicators, no brightness, no window activation. The
README is honest about the direction of the port ("No Hyprland, Niri, or Sway dependencies"), and
`qdbus6` is itself a hard runtime dependency listed as Required.

---

## 5) Panel Replacement & Tray/SNI Ownership

**Does it kill the Plasma panel? No.** There is no code touching plasmashell: no `kwriteconfig5/6`
to hide panels, no `plasmashell -d`/replacement, no `org.kde.plasmashell` D-Bus calls anywhere in
the tree. The intended deployment is bar + dock **on top of** a Plasma session, with Plasma's own
panel presumably removed manually by the user if desired. (Fleet-relevant: that is exactly the
companion-chrome doctrine — it never fights plasmashell for the desktop containment role.)

**Notification daemon: exists, but default-off — the clean collision answer.** `NotificationService`
wraps `Quickshell.Services.Notifications.NotificationServer` in a **conditional `Loader`**:

```qml
Loader {
    active: ConfigService.notificationsEnabled   // default: false
    sourceComponent: Component { NotificationServer { keepOnReload: true; ... } }
}
```
([NotificationService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/notifications/NotificationService.qml))

`notificationsEnabled: false` ships in [`config/bar_config.json`](https://github.com/SnTR370/quickshell-kde/blob/main/config/bar_config.json),
and the commit that introduced it is explicit: *"fix(notifications): make NotificationServer
conditionally loaded to preserve Plasma D-Bus ownership"* ([commit](https://github.com/SnTR370/quickshell-kde/commits/main/) —
the `org.freedesktop.Notifications` bus name is single-owner, so two daemons means one silently
loses). Enabling it is framed as "standalone KWin session" mode. This is the correct pattern and the
single best collision-avoidance artifact in the repo.

**SNI/tray: enabled by default — the one real collision point.** `TrayModule` binds directly to
`Quickshell.Services.SystemTray` (`SystemTray.items`) with activate / secondaryActivate /
`display(menu)` / scroll, and ships in the default `right` slot list of `bar_config.json`
([TrayModule.qml](https://github.com/SnTR370/quickshell-kde/blob/main/modules/bar/TrayModule.qml)).
Under Plasma, plasmashell owns the `StatusNotifierWatcher`; Quickshell's SystemTray service
additionally registers as a host, so items are delivered to **both** trays — the practical symptom
is duplicated tray icons, not a watcher war ([Quickshell SystemTray docs](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.SystemTray/)).
For the fleet's rule ("SNI duty stays with Plasma"), the fix is one line: remove `"tray"` from the
bar's right-slot config. Unlike notifications, there is no config flag disabling the tray *service*
itself — the module simply renders empty when it sees no items.

---

## 6) Runtime & Launch

- **Launch:** `quickshell -p ./shell.qml` from the repo root, run as the user; `Ctrl+C` or
  `quickshell kill` to stop; `quickshell list` to inspect ([README](https://github.com/SnTR370/quickshell-kde/blob/main/README.md)).
  **No systemd user unit, no autostart .desktop, no install script** ships on `main` — daily-driver
  onboarding is explicitly out of scope ("will never touch `~/.config/quickshell/`"). The
  `feat/arena-installer` branch (pushed 2026-11-07) appears to be where install tooling is being
  built.
- **Entry point:** [`shell.qml`](https://github.com/SnTR370/quickshell-kde/blob/main/shell.qml) — a
  bare `ShellRoot` instantiating Bar, Dock, LauncherWindow, ToastHost, OSDHost, MediaPopup,
  SettingsWindow; `//@ pragma UseQApplication` at top (widget-style app init for DPI/clipboard).
- **Versions:** Quickshell **>= 0.3.0** (README badge + requirement table; matches host-verified
  COPR 0.3.2 availability). Qt 6 implied (`qdbus6`, `qt6-tools` for `qmllint`/`qmlformat`).
- **Runtime deps:** `plasma-workspace`/`kwin` (session), `pipewire`/`pipewire-pulse`,
  `python >= 3.9` (app indexer), **`qdbus6`/`qt6-tools` (Required — the control plane)**,
  recommended `upower`, `networkmanager`.
- **Distro assumptions:** generic Linux + KDE Plasma 6; nothing Arch/Fedora-specific in code. Flatpak
  app dirs are scanned in both system and user export paths. All writes stay in
  `$XDG_CONFIG_HOME/quickshell-kde/` and `$XDG_CACHE_HOME/quickshell-kde/`; zero root, no `/etc`
  touches ([DEVELOPMENT.md](https://github.com/SnTR370/quickshell-kde/blob/main/DEVELOPMENT.md) "Zero Root / Safe Storage").
- **Config model:** three JSON files (`bar_config.json`, `dock_config.json`, `theme_config.json`)
  loaded by `ConfigService` with `JsonStore.fallbackPath` defaults — user config layered over
  repo defaults, no restart required for the settings GUI to apply changes
  ([docs/CONFIGURATION.md](https://github.com/SnTR370/quickshell-kde/blob/main/docs/CONFIGURATION.md)).

---

## 7) Quality Signals

**On `main` (what a cloner gets today):**
- **Docs: unusually strong for 2 stars.** Five markdown docs beyond the README
  ([ARCHITECTURE](https://github.com/SnTR370/quickshell-kde/blob/main/docs/ARCHITECTURE.md),
  [KWIN_INTEGRATION](https://github.com/SnTR370/quickshell-kde/blob/main/docs/KWIN_INTEGRATION.md),
  [MODULES](https://github.com/SnTR370/quickshell-kde/blob/main/docs/MODULES.md),
  [CONFIGURATION](https://github.com/SnTR370/quickshell-kde/blob/main/docs/CONFIGURATION.md),
  [DEVELOPMENT](https://github.com/SnTR370/quickshell-kde/blob/main/DEVELOPMENT.md)) plus
  CONTRIBUTING.md and an ATTRIBUTION.md. Commit history shows repeated **documentation-truthfulness
  audits** ("docs: audit documentation truthfulness, remove personal paths", "docs: document accurate
  window management ... and limitations") — the docs were corrected against reality, not aspirational.
- **Tests/CI on main: none.** Milestone 3 roadmap lists "comprehensive automated test suite and CI
  workflow" as future work. `qmllint`/`qmlformat` are the only static gates.
- **QML quality: clean and idiomatic.** Consistent design-token usage (`Theme.*`), no hardcoded
  colors in modules, proper `qmldir` singleton registries at every level, `Repeater`+`Loader` slot
  composition instead of copy-paste per module. **No Hyprland residue on main**: the inherited
  `hyprctl`/`niri msg`/`mmsg` calls were stripped per
  [ATTRIBUTION.md](https://github.com/SnTR370/quickshell-kde/blob/main/ATTRIBUTION.md) — verified
  against the full tree (zero `hyprctl` references outside ATTRIBUTION/docs).
- **Heritage:** adapted from `ekremx25/quickshell` (MIT, 40★, Hyprland/Niri/MangoWC shell) — visual
  patterns kept, unsafe root scripts (`disk_fstab_helper.sh`, `eq_filter_chain.sh`) explicitly
  discarded, ad-hoc polling replaced with native Quickshell services
  ([ATTRIBUTION.md](https://github.com/SnTR370/quickshell-kde/blob/main/ATTRIBUTION.md)).

**On the sprint branches (the actual current state, ~110 commits ahead of main):**
- **A real test suite is landing**: 20+ pytest files (`tests/test_dock_*.py`, `test_bridge_*.py`,
  `test_milestone_3a.py`, ...), QML scene tests (`tst_controlcenter.qml`, `tst_dock_autohide.qml`),
  and [`.rig/e2e.sh`](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/.rig/e2e.sh) —
  an end-to-end harness that spins up a **throwaway D-Bus session + `kwin_wayland --virtual`**,
  drives a scripted test window through add/move/resize/minimize/fullscreen/close, verifies the
  KWin event bridge loads/unloads its resident script, tests orphan-script cleanup after SIGKILL,
  and asserts spoofed D-Bus records from non-KWin senders are rejected. That is a serious
  compositor-level test rig, never touching the live Plasma session.
- **The project is openly AI-agent-built.** [`CLAUDE.md`](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/CLAUDE.md)
  is an agent working-rules file: the agent runs in Claude Code routed via CCR to "EVREN GLM-5.3",
  with a one-feature-per-session protocol, quality gates (tests + qmllint + isolated Wayland
  runtime), no-auto-merge-to-main, and no-fake-results rules. `tools/rush/rush_supervisor.py` +
  committed run logs (`tools/rush/runs/*.json`) show an orchestrated feature-rush loop; branch names
  (`rush-dock-004`, `colosseum-isolation`, `arena-installer`) and dev logs
  (`RUSH_PROTOCOL.md`, `P0_MARATHON_LOG.md`) match. This explains the one-day 37-commit genesis:
  it is an agent-driven engineering project with human-supervised gates, not a typical hobby spike.
- **Architectural direction (Milestone 3A, [docs/UX_SPEC_V1.md](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/docs/UX_SPEC_V1.md)):
  a composable surface model** — every surface described by one config table
  (`enabled/floating/edge/edgeOffset/reserveSpace/thickness/opacity/blur/monitors`), floating by
  default with `exclusiveZone: 0` (maximized windows fill the screen), decoupled module ownership
  ("no module permanently owned by a surface"), a central
  [`ModuleRegistry.qml`](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/services/core/ModuleRegistry.qml)
  that validates and sanitizes slot lists, plus new Control Center, dock stacks/magnification/
  keyboard-nav, intellihide, monitor profiles, layout presets.
- **Tension for the fleet:** Milestone 3A introduces `services/kwin/bridge/` — a **compiled C++ Qt6
  QML plugin** (`kwinbridge.cpp`, CMakeLists) paired with a resident KWin script
  (`kwin-event-bridge.js`) pushing live window events over D-Bus, for event-driven intellihide.
  The [bridge README](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/services/kwin/bridge/README.md)
  is candid about ABI constraints (same Qt 6 minor line as the running Quickshell, `$ORIGIN`
  runpath, binaries never committed) and — crucially — the design keeps an **automatic fallback**:
  if the `.so` is missing/unloadable, `WindowService` logs "KWin event bridge plugin unavailable;
  keeping snapshot sync" and reverts to snapshot polling. Nothing breaks; you only lose
  responsiveness. That degrade-gracefully ladder (compiled bridge → KWin-script snapshots →
  qdbus6 polling) is itself a transferable pattern.

---

## 8) Community Traction

**Effectively zero — this is a discovery-grade project, not a community one.**

- Search (web backend, 2026-11-12) for "SnTR370 quickshell-kde" surfaces only GitHub itself (the
  [repo](https://github.com/SnTR370/quickshell-kde), the
  [modules tree](https://github.com/SnTR370/quickshell-kde/tree/main/modules), and the
  [author profile](https://github.com/SnTR370)) — **no Reddit, no Hacker News, no discuss.kde.org,
  no blog, no YouTube coverage found**. A second search for quickshell-on-Plasma community threads
  returns only generic Plasma ricing posts (e.g. [r/unixporn Plasma 6](https://www.reddit.com/r/unixporn/comments/1cbkc6m/plasma_kde_scratchy_plasma_6/)),
  none referencing this shell.
- GitHub-side signals agree: 2 stars, 1 fork (anonymous, 2026-09-08), 0 issues ever, 0 external
  PRs, 0 watchers beyond stars ([repo API](https://api.github.com/repos/SnTR370/quickshell-kde)).
- README screenshots section says *"Visual previews and screenshots pending"* — there is not even a
  screenshot in the repo ([README](https://github.com/SnTR370/quickshell-kde/blob/main/README.md)).
- The author's GitHub presence is otherwise empty (1 public repo, no bio). The Turkish README
  translation (`README.tr.md`, sprint branches) suggests personal-use-first distribution.

Sentiment: N/A — no public sentiment exists. The interesting audience signal is indirect: the
sibling shells (§9) prove demand for Quickshell-on-Plasma, which is the wave this repo is surfing
solo.

---

## 9) Three-Shell Comparison (glance-level, per scope fence)

| | **SnTR370/quickshell-kde** | **ladybug-me/end-4dots-kde** | **NextKde/NextKde (KOS)** |
|---|---|---|---|
| What it is | Ground-up modular shell, KWin adapter isolation | Community KDE port of end-4's `dots-hyprland` (illogical-impulse aesthetic) | "A Quickshell desktop for KDE Plasma" — full KOS Desktop Shell + companion app family |
| Stars / forked | 2★ / 1 fork (2026-11-12) | 135★ / 4 forks | 863★ ([repo](https://api.github.com/repos/NextKde/NextKde)) |
| License | MIT | GPL-3.0 | GPL-3.0 |
| Created / pushed | 2026-08-28 / 2026-11-07 | 2026-06-14 / 2026-10-23 | 2025-11-07 / 2026-11-13 (today) |
| Quickshell-based | Yes (>= 0.3.0) | Yes ("Quickshell widgets" badge) | Yes (`Quickshell 0.3.x` badge) |
| Compositor isolation | **The core design**: `KWinService`/`WindowService` adapter singletons, env-detection, no compositor strings in UI layer | Pragmatic shims: "Custom KDE bridge via KWin script" + a **rewritten hyprctl** that translates Hyprland calls into KWin ops for ported widgets ([README](https://github.com/ladybug-me/end-4dots-kde)) | Integrated product; works with KWin/NM/PipeWire/BlueZ/systemd ([README](https://github.com/NextKde/NextKde)) |
| Scope | Bar, dock, launcher, OSD, media, (opt-in) notifications, settings | Full desktop aesthetic kit (MD3 theming, Darkly/Kvantum, 10-desktop presets) | Bar+dock+launcher+search+notifications+settings, desktop files, window previews, control center, Calendar/Weather/Calc/Music apps |
| Uniquely does | Documents + enforces the adapter seam; conditional notification server; graceful compiled-bridge→snapshot→polling ladder; e2e rig with virtual KWin | Preserves the end-4 UX people actually want, on Plasma | Polish + breadth + multilingual docs + app ecosystem; the "consumer product" of the three |
| Maturity vs opinionation | **Most architecturally explicit, least adopted** | Most opinionated aesthetic | Most mature product & community |

Note: the task brief's `NextKde/KOS` resolves to repo `NextKde/NextKde` (the KOS shell lives in the
org's main repo; `NextKde/KOS` itself 404s). end-4dots-kde and NextKde details are glance-level per
the scope fence — sibling lanes own their depth.

---

## 10) What The Fleet Can Steal (dual-target Omarchy/KDE plugin lessons)

Ranked by transfer value for porting Omarchy/Quickshell plugins to Plasma 6 on Bazzite:

1. **The adapter-singleton seam (steal this verbatim as *shape*).** One QML singleton per
   compositor — `KWinService` today, a `HyprlandService` twin implementing the *same* property/
   signal surface (`desktops`, `currentDesktopIndex`, `runningWindows`, `desktopChanged`,
   `setCurrentDesktop()`, ...) over `hyprctl -j` — with UI modules barred from compositor strings
   by a written rule ([DEVELOPMENT.md](https://github.com/SnTR370/quickshell-kde/blob/main/DEVELOPMENT.md)).
   The missing piece here is an explicit interface contract; write one (a doc listing the guaranteed
   properties/signals) and the twin adapters become genuinely swappable. For fleet plugins this is
   cheaper than Quickshell's own multi-backend internals because QML singletons need no C++.
2. **Env-var capability detection + total no-op degradation.**
   `XDG_CURRENT_DESKTOP`/`KDE_FULL_SESSION`/`WAYLAND_DISPLAY` checks and `if (!isKWin) return;`
   guards mean the *same QML file tree* runs on both fleets: full function on the matching
   compositor, harmless static chrome elsewhere ([KWinService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/KWinService.qml)).
   A dual-target Omarchy plugin should detect Hyprland the same way (`HYPRLAND_INSTANCE_SIGNATURE`)
   and degrade identically.
3. **The KRunner window-API trick for KDE taskbar duty.** Listing/activating windows via
   `org.kde.KWin /WindowsRunner` + `org.kde.krunner1.Match/Run` is a *sanctioned, always-present*
   surface that dodges KWin's restriction of `zwlr_foreign_toplevel_manager_v1`
   ([WindowService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/kwin/WindowService.qml)).
   Caveat learned here: it's text-parsed and poll-based (2.5 s) — fine for indicators, wrong for
   intellihide. For event-grade needs see #5.
4. **Conditional-Loader ownership yielding.** Any singleton-owner bus name
   (`org.freedesktop.Notifications`, potentially `StatusNotifierWatcher`) gets a
   `Loader { active: configFlag }` wrapper, default-off next to Plasma
   ([NotificationService.qml](https://github.com/SnTR370/quickshell-kde/blob/main/services/notifications/NotificationService.qml)).
   This is the exact mechanism to satisfy the fleet rule "notification/tray duty stays with Plasma":
   ship the capability, default it to Plasma, flip it on only for standalone sessions. (SNI needs
   the sharper version: keep `"tray"` out of the default slot list to avoid duplicate icons.)
5. **The three-rung event ladder: compiled QML plugin → resident KWin script snapshots → qdbus6
   polling, with automatic runtime downgrade.** The bridge README's design — plugin marked
   `optional plugin` in qmldir, `Loader.Error` → log + keep snapshot sync — is the honest way to
   want performance without hard-requiring compiled deps
   ([bridge README](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/services/kwin/bridge/README.md)).
   On Bazzite (no rpm-ostree layering) the fleet would *ship rung 2+3 only* — the resident KWin
   script (`services/kwin/scripts/kwin-event-bridge.js`, pure JS via KWin scripting, no compile)
   pushing events over D-Bus is the sweet spot: event-driven, user-space, no ABI risk. Rung 1 can
   remain an opt-in for writable-root machines like sammypro5.
6. **`ext_background_effect_manager_v1` blur from layer-shell.** `BackgroundEffect.blurRegion` on
   `PanelWindow` gets Hyprland-style blur *inside Plasma* ([Bar.qml](https://github.com/SnTR370/quickshell-kde/blob/main/modules/bar/Bar.qml))
   — portable gloss for fleet chrome without touching Plasma themes.
7. **Python sidecars for what QML can't do.** `scan_apps.py` / `discover_displays.py` spawned via
   `Quickshell.Io Process`, JSON over stdout — the exact pattern for fleet plugins needing
   enumeration/IO that Plasma QML can't spawn at all
   ([scan_apps.py](https://github.com/SnTR370/quickshell-kde/blob/main/services/applications/scan_apps.py)).
   Keep them stdlib-only (both are) and they're safe on immutable hosts.
8. **The `.rig` e2e pattern.** Throwaway `XDG_RUNTIME_DIR` + private D-Bus + `kwin_wayland
   --virtual` for automated compositor-level testing without touching the live session
   ([.rig/e2e.sh](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/.rig/e2e.sh)).
   Directly reusable as the CI rig for fleet dual-target plugins — and it doubles as the Hyprland
   test story (swap in `Hyprland` headless).
9. **Config-slot composition.** `Repeater`+`Loader` over JSON slot lists with a `ModuleRegistry`
   validating ids ([ModuleRegistry.qml](https://github.com/SnTR370/quickshell-kde/blob/feat/arena-installer/services/core/ModuleRegistry.qml))
   is how to make one plugin user-composable across both desktops without forking QML.

Also steal the *meta*-lesson: this repo's CLAUDE.md gate discipline (one feature per session, tests
before push, no auto-merge, honest docs audits) is a working template for agent-driven fleet
engineering — but note its main branch is 110 commits behind its sprint branches, which is what
happens when merge gates have no human cadence.

---

## 11) Unverified / Open Questions

- **Runtime behavior claims rest on code reading, not execution.** I did not run the shell on
  Bazzite/KWin 6.8. The 2.5–3 s polling latency, qdbus6 regex robustness across `qdbus6` versions,
  and the duplicate-tray-icon prediction are inferred from code, not observed.
- **Sprint-branch state is a moving target.** All Milestone 3A findings (ModuleRegistry, bridge,
  Control Center, tests) come from `feat/arena-installer` and siblings on 2026-11-12; none of it is
  merged to `main`, has no release, and could be rebased or abandoned. The `tests/` suite's pass
  state is unknown (no CI runs it publicly).
- **Upstream relationship depth.** ATTRIBUTION.md claims concept/UI adaptation from
  `ekremx25/quickshell`; I did not diff the two trees to quantify actual code reuse.
- **Quickshell SystemTray multi-host semantics** under a live plasmashell (duplicate icons vs
  watcher conflict) is cited from Quickshell's docs model, not from a live Plasma 6.8 experiment.
- **`ext_background_effect_manager_v1` on the fleet's exact KWin 6.8.2**: the protocol is used by
  the shell and claimed in docs; version-gating on KWin's side was not verified here (host-side
  lane owns that).
- **Community coverage**: absence of evidence from two search passes + GitHub zeros is strong but
  not proof (e.g. Discord/Telegram chatter is unsearchable from here).

---

## Checked vs Not-Checked

**Checked (primary sources, 2026-11-12):**
- GitHub API: repo metadata, contributors, commits (37 on main), branches (25), events, issues/PRs
  (2 closed PRs, 0 issues), releases (none), forks/stars, user profile.
- Full `main` file tree (108 entries) via `/git/trees?recursive=1`; read on `main`: README.md,
  shell.qml, all 5 docs, ATTRIBUTION.md, KWinService.qml, WindowService.qml, services/qmldir,
  Bar.qml, TrayModule.qml, NotificationService.qml, BrightnessService.qml (partial), scan_apps.py,
  discover_displays.py, all 3 config JSONs.
- Sprint-branch verification: `compare` API (ahead/behind) for 3 branches; full tree of
  `feat/arena-installer` (187 entries); read CLAUDE.md, ModuleRegistry.qml, kwin bridge README,
  UX_SPEC_V1.md (partial), .rig/e2e.sh (partial).
- Sibling glance: API metadata + README head for ladybug-me/end-4dots-kde and NextKde/NextKde;
  metadata for ekremx25/quickshell.
- Community: two web searches (project name; quickshell-KDE reddit) — no third-party coverage found.

**Not checked:**
- Live execution on any compositor (no `quickshell -p` run; no Bazzite/KWin 6.8 hands-on).
- Actual pass/fail state of the branch test suite; no CI exists to consult.
- Line-by-line diff vs ekremx25/quickshell (reuse quantification).
- Discord/Telegram/Matrix chatter; non-English social coverage beyond what search surfaced.
- Quickshell upstream internals (sibling lane); end-4dots-kde and NextKde depth beyond README/API
  glance (sibling lanes).
- The remaining unread files on `main` (SettingsWindow.qml 34.5 KB internals, LauncherWindow.qml,
  Dock.qml full body, ConfigService.qml, Theme.qml) — read selectively, not exhaustively.
