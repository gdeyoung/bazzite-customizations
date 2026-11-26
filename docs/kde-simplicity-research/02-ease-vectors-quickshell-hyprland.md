# Why Quickshell & Hyprland feel 10× easier than KDE plasmoid development — an ease-vector decomposition

**Dossier 02 · kde-simplicity-research** · Compiled 2026-11-04 (CST) · Subagent: research (cloud-dev)
Scope: decompose *why* the Quickshell/Hyprland extension loops feel effortless into named, evidenced ease vectors; verify which of those KDE Plasma has today; produce a verified candidate table of easy shell-customization frameworks incl. KWin layer-shell status. Host context: Bazzite stable (Fedora 45 base, `kwin-6.8.2`, `plasma-workspace-6.8.2` — verified locally 2026-11-04).

Method: primary = project docs/repos/wikis/releases + distro packaging APIs + a live probe of this host's own package repos; secondary = GitHub issue trackers; tertiary = community. Tier labels: **S** = official docs/source/primary repo; **A** = vendor blogs/release notes/official wiki mirrors; **B** = independent tech media; **C** = Reddit/forums/issues; **F** = fleet-verified local knowledge (skills `plasma-plasmoid-development` v1.7.1, `omarchy-plugin-porting` v1.0.0 — both verified on Plasma 6.7.5/Bazzite). Missing values are marked `unknown`, never inferred. GitHub release/commit metadata = GitHub REST API snapshot 2026-11-04.

---

## 0. Executive summary + premise corrections

**Thesis.** The 10× feeling is not one feature — it is ~12 compounding loop shorteners (named in §4). The three highest-leverage ones — zero-build artifacts, sub-second save→see reload, and single-file source of truth — are genuine gaps on KDE for *live-shell* iteration, but all three are closable with a thin fleet tool (a watch-mode wrapper around `kpackagetool6` + the already-proven evaluateScript re-add pattern), not with a framework migration. Conversely, KDE already *wins* three vectors outright (declarative config schema→UI via KConfigXT, one-click store distribution via GHNS, and a no-compile embedded applet model that Hyprland plugins can never offer because they are compiled C++ into the compositor process). The bridge question resolves favorably: KWin has implemented `zwlr_layer_shell_v1` since **September 2020** — Quickshell/EWW/Ironbar-class chrome can run as Plasma companion surfaces today, with four specific caveats (§5).

**Premise corrections (load-bearing):**

1. **"Quickshell is NOT in Fedora repos" — FALSE.** Verified three ways: (a) Quickshell's official install docs list "Release versions of Quickshell are available in Fedora Rawhide … `sudo dnf install quickshell`" plus a dedicated COPR (`errornointernet/quickshell`) [S: docs install page, §Sources 2]; (b) Repology shows `quickshell 0.2.1^git20260209` in fedora_44 *and* fedora_rawhide [S: 10]; (c) **live probe of this host (Bazzite F45): `dnf list --available quickshell` → `quickshell.x86_64 0.2.1^git20260209.dacfa9d-5.fc45 fedora`** — i.e. `rpm-ostree install quickshell` works on the boss's machine today with no layering-from-COPR and no build. Nuance: the Fedora package is a git snapshot of 0.2.1, behind upstream 0.3.2 (2026-10-08); the COPR carries both `quickshell` and `quickshell-git`.
2. **"KWin's layer-shell support is new/limited (6.1-era)" — if assumed, FALSE.** The implementing commit is `Implement layer-shell v1 protocol`, Vlad Zahorodnii, **2020-09-03** [S: 17] — Plasma 5.20-era, six years of hardening since (keyboard-interactivity fixes !4578/!4579 Nov 2023, output-removal handling !6749, popup integration tests !9046, critical-notification layer fix !9610 Jul 2026) [S: 18]. See §5.
3. **"Porting Foyer (a Quickshell app) to KDE loses KRunner's ecosystem and adds a second launcher mental model" — stands, un-reverified.** This dossier adds one nuance: KRunner runners are DBus services, so a *companion* Quickshell launcher could in principle shell out to them via `Process` — plausible, **unverified**; the two-launcher UX objection is unaffected.
4. New fact worth recording: **HyprPanel is dead** — archived by its owner 2026-04-27; successor **Wayle** (Rust, "compositor-agnostic… assuming the compositor implements the layer shell protocol") [S: 29]. And current Hyprland exposes a **Lua config/scripting API** (`hl.plugin.load`, `hl.config`) alongside hyprlang [S: 12].

---

## 1. Candidate table — easy shell-customization frameworks (bars/widgets/panels on Wayland), Plasma/KWin compatibility

Cells cite the numbered sources in §Sources by `[n]`. `unknown` = could not be verified in budget; never inferred. "layer-shell" = `zwlr_layer_shell_v1`.

| Framework | Config language | Hot reload (mechanism, source) | Packaging model | Protocol dependency | Works on KWin/Plasma (verified status) | Tray/SNI | KDE theming (Kirigami/Breeze) | Activity (last release) |
|---|---|---|---|---|---|---|---|---|
| **Quickshell** 0.3.2 [1][8] | QML/JS | **y** — file watcher reloads config on save; `QS_DISABLE_FILE_WATCHER` opt-out; reload is a full config reload [1][3][7] | distro-widespread: Arch, Nix, Debian, Gentoo, Guix, **Fedora F44/F45/Rawhide**, COPR `errornointernet/quickshell` [2][10][11] | layer-shell on Wayland (PanelWindow→WlrLayershell); also runs on X11 [6][8] | **Protocol-viable, upstream-unendorsed**: works on any layer-shell compositor incl. KWin (≥5.20-era [17]); project bundles WM wrappers only for Hyprland+i3 [4]; no KDE support statement; generic layer-close crash #910 open [33] | **y** — `Quickshell.Services.SystemTray` (SNI) [5] | **No** — no Kirigami/Breeze types in module list [5]; theming is manual QML colors | **v0.3.2, 2026-10-08**; repo pushed 2026-10-22; 3.2k★ [8][9] |
| **AGS v3** (scaffold CLI for Astal+Gnim) [24] | TypeScript/JSX on GJS (Gnim) | unknown — not advertised in README; community restarts via scripts and re-applies CSS on watch [C: 33] [24] | AUR; COPR `solopasha/hyprland` used for Fedora dep chain (via HyprPanel docs) [29]; Nix flake [24] | layer-shell via Astal (GTK3) [24] | unknown (no KWin statement found; layer-shell present in KWin since 2020 [17]) | unknown (Astal ships tray services per ecosystem usage — unverified) | no (GTK3) [24] | **v3.1.2, 2026-04-08**; repo pushed 2026-04-08; 3.1k★ [9][24] |
| **Astal** (library layer of AGS) [24] | multi-language bindings (Vala/C core; JS/TS, Python, Lua, Rust langs in repo) | n/a (library; host app defines loop) | Nix, language package managers [24] | layer-shell (GTK) [24] | unknown | unknown | no | no tagged releases; commits through 2026-10-19; ~1.0k★ [9][24] |
| **EWW** (elkowar) 0.6.0 [23] | Yuck (Lisp-like) + GTK widgets | **no built-in advertised**; daemon restart is the loop (README/docs silent on watch) [23] | AUR, Nix, cargo; **NOT in Fedora** (verified: no `eww` in F45 repo; rpms/eww 404) [11] | layer-shell via gtk-layer-shell (GTK3) [23] | **Partial, buggy**: open KDE bug "Widgets are always on top in KDE" (#393, open) — i.e. it renders on KWin but stacking is broken, unresolved [33] | no built-in tray module (README widget docs; users shell out) [23] | no | **v0.6.0, 2024-04-21** (repo pushed 2026-07-17 — low release cadence); 12.7k★ [9][23] |
| **Ironbar** 0.19.1 [25] | Corn (Nix-flavored DSL); legacy JSON/TOML/YAML [25] | **y** — built-in hot reload, actively maintained (commit "fix(hot reload): fully reloading for module changes", 2026-11-01) [25] | crates.io, AUR, Nix; **NOT in Fedora** (verified: no match in F45 repo) [11][25] | layer-shell via gtk4-layer-shell [25] | unknown (targets Hyprland/Sway/Niri/wlroots per topics; no KWin statement) [25] | **y** — tray module [25] | no | **v0.19.1, 2026-09-20**; commits 2026-11-02; 1.5k★ [9][25] |
| **Waybar** 0.15.0 (custom modules) [27] | JSON + CSS; `custom/` modules execute scripts | **y** — signals: `SIGUSR2` reloads config/CSS in place, `SIGUSR1` toggle visibility (man page) [28] | **in Fedora F45** (verified locally: `waybar-0.15.0-6.fc45`) + all major distros [11][27] | layer-shell (wlroots-family) [27] | **Not project-endorsed**: README compositor table lists Sway/River/Hyprland/Niri/Mango/DWL/Wayfire — **KWin absent**; no KWin integration modules; behavior on KWin unknown [27] | **y** — Tray (SNI via libappindicator) module [27] | no (GTK3, CSS) | **0.15.0, 2026-02-06**; commits 2026-10-28; 12.1k★ [9][27] |
| **nwg-panel** 0.12.3 [26] | JSON, edited via **built-in GUI config tool** (no hand-editing) [26] | GUI "applies" on save (panel re-reads config); exact latency unknown | **in Fedora** (rpms/nwg-panel exists; local F45 repo check: no match at this moment — repology lists Fedora historically [10]) + Arch/nix [26] | layer-shell (GTK3, nwg-shell stack) [26] | **No** — README scope: "panel for sway and Hyprland Wayland compositors" [26] | **y** — SNI tray module; documents kded6 SNI-watcher conflict on KDE-adjacent sessions (issue #396) [26] | no | **v0.12.3, 2026-10-21**; pushed 2026-10-26; 782★ [9][26] |
| **HyprPanel** (archived) [29] | TypeScript/SCSS (AGS/Astal) | n/a | AUR `ags-hyprpanel-git`, COPR deps | Astal/layer-shell | **No** — Hyprland-only by design; **repo archived 2026-04-27**, successor **Wayle** [29] | y (AGS tray) [29] | no | archived 2026-04-27; 2.2k★ [9][29] |
| **fabric** (Python) 0.0.2 [30] | Python (signal-based; "no polling or bash scripting") | unknown (dev tooling `run-widget.nix` exists) [30] | AUR (PKGBUILD in repo), Nix, pip [30] | GTK3 layer-shell (Wayland) + X11 [30] | unknown (no KWin statement; Ax-Shell & friends target Hyprland) | unknown | no | **v0.0.2, 2026-08-01**; pushed 2026-11-01; 1.4k★ [9][30] |
| **sfwbar** 1.0β17 [31] | Own config format (switched at β17) + taskbar widget language | unknown | **in Fedora** (`dnf install sfwbar`, `sfwbar-1.0~beta16.1-4.fc45` verified locally) + AUR [11][31] | layer-shell via gtk-layer-shell [31] | unknown (taskbar/window-control features depend on foreign-toplevel support; untested on KWin) | **y** — SNI tray [31] | no | **1.0β17, 2026-03-18**; commits 2026-11-02; 441★ [9][31] |
| *(watch)* **Wayle** [29] | TOML (planned), Rust | n/a (pre-release) | none yet | layer-shell, compositor-agnostic by design [29] | stated goal: any layer-shell compositor — unverified (no release) | unknown | no | pre-release [29] |

**Table read-outs.** (1) Quickshell is the only candidate that is simultaneously in this host's own Fedora repo, QML/Qt-native (shares Plasma's UI stack rather than dragging GTK in), SNI-capable, and hot-reloading. (2) Nothing in the set has a Kirigami/Breeze integration story — theming is manual everywhere. (3) Official "works on KWin" endorsements do not exist anywhere in this space; KWin compatibility is protocol-level (layer-shell), proven per-project only by scattered bug reports (EWW #393 renders-but-broken; the rest untested/unknown).

---

## 2. Quickshell ease anatomy — what exactly makes the loop fast

All cites S-tier (Quickshell official docs/site/changelog) unless noted.

**2.1 One file starts the world.** A config = any folder with `shell.qml` under `~/.config/quickshell/`; `qs -c name` or `qs -p /path` runs it. The guided intro builds a working multi-monitor clock bar from one file, in one page [3].

**2.2 Save = apply (watch-reload).** "Quickshell live-reloads your code. You can leave it open and edit the original file. The panel will reload when you save it." [3]; homepage: "loads changes as soon as they're saved, letting you iterate as fast as you can type" [1]. Mechanics and limits: the watcher reloads the **entire config** (state resets; reload-crash classes are a standing fix category in the changelog — loaders mid-load, input masks, sockets [7]); `QS_DISABLE_FILE_WATCHER` env opt-out; a fix specifically for VSCode's atomic-save breaking the watcher [7]. Net: <1s edit→see, no restart, at the cost of process-local state.

**2.3 Errors at the point of edit.** Runtime failures print to the launching terminal with file:line: `WARN scene: **/shell.qml[36:-1]: ReferenceError: clock is not defined` — shown *in the tutorial itself* as part of the learning flow [3].

**2.4 Window ownership = yours.** `PanelWindow` (anchors, `exclusiveZone`, `aboveWindows`, `focusable`, `margins`) maps 1:1 onto layer-shell knobs; `FloatingWindow` for normal windows [6]. There is no host C++ second-guessing your sizes — the exact inverse of Plasma, where the compact cell/popup host ignores half the sizing properties and a size freeze can silently override all hints (fleet-verified: popupWidth/popupHeight keys; four-property sizing law) [F: 21][22].

**2.5 Per-monitor = declarative.** `Variants { model: Quickshell.screens; delegate: Component { PanelWindow { screen: modelData … } } }` — bars materialize/destroy reactively on hotplug [3].

**2.6 Process + system integrations as typed objects.** `Process`/`StdioCollector`/`SplitParser`/`Socket` for shell-out; `IpcHandler` to call into your shell from keybinds [3][4]. Shipped integrations (module list [5]): Hyprland, I3, Bluetooth, Networking, Mpris, Notifications daemon, Pam, Pipewire, Polkit agent, **SystemTray (SNI)**, UPower, Greetd, DBusMenu, Widgets, Wayland, WindowManager. FAQ is explicit about scope: WM interfaces bundle **Hyprland and i3 only**; other WMs = roll your own over Socket/Process [4].

**2.7 Docs are examples-first and version-pinned.** Versioned docs (`/docs/v0.3.2/…`) where every symbol in examples is a hyperlink to its typed reference page; guided intro; FAQ keyed to failure modes; an official examples repo (`quickshell-examples`) and a homepage gallery of user configs each with an install link [1][3]. Docs carry an honest breaking-changes policy (pre-1.0 breaks + migration guides) [4].

**2.8 Editor tooling is a first-class doc page.** Per-editor LSP setup (Emacs/Neovim/Helix/VSCode) around Qt's `qmlls`; Quickshell **generates a managed `.qmlls.ini`** next to `shell.qml` so the language server sees the shell's types; known caveats listed straight-faced (no docs for Quickshell types in LSP; `PanelWindow` unresolvable) [2].

**2.9 Install is one package.** See premise correction §0.1 — including on this exact host (F45 repo + COPR) [2][10][11].

**Loop math:** edit → autosave → watcher reload (<1s) → error or visual result in the same terminal/desktop you're already looking at. No install step, no restart, no journal archaeology for the happy path.

---

## 3. Hyprland ease anatomy — hyprpm, template, config loop, and the honest limits

All cites S-tier (Hyprland wiki current `wiki.hypr.land`, versioned archive, official repos) unless noted.

**3.1 hyprpm automates the whole plugin supply chain.** `hyprpm add <git-url>` clones, builds against the *installed* Hyprland's headers (deps: `cpio cmake git meson gcc`, plus `-dev` packages on Fedora/Debian), `hyprpm enable/disable <name>`, `hyprpm reload` injects into the running session, `hyprpm update` refreshes; `exec-once = hyprpm reload -n` restores at login; failures notify [12][13]. Version-safety is automated upstream too: the official plugins repo ships `hyprpm.toml` pins — "hyprpm automatically detects your hyprland version & installs only the corresponding 'pinned' release" [16]. Permission manager integration exists (`hl.permission(... "plugin", "allow")`) [12].

**3.2 The ABI wall is real, and it's fenced exactly where it bites.** Plugins are C++ shared objects loaded **into the compositor process** ("(almost) full access to every part of Hyprland's internal process") [14]. Every plugin embeds `HYPRLAND_API_VERSION` and must refuse to load when `__hyprland_api_get_hash() != GIT_COMMIT_HASH` — the wiki's own boilerplate does the check and warns it "will prevent random crashes coming from mismatched header versions" [14]. Nix users get the same guarantee declaratively (`inputs.hyprland.follows`) [16]. So: no stable plugin ABI — every Hyprland upgrade rebuilds plugins — but the toolchain (hyprpm) absorbs it, and the guard converts silent segfaults into a clean notification.

**3.3 The "template repo" premise needs a correction.** `hyprland/hyprland-plugin-template` does not exist (404); the real template lives at **hyprland-community/hyprland-plugin-template** — 17★, last pushed **2023-05-08** (stale) [32]. The wiki's actual on-ramp is "read `PluginAPI.hpp` (commented) + copy a small plugin from hyprwm/hyprland-plugins (`csgo-vulkan-fix`, `hyprwinwrap`)" [14][16]. Entry is a ~40-line boilerplate: `PLUGIN_API_VERSION`, `PLUGIN_INIT` (register config vars/hooks here), `PLUGIN_EXIT`, HASH guard [14].

**3.4 Config loop is instant by construction.** `~/.config/hypr/hyprland.conf` (hyprlang): "The config is reloaded **the moment you save it**. However, you can use `hyprctl reload`" [15]. Syntax errors surface as an on-screen error bar (the wiki's `noerror` escape-hatch exists specifically because of it) [15]. Current Hyprland additionally exposes a **Lua API** for config-time scripting (`hl.plugin.load`, `hl.config`, `hl.on("hyprland.start", …)`) [12] — config-as-program without plugins.

**3.5 Safe iteration is a documented mode.** `make debug` + run the nested `./build/Hyprland` *inside* your session → "run your plugin in the nested session without worrying about nuking your actual session" [14].

**3.6 What Hyprland plugins CANNOT do (the honest contrast).** They are compositor-internal C++: great at dispatchers, layouts, decorations, hooks, window rules — **no widget/UI toolkit, no panel system, no theme engine**. Bars/trays/launchers on Hyprland are exactly what Quickshell/AGS exist to fill (Hyprland's own wiki disclaims default plugins entirely [12]). Stability is best-effort: "Hyprland employs a few tactics to unload plugins that crash. However, those tactics may not always work" [12]. And the wiki's security posture is blunt: "Writing a plugin to wipe your computer is easy" — trust is manual [12]. Plasmoids invert every one of these: sandboxed-ish declarative QML, cannot crash the shell process from a widget, but also cannot touch compositor internals without graduating to a compiled KWin effect/script C++ plugin (full Frameworks build; a *higher* barrier than a Hyprland plugin, since there is no hyprpm equivalent and no per-commit ABI guard).

---

## 4. The ease vectors (core deliverable) — 12 named vectors, evidence → KDE equivalent today → close-the-gap call

Legend per vector: **Evidence** (Quickshell/Hyprland, source+tier) · **KDE today** (may be "none — genuine gap") · **Close it** (build / buy / skip + rough cost).

**V1 — Zero-build artifact (the files are the package).**
Evidence: QS config = a folder + `shell.qml`, run directly [S:3]; Hyprland config is text executed on save [S:15]. KDE today: **parity for pure-QML plasmoids** — no compile; but "the package" is a directory contract (`metadata.json` + `contents/ui/main.qml` + optional `contents/config/main.xml`) + `kpackagetool6 -t Plasma/Applet -i` [S:19][F:21]. Close it: **build (trivial)** — a `plasma-new` scaffolder emitting the tree; the compile-free property is already true.

**V2 — Sub-second save→see loop (watch-reload).**
Evidence: QS live-reload on save [S:1][3]; Hyprland "reloaded the moment you save it" [S:15]. KDE today: **genuine gap for the live shell.** Official paths are `plasmoidviewer` (separate window, needs `plasma-sdk`), `plasmawindowed`, or install + `plasmashell --replace`, which the docs themselves call slow ("takes a few seconds for the panel to load") [S:20]. The fleet already proved a better live path: `kpackagetool6 -u` + remove/re-add the widget instance via `evaluateScript` → new QML loads with **zero shell restart** [F:21]. Close it: **build (1 day)** — wrap that pattern + inotify into a `plasma-watch` tool in bazzite-customizations; delete/re-add churn is acceptable for dev, and installers still never restart the shell [F:21].

**V3 — Single-file / single-tree source of truth.**
Evidence: `shell.qml` is the whole config [S:3]; hyprland.conf single file [S:15]. KDE today: **near-gap** — mandatory two-file minimum (metadata.json + main.qml), which is *also* the minimum viable plasmoid [S:19][F:21]. Close it: **build (trivial)** — same scaffolder as V1; git-track the source dir and treat `~/.local/share/plasma/plasmoids/` as build output. Fleet rule already forbids pointing `-u` at the install dir (self-destructing install) [F:21].

**V4 — Errors at the point of edit (terminal, file:line).**
Evidence: QS prints `WARN scene: **/shell.qml[36:-1]: ReferenceError…` to the launching terminal, taught *in the intro* [S:3]; Hyprland shows an on-screen error bar for config errors [S:15]. KDE today: **half-parity.** Runtime QML errors *do* carry file:line, but in `journalctl --user` (categorized logging hides `console.log` unless `qml.debug=true` is enabled [S:20][F:21]); fatal applet loads surface as `error when loading applet … Type X unavailable` with the true file:line in the LAST line of the chain [F:21]. Close it: **build (small)** — the harness already captures this; extend `plasma-watch` to tail + filter the journal by plugin id and surface errors next to the editor.

**V5 — One-command, dependency-and-ABI-aware plugin manager.**
Evidence: hyprpm add/enable/reload/update with header install, version-pinned plugin releases, and startup restore [S:12][13][16]. KDE today: **genuine gap (CLI-first)** — `kpackagetool6` is path-manual with no resolver/build; GUI equivalents exist (System Settings → KWin Scripts; Add Widgets → Get New…) but are store-browsing, not source-management. Mitigant: pure-QML plasmoids need no build step, so there is less for a manager to do. Close it: **build (medium)** — a `plasma-pm` wrapping kpackagetool6 + git clone + (for the rare C++ widget) cmake; or **skip** and lean on V7's store flow.

**V6 — Reversible uninstall symmetry.**
Evidence: `hyprpm remove/disable` [S:12]; QS = delete the folder. KDE today: **parity** — `kpackagetool6 -r`, plus GUI uninstall of widgets/scripts; user-level location (`~/.local/share/plasma/plasmoids`) makes everything non-destructive on an ostree host [F:21]. Close it: **skip** (nothing to close).

**V7 — Copy-paste / one-click adoption culture.**
Evidence: QS homepage gallery of full configs with install links [S:1]; awesome-hyprland + hypr.land/plugins as canonical lists [S:12]. KDE today: **KDE wins this one** — store.kde.org + "Get New [Widgets/Scripts]" (GHNS) is one-click install *from the running desktop*, which neither Hyprland nor Quickshell has (their equivalent is `git clone` + copy dotfiles) [S: 19; GHNS flow per KDE widget tutorial ecosystem]. Close it: **skip** — but note asymmetry: GHNS covers users, not developers; the *developer* snippet culture (drop-in examples) is thinner on the KDE side (develop.kde.org examples page exists [S:19]).

**V8 — Config-as-data: schema generates the settings UI.**
Evidence (inverse direction): nwg-panel ships a GUI config editor so users never hand-edit JSON [S:26]; Hyprland plugins register config vars in `PLUGIN_INIT` and they become hyprlang keywords [S:14]. KDE today: **KDE wins** — KConfigXT `contents/config/main.xml` declaratively generates the widget's config dialog; optional `config.qml` for layout [S:19][F:21]. Quickshell has *no* config-UI concept (your config is the program). Close it: **skip** (KDE advantage; keep in any hybrid design).

**V9 — Typed system-integration objects (services as singletons).**
Evidence: QS modules: SystemTray(SNI), Mpris, Pipewire, UPower, Notifications, Polkit, Bluetooth, Networking, DBusMenu [S:5]. KDE today: **partial** — Plasma QML API (PlasmaCore, dataengines, `plasma5support` DataSource for executables) covers similar ground but is aging: the executable dataengine now lives in `org.kde.plasma.plasma5support` with import traps, and applets cannot spawn processes directly (route through dataengine or an API) [F:21][22][S:19]. Close it: **buy** (nothing to install — pattern already proven in fleet widgets) + **build (small)**: a shared `FleetServices.js`/QML singleton library wrapping the probes we already run, making ports one-liners.

**V10 — Per-monitor declarative compositing.**
Evidence: QS `Variants { model: Quickshell.screens }` [S:3]. KDE today: **parity-ish but imperative** — panels per monitor via UI or `evaluateScript` (`panelById`, `addWidget`), with known traps (widget widths unreliable from script; index pinning after recreate) [F:21]. Close it: **skip** for panels Plasma already owns; **build (small)** only if companion-chrome (§5) becomes real — Quickshell brings V10 with it for free.

**V11 — Editor tooling wired to the framework (LSP).**
Evidence: QS documents per-editor `qmlls` setup and *generates* `.qmlls.ini` so the LSP resolves shell types [S:2]; AGS world uses TypeScript (tsc/LSP for free) [S:24]. KDE today: **partial gap** — Qt's qmlls exists, but nothing wires plasmoid context (Plasmoid attached object, plasma imports, install dir) into it; Qt Creator templates exist but are heavyweight. Close it: **build (small)** — a fleet doc + `.qmlls.ini` recipe pointing QML import paths at installed plasmoids (`/usr/share/plasma/plasmoids/` as the type source, mirroring QS's approach).

**V12 — Sandbox-safe nested iteration.**
Evidence: Hyprland `make debug` nested session is a documented dev mode [S:14]; QS is a separate process — crash = your bar dies, shell lives. KDE today: **exists but DIY** — `plasmoidviewer`/`plasmawindowed` (isolated window incl. `-l topedge -f horizontal` panel emulation, `QT_SCALE_FACTOR` DPR testing [S:20]) and the fleet's virtual harness (nested `kwin_wayland` + fresh-HOME plasmashell) which is the only reliable popup-verification path [F:21]. Close it: **build (done, package it)** — the harness is written; wrap as `plasma-harness` one-command for parity with `make debug`.

**Vector scorecard:** KDE parity today: V1, V6, V7(user-side), V8, V10(imperative), V12(DIY). Genuine gaps: **V2 (hot reload), V5 (plugin manager CLI), V11 (LSP wiring)**, plus the developer-side half of V7. Closable by the fleet in ≤1 day each: V1+V3 (scaffolder), V2 (watch wrapper), V4 (journal tailer), V9 (services lib), V11 (qmlls recipe), V12 (harness packaging). Nothing requires waiting on upstream KDE.

---

## 5. The bridge question — can Quickshell/AGS/EWW-class apps run ON Plasma today?

**Protocol verdict: yes — and much older than commonly assumed.** KWin's `zwlr_layer_shell_v1` implementation landed 2020-09-03 (commit `f8dd1c615…`, "Implement layer-shell v1 protocol", Vlad Zahorodnii) [S:17] — Plasma 5.20-era. It has been continuously hardened since: keyboard-interactivity fixes (!4578 "Fix none keyboard interactivity in LayerShellV1Window", !4579 "Implement dockWantsInput", 2023-11) [S:18], close-on-output-removal (!6749, 2024-11), popup integration tests (!9046, 2026-04), critical-notification layer scoping (!9610, 2026-07), and reserved-space precedence work ("Make horizontal panels take precedence in reserved space", !7721, 2025-06) [S:18]. On this host (kwin 6.8.2) all of that is present. Exclusive zones work (struts — per-virtual-desktop struts were *removed* in !8786 as cleanup, 2026-03) [S:18]; keyboard interactivity works post-!4578.

**Quickshell-on-Plasma specifically:** no upstream KDE endorsement or test target exists — the docs bundle WM integrations for Hyprland and i3 only and say "for any other WM … roll your own" [S:4]; PanelWindow requires a layer-shell compositor [S:6], which KWin is. So a Quickshell bar attaches on Plasma 6 at the *protocol* level; there is no official support statement either way (gap, flagged). Community signal is thin: a generic layer-surface-close SIGSEGV (#910, open) is the closest tracker evidence, not KDE-specific [C:33].

**What actually breaks / degrades if you run it as companion chrome on Plasma 6.8:**
1. **WM features are dead weight.** No Hyprland/i3 IPC on KWin → taskbar, workspaces, window-list widgets are unusable; `Quickshell.WindowManager`'s coverage on KWin: unknown. Companion chrome must be content-only (clocks, sensors, media, notifications-ish).
2. **Theme mismatch.** No Kirigami/Breeze binding (no such module ships [S:5]; changelog grep finds none [S:7]). A Quickshell bar will not follow the Plasma color scheme/rounding; you hand-sync QML colors. GTK-based alternatives (Waybar/EWW/AGS) are worse fits stylistically *and* drag a second toolkit in.
3. **SNI tray collision risk.** Plasma registers its own StatusNotifierWatcher/host. Quickshell's `Services.SystemTray` implements a tray too [S:5]; nwg-panel documents the kded6-owned-watcher conflict class explicitly (#396) [S:26]. Expect duplicate-or-missing icons unless Plasma's tray is left as the sole host — companion chrome should skip tray duty.
4. **Reserved-space negotiation.** KWin arbitrates struts from both Plasma panels and layer-shell surfaces (incl. horizontal-panel precedence rules !7721 [S:18]) — workable, but edge-stacking a Quickshell bar on an edge Plasma already occupies is the first thing to test; keep it on a free edge/surface.
5. **Error surface asymmetry.** QS errors go to its terminal (V4) — actually *better* than plasmoid-journal debugging; but its reload-crash classes [S:7] are its own risk.

**Kirigami/Breeze integration story: none found** — no Quickshell release notes, modules, or docs mention Kirigami or Breeze (greps over changelog + module listing [S:5][S:7]). Since Quickshell is QtQuick, hand-rolling colors against the Plasma theme file is possible but unverified.

**Verdict:** Quickshell as *companion* chrome (secondary HUD/bar on a free edge) on Plasma 6.8: **viable today, protocol-proven, upstream-unendorsed, theming-manual** — a reasonable experiment now that `rpm-ostree install quickshell` is one command on this host [11]. Quickshell as *replacement* for the Plasma panel/launcher: **no** — loses V8/V7/KRunner/native tray, adds collision surface; the prior session's Foyer conclusion stands.

---

## 6. Recommendation matrix (build / buy / skip)

| Move | Call | Why / cost |
|---|---|---|
| `plasma-watch` (inotify + `kpackagetool6 -u` + evaluateScript remove/re-add) | **build, ~1 day** | Closes V2/V4 — the single biggest felt-difficulty vector. Pattern already fleet-proven [F:21]. |
| `plasma-new` scaffolder (metadata.json + main.qml + config/main.xml stub) | **build, hours** | Closes V1/V3 developer-side. |
| `FleetServices` QML singleton lib (probe/SNI/Mpris wrappers) | **build, small** | Closes V9; makes Omarchy ports one-liners [F:21][22]. |
| qmlls recipe (`.qmlls.ini` + import paths to installed plasmoids) | **build, hours** | Closes V11 using Quickshell's own technique [S:2]. |
| Package virtual harness as `plasma-harness` | **build (exists)** | Closes V12 for contributors [F:21]. |
| Quickshell via `rpm-ostree install quickshell` for companion-chrome experiments | **buy — now zero-cost** | In F45 repos [11]; COPR if 0.3.2 needed [2]. |
| `plasma-pm` hyprpm-equivalent CLI | **skip (for now)** | V5 gap is real but small for pure-QML widgets; revisit if C++ widgets enter the fleet. |
| Porting launchers/panels off Plasma to Quickshell | **skip** | §5 verdict; KRunner/GHNS/KConfigXT losses outweigh [prior-session premise, upheld]. |

---

## Sources

Tier: S = official docs/source/direct API probe · A = official-adjacent (wiki archive versions, vendor repos) · C = community/issues · F = fleet-verified local knowledge. All GitHub metadata (releases/push dates/stars) via GitHub REST API snapshot 2026-11-04 [9].

1. [S] Quickshell homepage (features: live reload, QML+LSP, gallery, 0.3.2 announcement 2026-10-08) — https://quickshell.outfoxxed.me/
2. [S] Quickshell Installation & Setup (distro matrix incl. Fedora Rawhide + COPR errornointernet; qmlls/.qmlls.ini, editor configs) — https://quickshell.outfoxxed.me/docs/v0.3.2/guide/install-setup
3. [S] Quickshell guided introduction (shell.qml discovery, live-reload note, file:line WARN example, Variants per-monitor, Process/StdioCollector) — https://quickshell.outfoxxed.me/docs/v0.3.2/guide/introduction
4. [S] Quickshell FAQ (WM wrappers "Hyprland and i3" only; breaking-changes policy) — https://quickshell.outfoxxed.me/docs/v0.3.2/guide/faq
5. [S] Quickshell module listing (SystemTray, Mpris, Pipewire, UPower, Hyprland, I3, DBusMenu…; no Kirigami) — https://quickshell.outfoxxed.me/docs/v0.3.2/types
6. [S] Quickshell PanelWindow reference (anchors/exclusiveZone/aboveWindows ↔ WlrLayershell) — https://quickshell.outfoxxed.me/docs/v0.3.2/types/Quickshell/PanelWindow
7. [S] Quickshell changelog (QS_DISABLE_FILE_WATCHER; reload/watcher fix classes; no Kirigami mentions) — https://quickshell.outfoxxed.me/changelog
8. [S] Quickshell repo (GitHub mirror; primary git.outfoxxed.me; "for Wayland and X11"; 3.2k★) — https://github.com/quickshell-mirror/quickshell
9. [S] GitHub REST API repo/release snapshot 2026-11-04 (stars, pushed_at, latest release per repo: quickshell v0.3.2 2026-10-08; eww v0.6.0 2024-04-21; ags v3.1.2 2026-04-08; ironbar v0.19.1 2026-09-20; nwg-panel v0.12.3 2026-10-21; waybar 0.15.0 2026-02-06; fabric v0.0.2 2026-08-01; sfwbar 1.0β17 2026-03-18; Hyprland v0.57.1 2026-11-03) — https://api.github.com/repos/{owner}/{repo}/releases/latest
10. [S] Repology: quickshell packaging matrix (fedora_44 0.2.1^git, rawhide, arch, nix, debian…) — https://repology.org/api/v1/project/quickshell
11. [S] Local host probe 2026-11-04 (Bazzite stable, F45 base, kwin-6.8.2): `dnf list --available` → quickshell 0.2.1^git20260209-5.fc45, waybar 0.15.0-6.fc45, sfwbar 1.0~beta16.1-4.fc45; no eww/ironbar/nwg-panel — (fleet machine gdtower, command output retained in task log)
12. [S] Hyprland wiki (current, "Last updated November 3, 2026"): Using plugins (hyprpm workflow, deps, permission mgr, Lua hl.* API, plugin discovery) — https://wiki.hypr.land/hyprland-plugins/using-plugins/
13. [A] Hyprland wiki 0.44.0 archive: Using plugins (exec-once = hyprpm reload -n; manual hyprctl plugin load/unload) — https://wiki.hyprland.org/0.44.0/Plugins/Using-Plugins/
14. [S/A] Hyprland wiki 0.44.0: Plugin development — Getting started (PluginAPI.hpp, PLUGIN_API_VERSION, HASH≠GIT_COMMIT_HASH guard, nested `make debug` session) — https://wiki.hyprland.org/0.44.0/Plugins/Development/Getting-Started/
15. [S/A] Hyprland wiki 0.44.0: Configuring Hyprland ("The config is reloaded the moment you save it"; error-bar/noerror) — https://wiki.hyprland.org/0.44.0/Configuring/Configuring-Hyprland/
16. [S] hyprwm/hyprland-plugins (official plugins; hyprpm.toml version pinning; Nix follows-guard) — https://github.com/hyprwm/hyprland-plugins
17. [S] KWin commit: "Implement layer-shell v1 protocol", Vlad Zahorodnii, 2020-09-03 — https://invent.kde.org/plasma/kwin/-/commit/f8dd1c615b661660e25be0f92adbdda28da07b8e
18. [S] KWin merge requests (GitLab API, merged, 2023–2026): !4578 keyboard interactivity, !4579 dockWantsInput, !6749 close-on-output-removal, !7721 horizontal-panel reserved-space precedence, !8786 drop per-VDS struts, !9046 layer-shell popup integration tests, !9610 critical-notification layer scope — https://invent.kde.org/plasma/kwin/-/merge_requests/4578 · /4579 · /6749 · /7721 · /8786 · /9046 · /9610
19. [S] KDE Plasma Widget tutorial (package structure, fork-a-shipped-widget, KConfigXT, plasmawindowed, examples page) — https://develop.kde.org/docs/plasma/widget/
20. [S] KDE Plasma Widget testing (plasmoidviewer/-a, --location/--formfactor, QT_SCALE_FACTOR, qml.debug logging rule, `plasmashell --replace` "takes a few seconds") — https://develop.kde.org/docs/plasma/widget/testing/
21. [F] Fleet skill `plasma-plasmoid-development` v1.7.1 (verified on Plasma 6.7.5/Bazzite): kpackagetool6 deploy/upgrade loop, evaluateScript remove/re-add live reload, journal error patterns, popupWidth/Height freeze, sizing laws, plasma5support dataengine, unit-restart ban — ~/.hermes/skills/devops/plasma-plasmoid-development/SKILL.md
22. [F] Fleet skill `omarchy-plugin-porting` v1.0.0 (Quickshell window-ownership vs Plasma embedded-cell differential; "Plasma QML cannot spawn processes" — route via API/dataengine) — ~/.hermes/skills/devops/omarchy-plugin-porting/SKILL.md
23. [S] EWW repo README (Yuck/GTK3, Rust, docs site, examples; 12.7k★) — https://github.com/elkowar/eww
24. [S] AGS v3 repo (scaffold for Astal+Gnim; GJS/TS/JSX; layer-shell topic) and Astal repo (Vala/C libs, lang bindings) — https://github.com/aylur/ags · https://github.com/aylur/astal
25. [S] Ironbar repo (Corn config, tray module, hot-reload commits incl. ab6e96a 2026-11-01 "fix(hot reload): fully reloading for module changes") — https://github.com/JakeStanger/ironbar
26. [S] nwg-panel repo (GTK3 sway/Hyprland scope, GUI config tool, SNI tray, kded6 conflict #396) — https://github.com/nwg-piotr/nwg-panel
27. [S] Waybar repo (compositor integration table — KWin absent; Tray module; wlroots framing) — https://github.com/Alexays/Waybar
28. [S] waybar(5) man page (SIGUSR1/SIGUSR2 reload/visibility) — https://man.archlinux.org/man/waybar.5
29. [S] HyprPanel archive notice + Wayle successor (archived 2026-04-27; Wayle = Rust, compositor-agnostic via layer-shell, TOML) — https://github.com/Jas-SinghFSU/HyprPanel
30. [S] fabric repo (Python widgets, signal-based, X11+Wayland) — https://github.com/Fabric-Development/fabric
31. [S] sfwbar repo (features incl. SNI tray; Fedora/AUR packages; β17 config change) — https://github.com/LBCrion/sfwbar
32. [S] hyprland-community/hyprland-plugin-template (17★, pushed 2023-05-08 — stale; the `hyprland/…` path 404s) — https://github.com/hyprland-community/hyprland-plugin-template
33. [C] Issue trackers: quickshell #910 (WlrLayershell SIGSEGV on compositor-initiated close, open) — https://github.com/quickshell-mirror/quickshell/issues/910 · eww #393 ("Widgets are always on top in KDE", open) — https://github.com/elkowar/eww/issues/393 · waybar #961/#3126 (SIGUSR2 reload usage) — https://github.com/Alexays/Waybar/issues/3126
34. [S] Fedora package page for quickshell — https://packages.fedoraproject.org/pkgs/quickshell/quickshell/
35. [S] COPR errornointernet/quickshell — https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell

**Unverified / flagged:** AGS/Astal hot-reload behavior (V-table cell `unknown`); Astal tray on KWin; fabric/sfwbar reload mechanisms; Quickshell `WindowManager` module's KWin coverage; KRunner-from-Quickshell DBus shell-out (§0.3). These are marked `unknown` in the table rather than guessed.
