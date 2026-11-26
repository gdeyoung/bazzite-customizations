---
title: "Omarchy Plugin Ecosystem and its KDE Plasma 6 Portability Surface"
date: 2026-11-12
source_urls:
  - https://omarchy.org/manual/shell-plugins/
  - https://plugins.omarchy.org/
  - https://omarchy.org/manual/
  - https://omarchy.org/manual/omarchy-cli/
  - https://github.com/omacom/omarchy
  - https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md
  - https://raw.githubusercontent.com/omacom/omarchy/quattro/shell/plugins/README.md
  - https://plugins.omarchy.org/develop.html
  - https://plugins.omarchy.org/publish.html
  - https://github.com/omacom/omarchy-plugin-marketplace
  - https://raw.githubusercontent.com/omacom/omarchy-plugin-marketplace/main/registry.json
  - https://github.com/majesticio/plasmarchy
  - https://github.com/Wizmo-inc/plasmarchy
  - https://api.github.com/repos/omacom/omarchy
  - https://api.github.com/users/gdeyoung/repos
  - https://www.howtogeek.com/i-tried-the-viral-linux-distro-that-raised-millions/
status: complete
---

# Omarchy Plugin Ecosystem — Structure, API, and Plasma 6 Porting Economics

Researched 2026-11-12 for the fleet's KDE-simplicity campaign. Scope: the Omarchy plugin
system (post-"Quattro" Quickshell rewrite), the plugins.omarchy.org registry, and what of
it is worth porting to KDE Plasma 6. Sibling lanes (end-4dots-kde, NextKde/KOS,
quickshell-kde architecture, Quickshell framework capabilities) are referenced only in
passing.

## 1) Plugin System Mechanics

**Where the docs live.** The user-facing chapter is "Shell Plugins", chapter 32 of the
Omarchy manual: https://omarchy.org/manual/shell-plugins/ . Developer-facing docs live in
the Omarchy repo itself: a shell reference at
`docs/omarchy-shell.md` and a first-party plugin catalog at `shell/plugins/README.md`
(both on the `quattro` branch of the Omarchy GitHub repo — see §3 for the repo identity
question). The registry site has its own developer pages:
https://plugins.omarchy.org/develop.html and https://plugins.omarchy.org/publish.html .

**What the shell is.** The Omarchy desktop runs as a single long-lived **Quickshell
process called `omarchy-shell`**, and "almost everything you see on screen is a plugin
inside it": the bar, the dropdown panels, fullscreen overlays (emoji picker, clipboard
manager), the Omarchy menu, the lock screen, the polkit dialog, and headless services
(battery watcher, night screen warmer) — all plugins
(https://omarchy.org/manual/shell-plugins/).

**What a plugin actually contains.** A plugin is "a directory with a `manifest.json` and
some QML" (https://omarchy.org/manual/shell-plugins/). The manifest declares
`schemaVersion: 1`, an `id`, `name`, `version`, one or more `kinds`, and an
`entryPoints` object pointing at a QML file per kind. Six kinds exist:

| Kind | What it is |
| --- | --- |
| `bar-widget` | A component the active bar can drop into a section |
| `panel` | A persistent or summoned floating window |
| `overlay` | A fullscreen overlay |
| `menu` | A summoned menu surface |
| `service` | A headless singleton with no UI |
| `bar` | A full bar that replaces the built-in one |

`bar-widget` plugins carry an extra `barWidget` block (display name, category, optional
`defaultSection`, `allowMultiple`). So: **shell plugins are QML code, not themes or
scripts** — themes are a separate Omarchy concept (manual ch. 6/43), and app
installation is handled elsewhere in the distro, not by this plugin system.

**Where plugins live.** First-party plugins ship with the package in
`$OMARCHY_PATH/shell/plugins/`; user-added ones live in `~/.config/omarchy/plugins/<id>/`.
Both are discovered at startup. Ids are namespaced — built-ins all start with `omarchy.`
(`omarchy.clock`, `omarchy.network`, `omarchy.notifications`) and that namespace is
reserved for first-party use (https://omarchy.org/manual/shell-plugins/).

**How plugins are installed.** Third-party distribution is "just a git repo with a
`manifest.json` at its root":

```
omarchy plugin add https://github.com/acme/omarchy-weather.git --enable
```

The CLI clones into a staging dir, validates the manifest, refuses ids already claimed,
moves it into `~/.config/omarchy/plugins/<id>/`. It "never runs anything from the plugin,
never executes an install hook, and never asks for sudo". Updates are fast-forward pulls
(`omarchy plugin update [id]`) with a pre-apply diff, refusal on local changes, and
rollback on failed validation. Removal disables first, then deletes the git checkout (or
unlinks symlinks; hand-made folders get timestamped backups)
(https://omarchy.org/manual/shell-plugins/).

**Enable/disable state.** `omarchy plugin enable|disable <id>` or the GUI menu
*Setup > Plugins* (Enable/Disable/Add/Clone/Remove). State persists in
`~/.config/omarchy/shell.json`: third-party plugins are enabled exactly when their id
appears anywhere in the file (bar layout entry, `plugins[]`, or `bar.id`); first-party
non-bar plugins are on by default and off only via `disabledPlugins[]`. There is always
exactly one bar; you replace it rather than disable it (https://omarchy.org/manual/shell-plugins/).

**Cloning built-ins.** `omarchy plugin clone omarchy.clock` copies a built-in to
`~/.config/omarchy/plugins/<user>.clock`, renames it, enables it, and hot-swaps the
built-in out while keeping bar position/settings; calls to the original id are routed to
the clone. Saving any file under `~/.config/omarchy/plugins/` **hot-reloads** the plugin
code (https://omarchy.org/manual/shell-plugins/).

**Security model.** Plugins are arbitrary, **unsandboxed code inside the long-lived
shell process** — the CLI warns and asks for confirmation before install. Mitigations:
third-party plugins get a "limited interface scoped to their own service and lifecycle"
while built-ins get "trusted shell interfaces"; authentication services are kept outside
the reachable host object graph; a third-party replacement `bar` cannot request another
plugin's live service object, so service-backed widgets may degrade in a custom bar
(https://omarchy.org/manual/shell-plugins/). For the fleet this matters: any Omarchy
plugin we port is code that runs with full user privileges in-process on Omarchy, and
would run as an equally trusted applet/plasmoid on Plasma.

**Registry.** plugins.omarchy.org is the community registry ("marketplace for Omarchy
shell plugins"). It is a JS-rendered site with search (Ctrl-K), filters
(Verified/Unverified), sort modes (recently added/updated, most starred/viewed/copied/
hearts, top ranked, install rate, A–Z), "Hidden Gems" and "Just Landed/Updated" rails,
and theme previews (Tokyo Night, Catppuccin, Gruvbox, Nord, Rosé Pine, etc.)
(https://plugins.omarchy.org/). Listing on it is how authors get discovered; the
underlying distribution mechanism remains plain git repos.
## 2) Shell Plugins API Surface

**Manifest contract** (schemaVersion 1). Required: `schemaVersion`, `id`, `name`, `version`,
`author`, `description`, `kinds[]`, `entryPoints{}`; optional `license`, `barWidget{}`,
`keepLoaded`, `omarchy.clonedFrom`
(https://plugins.omarchy.org/publish.html,
https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md):

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock", "category": "Time",
    "allowMultiple": false, "defaultSection": "left",
    "defaults": { "format": "HH:mm" },
    "schema": [ { "key": "format", "type": "string", "label": "Format" } ]
  }
}
```

Note `barWidget.defaults` + `schema`: **the shell auto-generates a settings UI** for
widget options from the manifest schema — the Omarchy equivalent of Plasma's QML
config delegates (https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).

| Kind | `entryPoints` key | File loaded | Use it for |
| --- | --- | --- | --- |
| `bar-widget` | `barWidget` | `BarWidget.qml` | Item in the active bar |
| `panel` | `panel` | `Panel.qml` | Floating surface |
| `overlay` | `overlay` | `Overlay.qml` | Fullscreen surface |
| `menu` | `menu` | `Menu.qml` | Summoned menu |
| `service` | `service` | `Service.qml` | Headless singleton |
| `bar` | `bar` | `Bar.qml` | Full bar replacement |

(https://plugins.omarchy.org/develop.html)

**Host-injected context.** Entry points are QML `Item`s. On load the host injects
`omarchyPath`, `shell`, `manifest`, and the registries (`pluginRegistry` /
`barWidgetRegistry`) as properties. Built-ins receive the **trusted host objects**;
third-party plugins receive **capability-scoped facades**: an ordinary plugin may look
up and control only its own service and lifecycle; menu plugins get an
application-library facade; a full-bar plugin gets detached bar configuration +
widget-catalog snapshots + narrow proxies for non-authentication services.
Authentication services are excluded from the host's public service map and QML object
tree. The docs are explicit that "the facades are API boundaries, not same-process QML
sandboxes" — a visual plugin shares the bar's scene and can walk its parent hierarchy
(https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).

**Framework + UI base classes.** Plugin QML imports `QtQuick`, `Quickshell`, and the
shell's own modules `qs.Ui` / `qs.Commons`. The develop tutorial shows the canonical
widget shape: extend `BarWidget` (gets `bar`, `moduleName`, `settings`, `fixedEdge`),
embed a `WidgetButton`, lazy-load a `Panel.qml` that extends `Panel` +
`KeyboardPanel` (anchored to the bar button, Escape via `PanelKeyCatcher`), use
`SystemClock`, `Style`, `Color`, `Border` singletons
(https://plugins.omarchy.org/develop.html). Panels/overlays/menus expose
`open(payloadJson)` / `close()` and are summoned via IPC.

**Summon/IPC API** (the shell's control plane, `omarchy-shell shell <method>`):
`ping`, `summon <id> <payloadJson>`, `hide <id>`, `toggle`, `togglePanelAt <section>
<index>`, `call <id> <method> <arg>`, `rescanPlugins`, `reloadConfig`, `applyTheme
<colorsB64> <shellB64>`, `toggleBarTransparency`, `cycleInput <next|back>`,
`setPluginEnabled`, `enablePlugin <id> <placementJson>`, `putBarWidget`,
`moveBarWidget`, `setBarWidget <id> <key> <valueJson> <selectorJson>`, `listPlugins`,
`listShellConfig`, `debugBarGeometry`. Plugins can also register their own IPC targets
(`background`, `osd`, `media`, `notifications`, per-widget ids)
(https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).

**Configuration.** All shell config is `~/.config/omarchy/shell.json` (version 1):
`bar.id` + `bar.position` + `bar.background` + `bar.layout` with sections `left`,
`centerBegin`, `center`, `centerEnd`, `tray`, `right`; `plugins[]`; `disabledPlugins[]`;
`idle{screensaver,lock}`. Settings are inline on each layout entry — no merge layers,
no `config:` sub-object. Theme tokens live separately in `shell.toml` (machine-level
`~/.config/omarchy/shell.toml` overrides the active theme, watched live)
(https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).

**Theming API** exposed to QML via three singletons in `qs.Commons`: `Color` (palette
`foreground/background/accent/urgent` + per-surface roles `bar.*`, `popups.*`,
`tooltip.*`, `notifications.*`, `menu.*`, `polkit.*`, `lock.*`, `imagePicker.*`),
`Style` (cornerRadius, `Style.spacing.*`/`Style.space(px)` with `[spacing] scale`,
type scale `Style.font.*` derived from `[font] base-size`, bar dimensions, motion via
`Style.duration(ms)` honoring `omarchy toggle animations`), `Border` (gradient border
specs) (https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).

**Escape hatch — custom bar modules.** Without writing a full plugin you can declare
inline modules in `bar.layout.<section>`: `{"type":"command","exec":...,"interval":5}`
accepting **plain text or Waybar-style JSON** (`{text,tooltip,class}`), or
`{"type":"qml"}` pointing at `~/.config/omarchy/bar/modules/gpu.qml` which receives
`bar` (`foreground/background/urgent/fontFamily`, `run(cmd)`, tooltips, popouts),
`moduleName`, `settings` (https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).
This is the closest Omarchy analog to Plasma's "command in a plasmoid" pattern.

**Validation/lint.** `omarchy plugin validate ./dir` (manifest schema, reserved ids,
safe relative entry paths, entry-point-per-kind, no symlinks) and `qmllint -I
$OMARCHY_PATH/shell` against the installed shell imports
(https://omarchy.org/manual/shell-plugins/, https://plugins.omarchy.org/develop.html).

**What is Omarchy-specific (non-portable to plain Plasma 6):**
- The plugin runtime itself: `manifest.json` discovery, `PluginRegistry.qml`, hot-reload
  on save, capability facades, `shell.json` layout store — Plasma's equivalents are
  plasmoid metadata.desktop/metadata.json, KPackage/PlasmaPackage, plasma-desktop
  containment/layout model.
- `qs.Ui`/`qs.Commons` base classes (BarWidget, Panel, KeyboardPanel, Style/Color/Border
  token singletons tied to `shell.toml` themes).
- The `omarchy-shell` IPC socket and `summon/hide` lifecycle; keepLoaded semantics.
- Hyprland coupling in specific built-ins: the dock reads workspace floating/tiled mode
  through `omarchy-hyprland-workspace-layout-current`; popout placement follows
  Hyprland `general:gaps_out`; cycleInput depends on an input reader
  (https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).
- Wayland layer-shell windows (Quickshell `PanelWindow`/`WlSessionLock`) — Plasma
  applets live inside the shell's own window/containment hierarchy instead.

What ports cleanly is the QML *component* logic (QtQuick is shared) and any
HTTP/file-watching service logic; what must be re-expressed is chrome, placement,
sizing (Plasma applet popups are host-sized via Layout.minimumWidth/Height vs
Quickshell honoring PanelWindow width/height — fleet-known from the Oct 30 stocktick
campaign), and IPC (Plasma QML cannot spawn processes, so CLI-driven plugins must
become HTTP-API-driven on the KDE side).
## 3) The Current Omarchy Shell Stack

**Identity and version.** The Omarchy repo is now **`omacom/omarchy`** — the GitHub org
was renamed from `basecamp` (the API returns the same repo id 994093166 for both
paths: https://api.github.com/repos/basecamp/omarchy → `full_name: "omacom/omarchy"`).
Default branch: **`quattro`**. MIT license, 46,908 stars, 6,082 forks, created
2025-06-01, last push 2026-11-12 (https://api.github.com/repos/omacom/omarchy). The
root `version` file reads **`4.0.0.alpha`** — "Omarchy Quattro" is Omarchy 4
(https://raw.githubusercontent.com/omacom/omarchy/quattro/version), and the plugin
registry explicitly targets "Omarchy Quattro" (https://plugins.omarchy.org/).

**The stack: Waybar is gone; it's Quickshell now.** "Omarchy is an omakase Linux
distribution based on Arch, the tiling window manager Hyprland, and the desktop
construction-kit Quickshell" (https://omarchy.org/manual/). The whole desktop — bar,
panels, overlays, menus, lock, polkit, OSD — is one long-lived Quickshell process,
`omarchy-shell`, launched by Hyprland autostart via `omarchy-launch-shell`
(https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md).
Third-party coverage agrees: "It uses Hyprland as the window manager and Quickshell as
the toolkit for building custom desktop interfaces"
(https://www.howtogeek.com/i-tried-the-viral-linux-distro-that-raised-millions/).

Migration residue visible in the docs: the built-in polkit agent "replac[es] the old
`polkit-gnome-authentication-agent-1` autostart", and custom command modules still
accept "Waybar-style JSON" output for backward familiarity — both strong indicators
the pre-Quattro stack ran Waybar + separate helper daemons
(https://raw.githubusercontent.com/omacom/omarchy/quattro/shell/plugins/README.md,
.../docs/omarchy-shell.md). (The exact v1–v3 component list — Waybar/SwayOSD/wlogout
etc. — is covered in §10 as partially unverified.)

**Session layer** (from the repo's `default/` tree,
https://api.github.com/repos/omacom/omarchy/contents/default?ref=quattro): `hypr`
(Hyprland config), `sddm` (display manager), `uwsm` (universal Wayland session
manager), `wireplumber`/`alsa` (audio), `snapper` (snapshots), `plymouth`, `limine`
(bootloader), `wayland-sessions`, plus app defaults: `alacritty`, `chromium`,
`firefox`, `slack`, `nautilus-python`, and DHH-ecosystem apps `herdr-app`, `tensaku`,
`voxtype`. The `themes/` tree ships the ~20 color themes previewed on the marketplace.

**First-party plugins = the desktop.** 26 built-ins ship in `$OMARCHY_PATH/shell/plugins/`
(https://raw.githubusercontent.com/omacom/omarchy/quattro/shell/plugins/README.md):

| Plugin | id | kinds |
| --- | --- | --- |
| Bar | `omarchy.bar` | `bar` |
| Omarchy menu | `omarchy.menu` | `menu`, `bar-widget` |
| Image picker | `omarchy.image-picker` | `overlay` |
| Emojis | `omarchy.emojis` | `overlay` |
| Clipboard mgr | `omarchy.clipboard` | `overlay` |
| Reminders | `omarchy.reminders` | `overlay` |
| Notifications | `omarchy.notifications` | `service` |
| Media | `omarchy.media` | `service`, `bar-widget` |
| Battery / Idle / Night light / Remote session / Lock / Polkit | `omarchy.{battery,idle,nightlight,remote-session,polkit}` + `omarchy.lock` | `service` |
| OSD | `omarchy.osd` | `panel` |
| Dock | `omarchy.dock` | `service` |
| Audio, Bluetooth, Clock, Elsewhen (world clock), Monitor, Network, Power, Tailscale, Agents, Weather | `omarchy.{audio,bluetooth,clock,elsewhen,monitor,network,power,tailscale,agents,weather}` | `bar-widget` |

Notable: **`omarchy.agents` is a first-party bar widget** (the "agentic Linux" pitch —
agent status in the bar), the lock screen uses Quickshell's native `WlSessionLock` +
PAM, and the Omarchy menu's entries are JSONC files
(`default/omarchy/omarchy-menu.jsonc` + user `~/.config/omarchy/extensions/`) evaluated
with batched bash `when:`/`checked:` expressions and `Quickshell.execDetached` actions.
A `omarchy.theme-switcher` plugin is listed as "coming soon".

**Implication for the fleet:** everything the fleet would port from "Omarchy plugins"
is Quickshell QML against `QtQuick` + `Quickshell` + `qs.Ui`/`qs.Commons` — there is no
separate Waybar CSS/config layer left to port. Config/theme packages (themes, menu
JSONC, `shell.toml`) are portable as data; widgets/panels are QML ports.
## 4) Plugin Catalog (plugins.omarchy.org)

**Size and shape.** The registry's machine-readable source is `registry.json` in
`github.com/omacom/omarchy-plugin-marketplace`
(https://raw.githubusercontent.com/omacom/omarchy-plugin-marketplace/main/registry.json,
14 MB, fetched 2026-11-12). It lists **6,464 plugins across 6,462 GitHub repos** (a
repo usually carries one plugin; a few are multi-plugin), plus 138 retired ids and 110
repository migrations. Listing is by GitHub issue form with automated validation +
maintainer approval (https://plugins.omarchy.org/publish.html). Coverage:
`automatedSecurityBaseline` on 6,422/6,462 (99%), `maintainerVerificationReview` on
2,939 (45%) — the site's Verified/Unverified filter.

**Growth** (by `addedAt` month): 2026-07: 16, 2026-08: 1,944, 2026-09: 2,476,
2026-10: 1,697, 2026-11 (through 11/12): 329. The marketplace exploded in Aug 2026 —
roughly two months after Quattro landed. ~2,000 new listings/month at peak.

**Categories** (registry counts): Widgets 1,743 · Productivity 1,270 · System 1,050 ·
Hardware 671 · Desktop 590 · Appearance 495 · Developer Tools 494 · Other 127 · Kids 24.

**Tags** (self-declared): `bar` 4,661 (72%) · `quickshell` 4,463 (69%) · `system` 1,559
· `hyprland` 1,394 · `media` 858 · **`ai` 666 (10%)** · `workspaces` 459 · `launcher`
441 · `security` 399 · `power-management` 273 · `games` 242 · `education` 119 · `vpn`
62 · `kids` 28. Because the manifest contract requires QML entry points, **every
listed plugin is QML code**; there is no theme/config/script plugin class in the
registry itself. Themes are a parallel track (the ~20 Omarchy themes are previewed on
the marketplace and live in the distro's `themes/` tree; converter tools treat them
separately), and heavyweight integrations appear as "manual-setup" listings (e.g.
Wizmo-inc/plasmarchy, per its README).

**Fleet-relevant clusters** (from registry keyword/tag sweep):
- **AI/agent usage lane — the ecosystem's hottest category.** `robzolkos.agent-usage`
  ("weekly Claude and Codex usage, reset countdowns, prorated pace" — the plugin the
  official develop tutorial uses as its exemplar), `io.github.arthurr0.claude-usage`
  (5h-session + weekly limit meters with warn/critical thresholds),
  `felixzsh.codexbar` ("every AI coding limit in one panel, powered by the CodexBar
  CLI" — Codex, Claude, OpenCode Go, Gemini, Copilot), `io.github.aval4nch.agents-
  claude-status` (first-party agents panel + live Claude Code session status with
  color/pulse for working/waiting/blocked, plus cross-device sync), plus ~15 more
  `claude`-named and ~14 `codex`-named repos, `omarchy-ollama-*`, `omarchy-ai-usage`
  family, LM Studio/Gemini/Z.ai trackers. Manifests fetched 2026-11-12 from each repo.
- **Notification centers:** ~27 (apach, abran-labs, gabodev, "yet-another..." etc.) —
  all rebuilding what `omarchy.notifications` + Plasma both already own.
- **Weather:** ~36. **Todo/tasks:** ~25 + ~27. **Launchers/menus:** ~443 + ~53.
- **VPN/Tailscale:** 108 tagged vpn, 6 tailscale-specific. **Docker:** 10.
- **Wallpapers/docks/locks:** 47 wallpaper engines/docks themes, 62 docks, 107 lock-related.
- **Games:** 242 tagged (Quattrolitaire, tetris, minesweeper, sudoku in your bar).
- **Full-shell "suites":** exactly 2 — Lacuna (OldJobobo/lacuna-shell: "a complete
  visual shell for Omarchy with a custom bar, attached utility sidebar, system
  controls") and SHIBUMI (HANCORE-linux/Shibumi-Shell).

**Duplication is extreme**: 36 weathers, 27 notification centers, 25 todos — the
catalog is a gold-rush, and quality/relevance sorting matters more than raw count.
## 5) Portability Classification Table (top ~10 by fleet interest)

Port shapes: **(a) Quickshell-verbatim** — runs as-is/ lightly-patched under Quickshell
in a Plasma Wayland session (KWin supports layer-shell; Wizmo-inc/plasmarchy proves the
Omarchy bar itself runs there; Bazzite has quickshell 0.2.1 stock / 0.3.2 via COPR —
parent-verified fleet facts). **(b) Plasma applet** — rewrite as a native plasmoid
(panel/systemtray embed, popup sizing host-owned via Layout.minimumWidth/Height,
QML cannot spawn processes → CLI features become HTTP calls). **(c) No port needed** —
data/config/theme package or a feature Plasma already owns natively.

| Plugin | What it does | Port shape | Notes / effort |
| --- | --- | --- | --- |
| `robzolkos.agent-usage` | Claude+Codex weekly usage, reset countdowns, pace, in bar | **(b) Plasma applet** | Pure QML + local data parsing; schema-generated settings → Plasma config delegates. Low-med. The fleet's highest-value lane. |
| `io.github.arthurr0.claude-usage` | Claude 5h/weekly limit meters, warn/critical %, per-window popup | **(b) Plasma applet** | Same lane; rich defaults already enumerated in manifest. Low-med. |
| `felixzsh.codexbar` | All-provider AI limits "powered by the CodexBar CLI" | **(b) applet + HTTP service** | CLI-driven → must become HTTP API (fleet Plasma rule); needs a small local daemon. Med. |
| `io.github.aval4nch.agents-claude-status` | First-party agents panel + live Claude Code session status, sync | **(b) Plasma applet** | Depends on `omarchy.agents` host integration + session-status watcher; strip host coupling, keep status model. Med-high. |
| `omarchy.agents` (first-party) | Agent status in bar — DHH's "agentic Linux" centerpiece | **(b) Plasma applet** | No upstream port exists; the pattern (agent presence/status in shell chrome) is the mine, not the code. Med. |
| `daniellemky/omalaunch` | Extensible command launcher (menu + bar-widget, keepLoaded) | **(b) — prior art exists** | majesticio/plasmarchy ships a maintained native recipe for it. Plasma owns app launching (KRunner) — port the *extensibility pattern* only. Low (recipe exists). |
| `OldJobobo/lacuna-shell` (suite) | Complete replacement shell: bar, sidebar, controls | **(a) Quickshell-verbatim** | A full Quickshell shell, not an applet; run it under KWin as Wizmo does with omarchy.bar. Not a Plasma-native port. |
| `omarchy.bar` (first-party) | The built-in bar | **(a) proven** / (c) mostly | Wizmo-inc/plasmarchy already runs it in a Plasma session. As Plasma panels/taskbar: Plasma owns it — no port. |
| Notification centers (×27) | Rebuild notification UI | **(c) no port** | Plasma 6 owns notifications; mine only the rules-engine pattern (one plugin). |
| Weather (×36, + fleet's WeatherX) | Bar weather + radar panels | **(b) for fleet's own omarchy-weather only** | Stock Plasma weather widget covers basics; port the fleet's keyless WeatherX as an applet (HTTP, no spawn). Med. |
| Clipboard / emoji / reminders / lock / polkit / OSD / clock / audio-bt-network-power widgets | The built-in chrome | **(c) no port** — Plasma owns all | Exception: **emoji picker is a real Plasma 6 gap** (no built-in picker) — port `omarchy.emojis` as an overlay/shortcut applet. Klipper covers clipboard; KScreenLocker/polkit-kde/kscreen-osd cover the rest. |
| Themes (colors.toml/shell.toml) | The Omarchy look | **(c) conversion** | majesticio/plasmarchy already converts palettes → KDE color scheme + Plasma Style + Global Theme. Solved prior art. |
## 6) Porting Economics

- **Supply is enormous, value is concentrated.** 6,464 plugins, but ~72% are bar
  widgets, with heavy duplication (36 weathers, 27 notifiers). After the
  "Plasma-already-owns-it" filter (KRunner apps/windows/calculator/units/timers/file
  search, notifications, clipboard, OSD, lock, polkit, network/bluetooth/audio/battery
  device widgets, clock, panels/taskbar) and the duplication filter, the realistic
  port backlog is **~10–15 plugins**: the AI/agent-usage lane (4–6 repos), tailscale,
  docker, a todo widget if wanted, the emoji-picker gap, plus the fleet's own 15
  plugin repos (§8).
- **Effort shape per applet port** (grounded in the fleet's Oct 30 stocktick campaign
  translation table + this API review): shared QtQuick component logic ports nearly
  verbatim; the work is (1) chrome re-skin from `qs.Ui`/Style tokens to Plasma's
  theme system (or keep a token shim), (2) popup sizing — host-owned
  Layout.minimumWidth/Height instead of honored PanelWindow width/height, logical
  coordinates only (never × devicePixelRatio), (3) IPC — `omarchy-shell shell summon`
  and `Process`-spawning become DBus/HTTP; CLI-driven widgets (codexbar) need a tiny
  local HTTP daemon, (4) manifest `schema` → Plasma `ConfigModel`/config delegates,
  (5) strip Hyprland coupling (dock workspace-layout reads, gaps_out alignment).
- **Rough sizing**: a data-parsing bar widget (claude-usage class) ≈ 1–2 days to a
  polished applet; a panel-rich one (agents + session status) ≈ 3–5 days; the whole
  valuable subset ≈ 2–4 fleet weeks including QA on Bazzite.
- **Registry churn is a maintenance risk**: 138 retired ids and 110 repo migrations in
  ~4 months; a port should pin upstream commits (Plasmarchy records exactly this).
- **Cheap alternative lane**: Quickshell 0.3.2 (COPR) runs in a Plasma Wayland session,
  so any plugin can be smoke-tested near-verbatim before committing to a native applet
  port — use it as the triage bench, then port only what survives.
- **Not worth porting**: anything whose entire value is "exists in the bar" when
  Plasma's panel/systemtray already provides the surface (clocks, notifiers, media
  controls — Plasma's MMC widget), and anything reading Hyprland-only state.
## 7) Prior Art: Omarchy-on-KDE

Two independent projects named "Plasmarchy" exist (plus passing references below):

**1. `majesticio/plasmarchy` — an Omarchy→Plasma *converter tool***
(https://github.com/majesticio/plasmarchy). "Ports Omarchy themes and shell plugins
into native KDE Plasma 6 packages." Key properties from its README:
- CLI mirrors the Omarchy workflow: `plasmarchy plugin add <repo> --enable` (also
  `widget add`, `theme add`, `update`, `remove`, `rollback`, `list`, `test`, `doctor`);
  the optional word `omarchy` is a copy-paste compatibility prefix.
- Themes convert to **KDE color scheme + Konsole scheme + Plasma Style + Global Theme +
  wallpaper payload**. Supported shell plugins convert to `Plasma/Applet` KPackages.
  Ships "a maintained native recipe for Omalaunch" (daniellemky/omalaunch launcher).
- Installs to user XDG paths only (never `/usr/share`), records upstream commits, keeps
  the previous build for rollback; AUR package `plasmarchy`, release v0.1.0rc1.
- Security model: remote source is data until conversion; git hooks disabled; no repo
  installers executed; static native audit flags **forbidden runtime coupling: Omarchy
  shell IPC, Hyprland commands, `qs.Commons`, `qs.Ui`, paths under
  `~/.config/omarchy`**.
- Crucial honesty for the fleet: "**Arbitrary QML cannot be translated safely by string
  substitution.** When a repository uses an unsupported host API, Plasmarchy stops with
  a port report that names the files, symbols, and adapter categories required. It
  never installs a placeholder or half-working widget." I.e., automated conversion is
  recipe-based and bounded — the same conclusion the fleet's Foyer campaign reached.

**2. `Wizmo-inc/plasmarchy` (by cobraxai) — the Omarchy shell *running inside* Plasma**
(https://github.com/Wizmo-inc/plasmarchy). "The Omarchy shell and theme experience on
top of KDE Plasma's fluid window management... using KWin for window tasks,
minimization, virtual desktops, effects, and overview." Properties:
- Runs the **Omarchy Quickshell bar in a Plasma (Wayland) session** at the bottom,
  with theme-aware quick launchers merged with KWin window tasks, pin/unpin, Show
  Desktop, virtual-desktop switcher, KRunner shortcut.
- Syncs the Omarchy palette/icons/wallpaper into Plasma; optional Omarchy-styled SDDM
  + KScreenLocker-based idle screen; routes Print Screen through Omarchy's capture
  flow via Spectacle/`wl-copy`; drag-to-select recording via `gpu-screen-recorder`.
- Ships "Omarchy Agents usage panel and the `omatask` system monitor" and a global
  `codex-resume-all` picker.
- **Requires an existing Omarchy installation** — it's a session choice added to
  Omarchy, not a standalone KDE distro. First tested combination: **Omarchy
  `4.0.0.r1836.g0ae1694-1`, Plasma `6.7.4`, Quickshell `0.3.1`** — the best
  public version triangulation for the Quattro stack.
- It is itself **listed on the Omarchy Plugins marketplace as a "manual-setup"
  plugin** — the ecosystem's first Omarchy↔KDE bridge entry.

**Passing references (sibling lanes own the deep dives):** end-4dots-kde (Hyprland
dotfiles with a KDE-inspired aesthetic) and NextKde/KOS (KDE-first ricing) both chase
the same "beautiful minimal shell" goal from opposite directions; neither is an
Omarchy plugin port. General "Omarchy look on KDE" demand shows up as theme-conversion
requests, which majesticio/plasmarchy's theme pipeline directly addresses. No evidence
found of a Plasma *applet-by-applet* port program comparable to the fleet's Foyer
campaign — the fleet would be first to do it at scale with native applets.
## 8) Fleet Reference Repos (public API only, no private repos touched)

Queried `https://api.github.com/users/gdeyoung/repos` (3 pages, 2026-11-12) for
`omarchy|quickshell` in name/description — **17 public repos**, which split into three
kinds:

*The fleet's own Omarchy plugins (the Foyer campaign's output — these are themselves
port candidates for the KDE side):*
- `gdeyoung/omarchy-foyer` — "the Omarchy front door: full menu tree on open, live
  all-source search, one-row AI answers, custom handoffs, timers and everyday wins"
- `gdeyoung/omarchy-appdock` — "KDE-style task manager + minimize engine for Omarchy
  (Hyprland 0.56): dock widget, per-workspace icons, hyprbars titlebar buttons"
- `gdeyoung/omarchy-weather` — "WeatherX: extended weather — tabbed panel, pinned
  places, live keyless radar (Esri + RainViewer), Open-Meteo. No API keys"
- `gdeyoung/omarchy-audiofx` — "audio panel with system-wide effects, per-app routing
  + pins — drop-in replacement for omarchy.audio"
- `gdeyoung/omarchy-powercore` — "battery/power: per-source profiles, battery
  protection, clamshell, keyboard backlight, live watts"
- `gdeyoung/omarchy-displayplus` — "brightness, text size, universal scale + full
  hyprmoncfg layout editor"
- `gdeyoung/omarchy-driveway` — "USB/disks, SMB/NFS/sshfs shares, rclone cloud mounts"
- `gdeyoung/omarchy-ready-room` — "gaming panel: game mode toggles, controller battery
  and test, instant replay, MangoHud-linked FPS overlay"
- `gdeyoung/omarchy-tailfin` — "Tailscale status: device list, connection state,
  subnet routes, self-IPs"
- `gdeyoung/omarchy-timemachine` — "unencrypted rsync time machine — status chip +
  5-tab popup + bundled engine"
- `gdeyoung/omarchy-timepiece` — "clock: date in bar, world-clock row, countdown timer
  + pomodoro (fork of stock clock)"
- `gdeyoung/omarchy-sysmon` — "RAM, CPU, network rate, whole-disk stats — one widget"
- `gdeyoung/omarchy-armoury` — "ASUS laptop control: temps, fan, battery care mode"
- `gdeyoung/omarchy-ultrawide-bar` — "fork of the stock bar: partial width for
  ultrawides, fullscreen auto-hide" (2 stars)
- `gdeyoung/flea` (fork) — "fast, keyboard-first file manager for Omarchy: Quickshell
  front end, Rust backend"

*Knowledge/pattern repos:* `gdeyoung/omarchy-recipes` ("how to run a heavily customized
Omarchy machine as code — recipe-repo discipline, update-overwrite model, plugin
hygiene") and `gdeyoung/omarchy-skills` ("agent skills for Omarchy: triage +
reporting, plugin development, shell-plugin debugging. Live-CLI-verified on 4.0.x").

So the fleet is not just a consumer: it already **authors** Quattro plugins (all
Quickshell QML), and those repos are the primary porting backlog for the KDE target.
Source: https://api.github.com/users/gdeyoung/repos?per_page=100 (public API).
## 9) Implications For The Fleet

- **The campaign's premise holds**: every Omarchy plugin is Quickshell QML against
  QtQuick + `qs.Ui`/`qs.Commons`. The fleet's Oct-30 translation table (PanelWindow
  sizing → host-owned Layout.minimumWidth/Height; logical coords only) is the
  ecosystem-wide porting law, not a one-off.
- **The port backlog is the fleet's own shelf.** The 15 gdeyoung plugin repos (§8) +
  the external AI-usage lane (agent-usage / claude-usage / codexbar /
  agents-claude-status, §5) are the only imports that clear the
  "Plasma-doesn't-already-own-it" bar. Everything else in the 6,464-plugin catalog is
  duplication or Plasma-owned surface.
- **Two proven KDE strategies, pick deliberately**: (1) native applet conversion —
  majesticio/plasmarchy proves it's recipe-bounded, not general ("arbitrary QML cannot
  be translated safely by string substitution"); (2) Quickshell-in-Plasma — Wizmo proves
  the whole Omarchy bar runs under KWin. For Bazzite fleet targets, native applets stay
  the goal; Quickshell 0.3.2 via COPR is the triage bench, not the destination.
- **Patterns worth mining** (not feature lists): manifest `schema` → auto-generated
  settings UI (maps to Plasma config delegates); `summon`/`hide` IPC → DBus activation
  for opening applet popups from scripts; `keepLoaded` semantics; hot-reload on save;
  the "clone a built-in to learn it" flow (a great onboarding device for Plasma applet
  dev too); capability-scoped facades for third-party code; Waybar-JSON command
  modules as a compatibility tier.
- **Genuine Plasma gaps surfaced by the catalog**: emoji picker (no built-in Plasma 6
  picker), agent/AI-usage surfacing in shell chrome, tailscale status widget. These are
  where Omarchy ports add net-new capability to KDE rather than duplicating it.
- **Risk posture**: registry churn (138 retirements / 110 migrations in ~4 months) —
  pin upstream commits in every port; upstream is MIT (omacom/omarchy) so licensing is
  clean, but individual plugin licenses vary and were not audited.
- **The lock-screen lesson**: `omarchy.lock` (WlSessionLock) cannot follow the bar into
  a Plasma session — KScreenLocker owns that surface (Wizmo rebuilt it that way).
  Expect the same boundary for polkit (polkit-kde) and OSD (kscreen-osd).
## 10) Unverified / Open Questions

- **Quickshell version pinned by Omarchy 4.0.0.alpha itself**: Wizmo's README states
  it was "first tested" against Quickshell 0.3.1, but Omarchy's own package/install
  list (`install/` dir in the repo) was not inspected to confirm the pin.
- **Pre-Quattro component list**: "Waybar-style JSON" support and the
  polkit-gnome replacement note strongly imply the old stack (Waybar + SwayOSD +
  wlogout + rofi-class helpers), but no primary page enumerating the v1–v3 stack was
  verified (the Wikipedia REST call failed). Treat the Waybar-removal claim as
  verified; the precise old-component list as inferred.
- **Marketplace popularity metrics**: the site sorts by most-starred/viewed/copied and
  shows install rate, but those numbers live outside `registry.json` (likely a worker
  output); the "top" plugins here were selected by fleet relevance + registry tags,
  not by measured popularity.
- **Rendered catalog page counts**: plugins.omarchy.org is JS-rendered; the 6,464
  figure comes from `registry.json`, not a rendered-page count.
- **`omarchy.theme-switcher`**: listed as "coming soon" in `shell/plugins/README.md`;
  shipping status today unknown.
- **Omalaunch's Plasmarchy recipe maturity** and majesticio/plasmarchy beyond
  v0.1.0rc1 (AUR packaging tested?) — not exercised.
- **WlSessionLock/layer-shell behavior under KWin** for arbitrary plugins (proven for
  the bar by Wizmo; not for every plugin kind).
- **Org rename date** (basecamp → omacom) not pinned; only the redirect is verified.
- Whether the marketplace enforces per-plugin license metadata (publish guide lists
  license as recommended, not required).

## Checked vs Not-Checked

**Checked (primary sources, 2026-11-12):**
- https://omarchy.org/manual/shell-plugins/ (full chapter) and manual index
- https://plugins.omarchy.org/ (index), /develop.html, /publish.html (full guides)
- https://raw.githubusercontent.com/omacom/omarchy/quattro/docs/omarchy-shell.md (full,
  incl. IPC table, shell.json rules, theme tokens, custom bar modules)
- https://raw.githubusercontent.com/omacom/omarchy/quattro/shell/plugins/README.md
  (full first-party catalog)
- omacom/omarchy repo metadata via GitHub API (org rename redirect verified),
  `version` file (4.0.0.alpha), `default/` tree, root tree
- Marketplace `registry.json` (14 MB) — all 6,462 sources parsed: counts, categories,
  tags, verification coverage, growth by month, suites, retirements/migrations
- Plugin manifests fetched: robzolkos/omarchy-agent-usage,
  arthurr0/omarchy-claude-usage, felixzsh/omarchy-codexbar, daniellemky/omalaunch,
  AvAl4nch/omarchy-agents-claude-status
- majesticio/plasmarchy README (full) and Wizmo-inc/plasmarchy README (full)
- gdeyoung public repos via GitHub users API (3 pages; omarchy/quickshell filter)
- Web search sweep for Omarchy-on-KDE prior art

**Not checked:**
- plugins.omarchy.org rendered per-plugin pages, search UI, popularity metrics
- Omarchy `install/` scripts (exact package list incl. quickshell pin)
- Wikipedia's Omarchy article (REST call failed)
- Middle third of omarchy-shell.md already partially read; popup/window sections beyond
  line 349 not read
- Quickshell upstream capabilities (sibling lane), end-4dots-kde and NextKde/KOS
  internals (sibling lanes, referenced in passing only)
- Individual plugin licenses / code quality audits; AUR build of plasmarchy
- Any private fleet repos (public API only, per scope)
