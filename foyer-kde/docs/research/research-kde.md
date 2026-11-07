# Foyer for KDE — Research Digest: implementation surface + precedent digest

- Date: 2026-11-07 (CST). Lane: research-only subagent (no design decisions).
- Target host: GDTower-class Bazzite box (Fedora-atomic, KDE Plasma 6.x, Qt6, KWin/Wayland, user gdtower/gdeyoung).
- Facts marked **HOST-VERIFIED** were probed by shell command on this host (probe log in §1.0).
- Facts marked **UNVERIFIED** come from docs/web and were not runtime-confirmed here.
- STATUS: COMPLETE v1.0 (2026-11-07) — all sections filled; open spike items listed in §4.

## 0. TL;DR
**Build Foyer as a standalone Qt6/QML daemon (Option A) whose window is a `wl_layer_shell` surface via LayerShellQt** — runtime lib, QML module `org.kde.layershell`, and Qt wayland shell-integration plugin are all already installed on this host; license is LGPL (+MIT/BSD parts) — fine. Blur via `KWindowEffects::enableBlurBehind()` (the exact call `PlasmaCore.Dialog` itself uses, source-verified). Daemon warm-started by a `Type=dbus` systemd user unit mirroring `plasma-krunner.service` (host-verified pattern) → sub-150 ms open is realistic. Global shortcut via a `.desktop` + kglobalaccel `[services]` registration — the fleet already does exactly this (`hermes-ask.desktop` → Meta+H on this host). Skip PlasmaCore.Dialog (plasmoid) and plain windows (Wayland can't self-position; krunner itself uses the `QT_WAYLAND_DISABLE_FIXED_POSITIONS` hack). Full reasoning in §1.D. Big white-space finding: **no active KDE-native (Kirigami/layer-shell) modern launcher exists** — Albert/Ulauncher are Qt/GTK outsiders; the niche is open.

## 1. PART 1 — Implementation surface

### 1.0 Host probe log (all HOST-VERIFIED, run 2026-11-07 on gdtower/gdeyoung)
- OS: Bazzite 45.20261104 (Kinoite, VARIANT_ID=bazzite-dx-nvidia) — rpm-ostree atomic. Session: KDE / Wayland (`plasma.desktop`).
- **Plasma 6.8.2 / KWin 6.8.2** (`plasmashell --version`, `kwin_wayland --version`). NOTE: brief said 6.7.5; actual is 6.8.2. Qt 6.11.2 (qtwayland, qtdeclarative).
- `layer-shell-qt-6.8.2-1.fc45.x86_64` installed. Ships: `libLayerShellQtInterface.so.6`, Qt plugin `/usr/lib64/qt6/plugins/wayland-shell-integration/liblayer-shell.so`, QML module `/usr/lib64/qt6/qml/org/kde/layershell/` (qmldir: `module org.kde.layershell`, plugin `LayerShellQtQml`). **`layer-shell-qt-devel` NOT installed** (build gap; same for `kf6-kirigami-devel`, `kf6-kglobalaccel-devel`, `kf6-kwindowsystem-devel`).
- QML types on disk under `/usr/lib64/qt6/qml/org/kde/`: `layershell`, `kirigami` (kf6-kirigami 6.31.0), `breeze` (qqc2-breeze-style 6.8.2 — QQC2 style dir with ApplicationWindow.qml, BreezeStyle.qmltypes…), `plasma` (core etc., owned by `libplasma-6.8.2` rpm), `milou` (ResultsView.qml, ResultDelegate.qml), `kwindowsystem`, `qqc2desktopstyle`, `ksvg`.
- `kf6-kwindowsystem-6.31.0` **is** installed (earlier probe used a wrong plural name).
- KRunner runtime facts: `/usr/share/dbus-1/services/org.kde.krunner.service` = `Exec=/usr/bin/krunner --daemon`, `SystemdService=plasma-krunner.service`; `/usr/lib/systemd/user/plasma-krunner.service` = `Type=dbus`, `BusName=org.kde.krunner`, `PartOf=graphical-session.target`, `Restart=no`, `Slice=background.slice`; krunner daemon running under `user@1000.service` (busctl).
- kglobalaccel: D-Bus name `org.kde.kglobalaccel` owned by **kwin_wayland** (PID 7510) on this host — in Plasma 6.8 kglobalaccel runs inside KWin, not as a standalone daemon.
- kglobalaccel `[services]` precedent on this host: `~/.config/kglobalshortcutsrc` contains `[services][hermes-ask.desktop]` `_launch=Meta+H`; the desktop file (`~/.local/share/applications/hermes-ask.desktop`) has `Exec=busctl --user call org.kde.krunner /App org.kde.krunner.App query s "ai "` — i.e. the fleet already binds Meta+H to a desktop-file whose Exec pokes KRunner over D-Bus.
- Theming data on host: `~/.config/kdeglobals` embeds full color groups (`[Colors:Button] DecorationFocus=52,108,146`, `[Colors:Complementary] DecorationFocus=30,146,255` …) plus `[General] ColorSchemeHash=…`; `~/.config/kdedefaults/kdeglobals` says `[General] ColorScheme=Vapor`, theme `com.valve.vapor.desktop` — **Bazzite runs Valve's Vapor scheme, not stock Breeze**. No `AccentColor=` key present (scheme-embedded colors instead).
- KRunner 15-row cap, on disk: `/usr/lib64/qt6/qml/org/kde/milou/ResultsView.qml` line 53: `limit: 15` (the component exposes `property alias limit: resultModel.limit` — so any *re-user* of Milou can raise it; the stock KRunner instance doesn't).
- `ldd`: both `plasmashell` and `krunner` link `libLayerShellQtInterface` (plasma-workspace hard-requires it per `rpm -q --requires`).
- KWin blur effect: `kreadconfig6 kwinrc Plugins blurEnabled` empty → default (on).
- KRunner sources fetched to `src/` in this scratch dir: `krunner-main.cpp`, libplasma `dialog.cpp` (55 KB), layer-shell-qt `window.h`, kwindowsystem wayland `windoweffects.cpp`.

### 1.A Standalone Qt6/QML window via LayerShellQt — the real deal
- **What it is**: Qt wrapper over `zwlr_layer_shell_v1` (README: "applications to easily use … wlr-layer-shell"; repo https://github.com/KDE/layer-shell-qt / https://invent.kde.org/plasma/layer-shell-qt). Usage per README: `find_package(LayerShellQt REQUIRED)` → link `LayerShellQt::Interface`; call `LayerShellQt::Shell::useLayerShell()` **before any QWindow is created**; then `LayerShellQt::Window::get(win)` to configure per-surface settings. (Fetched from README.)
- **API surface** (fetched `src/interfaces/window.h` @ master, mirrored in local `src/window.h`): `setAnchors(Anchors)` — `AnchorTop|Bottom|Left|Right` flags; `setMargins(QMargins)`; `setExclusiveZone(int)` / `setExclusiveEdge(Anchor)`; `setLayer(Layer)` — `LayerBackground=0, LayerBottom=1, LayerTop=2, LayerOverlay=3`; `setKeyboardInteractivity(KeyboardInteractivity)` — `None / Exclusive / OnDemand`; `ScreenConfiguration` (use compositor's output or specific screen); `closeOnDismissed()`.
- **QML availability HOST-VERIFIED**: qmltypes in the installed module export `org.kde.layershell/Window 1.0` as an **attached type** (`isCreatable: false`, `attachedType: LayerShellQt::Window`) with the Anchor/Layer enums — so a plain `Window { }` in QML can be configured via the attached object, no C++ subclass needed (C++ path remains the documented one).
- **Which layer for Foyer**: `LayerTop` (same band Plasma uses for its own surfaces above normal windows; panels sit in Bottom/Top; `LayerOverlay` would stack above panels — appropriate only if we want to out-rank notification/popoup zones). Recommendation: **LayerTop**, matching how launchers behave (above apps, below OSD/lock).
- **How KRunner & Plasma dialogs actually do it**: KRunner (standalone binary) renders into a **PlasmaCore.Dialog**, NOT a layer surface — source-verified: `libplasma/src/plasmaquick/dialog.cpp` (fetched, grep for `LayerShell` = 0 hits) contains no layer-shell code, and krunner's own `main.cpp` (fetched) still carries `qputenv("QT_WAYLAND_DISABLE_FIXED_POSITIONS", {})` "to fake window position so Plasma Dialog sets correct borders" plus the comment *"Consider re-enabling when QT_WAYLAND_RECONNECT … when layer-shell support lands"*. Plasma's **panels** do use layer-shell (plasma-workspace requires `libLayerShellQtInterface.so.6`, plasmashell links it — HOST). So Foyer would do for the search window what plasmashell does for panels — an intentional upgrade over KRunner's dialog hack.
- **No taskbar entry**: inherent — layer surfaces are not `xdg_toplevel`s, so they never appear in taskbar/pager/alt-tab. (Semantics per layer-shell protocol; explainer linked from the README: https://drewdevault.com/2018/07/29/Wayland-shells.html.)
- **Licensing HOST-VERIFIED**: `/usr/share/licenses/layer-shell-qt/` = LGPL-2.1-only, LGPL-3.0-only, **LGPL-3.0-or-later**, MIT, BSD-3-Clause, CC0-1.0 (REUSE-layout repo). LGPL ⇒ linkable from any license, incl. closed. OK.
- **Centering caveat (real protocol constraint)**: layer-shell has anchors+margins, no "center" anchor. Two recipes: (a) anchor `Top|Left|Right` + topMargin ≈ 20–25% screen height (KRunner-ish band), or (b) unanchored floating + compute margin from output size (`QScreen` geometry available before commit). Both work; needs a one-shot geometry settle before first frame to avoid visible reposition.
- **Keyboard model**: `OnDemand` + `requestActivate()` is the polite default; `Exclusive` = compositor-granted keyboard grab (nothing else receives keys while open — the "Spotlight grab"). Recommend OnDemand default, Exclusive as a setting; Esc/escape handling is in-app either way.
- **Blur**: `KWindowEffects::enableBlurBehind(QWindow*, enable, region)` — API: https://api.kde.org/kwindoweffects.html ("Instructs the window manager to blur the background … Passing a null region enables for the whole window"). On Wayland this is implemented by KWindowSystem via the **`org_kde_kwin_blur_manager` protocol** — source-verified in `kwindowsystem/src/platforms/wayland/windoweffects.cpp` (fetched; instantiates `BlurManager`/`org_kde_kwin_blur` client extensions). Protocol reference: https://wayland.app/protocols/kde-blur (LGPL-2.1+). And **PlasmaCore.Dialog itself blurs via the same call**: `dialog.cpp` lines 222/238 — `KWindowEffects::enableBlurBehind(q, theme.blurBehindEnabled(), mask)` gated on the Plasma theme's `blurBehindEnabled`. ⚠️ VERIFY IN SPIKE: that KWin applies the blur to a *layer-shell* surface identically (client side is shell-agnostic; expect yes, but no runtime test on this host yet).
- **Build gap on this host (Bazzite/ostree)**: `layer-shell-qt-devel` + KF6 devels absent → either `rpm-ostree install` layering, or build in a toolbox/devcontainer and deploy binaries, or Flatpak (caveat: sandbox complicates kglobalaccel + session integration).

### 1.B Plasmoid popup via PlasmaCore.Dialog (the Kickoff path)
- What you get for free: Plasma theme integration (ColorScope), blur (see §1.A — `enableBlurBehind` is done *for* you, theme-gated), shadows/borders (`syncBorders`, `updateTheme()` in dialog.cpp), popup placement + margins from edges, focus-loss dismissal, and no taskbar entry (bypass-window flags).
- HOST evidence it's the native path: `org.kde.plasma.core` QML plugin present (rpm: libplasma-6.8.2); Plasma's own shell QML uses `PlasmaCore.Dialog` (grep hit in `/usr/share/plasma/shells/org.kde.plasma.desktop/…`). Kickoff = panel-attached applet using the KRunner library for search (per https://develop.kde.org/docs/plasma/krunner/ — "These plugins can be used by any application using the KRunner library, like the default Application Launcher").
- Could reuse Milou's results list (`org.kde.milou` QML installed HOST; `ResultsView.qml` exposes `limit` alias ⇒ the 15-cap is raisable if you instantiate it yourself).
- Cons for a keyboard-first overlay launcher:
  - Lifecycle fused to plasmashell — plasmashell restart/crash takes the launcher; slower iteration (install plasmoid + restart shell vs re-run binary).
  - Dialog geometry is popup logic (edge-relative, applet-anchored); precise screen-center floating is fighting the framework.
  - Version-coupled to Plasma internals (libplasma API churn), and you can't dbus-activate independently of the shell.
  - The window is a normal toplevel with bypass flags (same as KRunner today) — no overlay stacking, and Wayland focus rules apply.
- Verdict: best if Foyer wants to *be a widget*; wrong if it wants to *own the spotlight window* and daemon lifecycle.

### 1.C Plain normal/centered window (Albert/Ulauncher style)
- On Wayland, clients cannot self-position windows (no global coordinates). KRunner itself papers over this with `QT_WAYLAND_DISABLE_FIXED_POSITIONS` (fetched main.cpp) — a hack, not a contract.
- Focus: activation is compositor-discretion (focus-stealing prevention); taskbar/pager/alt-tab entries by default (skip-taskbar hints needed); window animates/appears in window list; stacking below panels/OSD — no overlay guarantee.
- Albert markets "lightning-fast, keyboard launcher" but is X11-first in behavior; Ulauncher (GTK) documents theming limited to colors because "changing element sizes is not possible due to restrictions in the GTK+ API" (https://docs.ulauncher.io/en/latest/themes/themes.html) — both are cited as cautionary precedents, not models.
- Verdict: keep as X11/fallback code path only; do not build the Wayland experience on it.

### 1.D Recommendation
**Option A — standalone Qt6/QML daemon + LayerShellQt surface.** Concretely:
1. `foyerd`: resident process, `Type=dbus` systemd user unit `foyer.service` + `/usr/share/dbus-1/services/org.kde.foyer.service` (mirror `plasma-krunner.service`, HOST-verified above) with `PartOf=graphical-session.target`. QQmlEngine created once at activation; `LayerShellQt::Shell::useLayerShell()` before any window; window pre-built & hidden → open = `show()` + `requestActivate()` (sub-150 ms is the same class of work KRunner does per keystroke; first-ever start after D-Bus activation pays one-time engine spin-up — estimate 300–600 ms, UNVERIFIED number).
2. Surface: `LayerTop`, anchors `Top|Left|Right` + computed top margin (or floating+margin recipe), `KeyboardInteractivityOnDemand` (+`Exclusive` opt-in), `closeOnDismissed`-style Esc → hide (keep process).
3. Blur: `KWindowEffects::enableBlurBehind(window, true)` once at window setup (same call Plasma dialogs use; kf6-kwindowsystem installed HOST). Transparent `QQuickWindow` background; match mask to panel shape like dialog.cpp's `updateTheme()`.
4. Theming: `QQuickStyle::setStyle("org.kde.breeze")` (qqc2-breeze-style installed HOST; standard QQuickStyle API — https://doc.qt.io/qt-6/qquickstyle.html) or Kirigami controls. Colors from the system scheme, not constants (see §1.E).
5. Shortcut: `~/.local/share/applications/org.kde.foyer.desktop` registered via kglobalaccel `[services]` (fleet-proven on this host); Exec points at a tiny `foyer-toggle` D-Bus poke (or the daemon itself) — the known "kglobalaccel caches Exec at registration / lands next login" semantics are accepted per the brief.
6. Fallback: if not on Wayland/KWin (X11 session), degrade to option C behavior.
- Why over B: independent lifecycle (survives plasmashell restarts; D-Bus-activatable), full window control (overlay layer, exclusive keyboard, no popup-geometry fights), normal app iteration speed, still perfectly "native" (Qt6 + KDE libs + Breeze style + blur protocol).
- Why over C: overlay stacking + guaranteed no taskbar/alt-tab + compositor-blessed keyboard + deterministic placement — none of which a plain Wayland toplevel can promise.
- Spike checklist (≈1 day): layer-shell window on LayerTop w/ anchors+margin; `enableBlurBehind`; OnDemand vs Exclusive focus; show/hide timing loop (`QElapsedTimer`); verify KWin blurs a layer surface; kglobalaccel registration through one login.

### 1.E Cross-cutting concerns
**Breeze theming + accent color inside a standalone QML app**
- QQC2 Breeze style is installed system-wide (`org/kde/breeze` under qt6/qml, rpm qqc2-breeze-style-6.8.2 — HOST). Apply with `QQuickStyle::setStyle("org.kde.breeze")` before loading QML (API: https://doc.qt.io/qt-6/qquickstyle.html). This styles Controls (buttons, textfields) Breeze-like without plasmashell.
- Kirigami 6.31 installed HOST (`org/kde/kirigami` full QML tree incl. controls/layouts/platform). Kirigami's `Kirigami.Theme` follows the platform palette/theme (repo: https://github.com/KDE/kirigami; exact PlatformTheme→scheme wiring UNVERIFIED here). Heavier than raw Controls; worth it if Foyer wants pages/settings chrome for free.
- Accent color, ground truth on this host: `~/.config/kdeglobals` carries the **full active scheme** (per-group `DecorationFocus`/`DecorationHover` values; `[General] ColorSchemeHash`) and `~/.config/kdedefaults/kdeglobals` pins `ColorScheme=Vapor` — **Bazzite ships Valve's Vapor scheme (blue #1e92ff-ish DecorationFocus in Complementary group), NOT stock Breeze**. So: read colors via `KColorScheme`/`KConfig` (KF6 KConfigWidgets, https://api.kde.org/frameworks/kconfigwidgets/html/classKColorScheme.html) or inherit via QPalette once a KDE platform theme is loaded — never hardcode Breeze blue, or Foyer looks wrong on this very machine. No `AccentColor=` key exists here (Plasma 6.7+/6.8 stores accent inside the scheme; HOST-observed).

**Blur / translucency**
- Covered in §1.A: KWindowEffects → `org_kde_kwin_blur_manager` protocol (source-verified both client impl and Plasma's own use). Also available: `enableBackgroundContrast` for legibility on busy wallpapers (same API page). QML side: window `color: "transparent"`, opaque content panels — same structure PlasmaCore.Dialog uses (dialog.cpp `updateTheme()` computes the mask from the background item).

**Instant warm start (systemd / D-Bus activation)**
- Pattern proven on host by krunner: D-Bus service file (`SystemdService=plasma-krunner.service`) + unit (`Type=dbus`, `BusName=org.kde.krunner`, `PartOf=graphical-session.target`, `Restart=no`, `Slice=background.slice`). Foyer copies this 1:1 (`org.kde.foyer`). First D-Bus call (from the shortcut's Exec or `KDBusService`) boots the daemon once; every subsequent open is a warm `show()`. Keep query engines (app index, KRunner runner manager if reused) loaded — KRunner's own plugins are loaded once per daemon session (per develop.kde.org KRunner docs: runners instantiated once, `init()` once).

**Global shortcut registration (kglobalaccel)**
- Host reality: `org.kde.kglobalaccel` is served by kwin_wayland (busctl HOST). Framework: https://github.com/KDE/kglobalaccel ("global accelerators that are independent of the focused window").
- Path 1 (proven on this host): install a `.desktop` + register it as a "command" shortcut → lands in `kglobalshortcutrc` under `[services][<file>.desktop]` (fleet example `hermes-ask.desktop`, `_launch=Meta+H`). kglobalaccel caches the Exec at registration; changes apply next login (accepted per brief). Exec can simply be `foyer --toggle` (daemon call) — same shape as the existing busctl poke.
- Path 2 (in-app): link KGlobalAccel and call `KGlobalAccel::setGlobalShortcut` for a named component while running (needs kf6-kglobalaccel-devel, not installed HOST). Cleaner UX (configurable from System Settings), but the shortcut exists only while/unless the component registered at least once — same next-login caveats apply on fresh profiles.
- Meta+<key> choices can collide with KWin internal shortcuts (both live in kglobalaccel) — pick default carefully (e.g. keep Alt+Space parity or a Meta+F-style combo; the host already uses Meta+H for hermes-ask, so Meta+F is free — HOST-checkable).


## 2. PART 2 — Precedent digest
(each: layout / density / hierarchy / keyboard model / worth stealing / what's bad)

### 2.1 Raycast (macOS/Windows, closed source)
- URLs: https://www.raycast.com/ · https://manual.raycast.com/
- Layout: single centered floating window (~⅓ screen width): large query row, dense icon+title+subtitle rows, right-aligned key hints; results grouped under section headers (Applications, Fallback, Store…). The manual's hero screenshot is literally titled "Raycast on Root Search" — root search listing *everything* is the spine.
- Hierarchy: query → sections → rows → per-item actions (⌘K) → nested subviews (extensions push full-screen-ish lists inside the same window).
- Keyboard model: arrows + Return; Backspace pops a level; per-command custom global hotkeys AND text aliases; everything reachable without mouse ("Fast. Ergonomic. Keyboard First."; 99.8% crash-free claim on site).
- Worth stealing: root-search-as-discovery (type anything, see every command matching); per-command hotkey + alias layer; actions-as-a-list (secondary actions on ⌘K, not hidden right-click); inline previews (files, colors, links); section headers as scoping device.
- What's bad: closed source + subscription-gated AI; feature sprawl (Notes, Timers, Window Mgmt, Focus…) dilutes launcher identity and fattens the root search; extension store = maintenance/security surface.

### 2.2 macOS Spotlight
- URL: https://support.apple.com/guide/mac-help/spotlight-search-mchlp1008/mac
- Layout: centered panel, **best match on top**, results grouped by type (Applications, Documents, Calculations…); user-draggable and remembers position; opens by ⌘Space (or Dynamic Island drag on some hardware).
- Instant-answer hierarchy: math, unit/currency conversion, definitions, clipboard history answer *inside the results* — answer-first, app-second.
- Keyboard: type → arrows → Return; Up arrow recalls previous search; **Space = Quick Look** preview on a result; **Tab = Quick Actions** (contextual actions on the selected result).
- Worth stealing: inline answers ranked above app results; type-grouped sections; preview key (Space) as first-class; clipboard history as a top-level lane.
- What's bad: web suggestions/Siri-AI creep reorder locally relevant results; ranking is opaque; actions limited vs Raycast.

### 2.3 Albert
- URL: https://albertlauncher.github.io/
- Layout: compact centered-top window; dense single-column rows (icon, title, subtitle, action hint); "lightning-fast, plugin-based keyboard launcher" with speed as a stated *primary design goal* ("designed to be fast", 200+ KPM claim).
- Plugin system: "curated collection of peer-reviewed, actively maintained plugins… could be your go-to app launcher or a full-blown system command palette"; APIs "simple and easy to learn".
- Keyboard: classic launcher model — type, fuzzy match, arrows, Enter; per-item secondary actions.
- Worth stealing: speed as an explicit product identity (measurable budget); curated/peer-reviewed plugin curation model; action hints per row.
- What's bad: Qt-Widgets-era visuals (not QML/modern); settings UI sprawl; custom license (see §3) complicates downstream reuse.

### 2.4 Ulauncher
- URLs: https://ulauncher.io/ · https://docs.ulauncher.io/en/latest/themes/themes.html
- Layout: centered-top bar; fuzzy search that "remembers previous picks, and auto-selects the best option next time" (MRU/frequency learning) — zero-config great first-run experience.
- Theming (docs-quoted limitation): only colors are themeable — "Changing element sizes is not possible due to restrictions in the GTK+ API." A hard density ceiling QML simply doesn't have.
- Extras: shortcuts + extension ecosystem (ext.ulauncher.io); fast directory browser via `~` or `/`, Alt+Enter for advanced options.
- Worth stealing: MRU + frequency auto-select; quick directory mode; extension shortcuts.
- What's bad: Python/GTK3 stack (daemon latency, the theming ceiling above); no compositor-level integration (no blur/layer placement).

### 2.5 KDE Kickoff + KRunner 6 (the incumbent)
- URLs: https://userbase.kde.org/Plasma/Kickoff · https://develop.kde.org/docs/plasma/krunner/
- Kickoff: panel-attached popup; search field focused on open; search matches name AND description ("type 'browser' → all browsers"); favorites (drag-pin), recent + frequent lists; whole launcher swappable via "Show Alternatives…" (Application Dashboard etc.).
- KRunner 6.8 (HOST-audited): single query line, top-center; results = Milou `ListView` with runner section headers, wrap-around key nav (`keyNavigationWraps: true`), `limit: 15` rows (ResultsView.qml:53 — the cap, on disk); trigger words + `?` help runner; "single runner mode" over D-Bus lets other apps bind a key to one runner (docs cite EmojiRunner example).
- Keyboard: Alt/Meta+Space → type → arrows (wrapping) → Enter; secondary actions via Tab in results.
- Worth stealing: description-matching (not just names); wrap-around nav; trigger-word prefixes; single-runner mode (Foyer can expose scoped palettes the same way); KCM config pages (System Settings integration).
- What's bad (the brief's list, verified): 15-row render cap hardcoded in the shipped instance; rows-only protocol (a ListView — no cards/grids/multi-pane); no in-app settings UI (KCM-only); no per-result hotkeys; no history prefix.

### 2.6 GNOME search (Activities overview + Nautilus) — "Swordfish" flagged
- URLs: https://developer.gnome.org/hig/patterns/nav/search.html · https://salivity.github.io/gnome/article/how-gnome-unified-search-works-for-files-and-apps · https://en.wikipedia.org/wiki/TinySPARQL · https://discourse.gnome.org/t/gnome-activities-overview-search-with-substring/29453
- Model: type-to-search in the overview aggregates async D-Bus **search providers** (apps, files, settings, calculator…) — a clean provider-aggregation architecture; files via TinySPARQL/LocalSearch indexer (ex-Tracker); HIG defines search as filtering with results list under the entry.
- Known pain, documented: tokenization misses substrings (discourse: "apple" fails to match `001_apple_tree.png`); discoverability is poor enough that "6 hidden GNOME Search tricks" (ZDNet, Oct 2025) is a mainstream article.
- Worth stealing: D-Bus provider aggregation (Foyer can wrap KRunner runners AND define its own provider spec); per-provider caps/ordering; an indexer-backed file lane instead of `find`.
- What's bad: weak fuzzy/substring matching; sprawling undifferentiated results; no action model on results.
- ⚠️ **"Swordfish" = UNVERIFIED**: no canonical GNOME artifact by that name found (2026-11-07 searches; only hit is an unrelated retired personal wiki page, https://wiki.gnome.org/Mike%20swordfish). If the brief meant a codename for GNOME's search overhaul, it left no citable trace — digest covers the shipped system instead. Parent should confirm intent.

### 2.7 Windows PowerToys Run
- URL: https://learn.microsoft.com/en-us/windows/powertoys/run (docs banner: evolving into "Command Palette" v2 — industry converging on palettes)
- Layout: compact bar, icon rows, per-result **context buttons** with keyboard chords (Ctrl+Shift+Enter run-as-admin, Ctrl+Shift+E reveal folder, Ctrl+C copy path); Tab cycles results ↔ context buttons.
- **Prefix routing table** (docs, cited verbatim examples): `=` calculator, `?` file search, `!` services, `$` settings, `<` Window Walker, `!!` history, `@` PowerToys, `.` programs, `//` URI, `??` web search… Docs even list the known prefix-collision hazards (path/math characters).
- Latency-tuning vocabulary worth copying wholesale into Foyer's settings (docs-quoted): "Input smoothing" (debounce delay), "Immediate plugins: how many ms a plugin may make the UI wait", "Background execution plugins" wait, "Number of results shown before scrolling", "Wait for slower plugin results before selecting top item (risk of jumpiness)", "Selected item weight".
- Worth stealing: prefix routing; per-plugin latency budgets; `!!` history as first-class; results-before-scroll setting; context-button row per result.
- What's bad: documented prefix-collision bug class; settings sprawl; Windows-only.

### 2.8 Linear command palette
- URLs: https://linear.app/changelog/2019-12-18-new-command-menu · https://linear.app/docs/search · https://linear.app/docs/select-issues · https://linear.app/now/invisible-details
- Command menu (⌘/Ctrl+K) is "one of the core components of Linear and lets you execute any command with just a few keystrokes… hundreds of actions" (changelog).
- Contextual scoping: palette/menus adapt to selection ("Once an issue or set of issues are selected, use Cmd/Ctrl K to open the command bar"); changelog: behaves like a dropdown but "retains its searchability and keyboard controllability".
- **Single-letter search prefixes** (docs/search): `i ` issues, `p ` projects, `u ` users, `t ` team, `l ` labels, `f ` favorites, `d ` documents — the cleanest scope-prefix scheme found.
- Everything-is-a-command: actions live in the same searchable surface; contextual menus double as shortcut teachers ("take almost every action… without using a mouse at all" — engineering post).
- Worth stealing: scope prefixes; context-aware command scoping; unification of search + actions; palette as the app's spine.
- What's bad: app-level only (no OS surface); in very large command sets exact-name matches can rank below fuzzy hits (anecdotal — UNVERIFIED).

### 2.9 tldr pages / OMH
- tldr: https://tldr.sh/ · https://github.com/tldr-pages/tldr — "simplified, community-driven man pages": each page = command → one-line description → example list ordered by likelihood-of-use; large client ecosystem (CLI/GUI/web — wiki-linked).
- Worth stealing: **example-first command cards** — the ideal content format for a launcher's command-help lane (a `ffmpeg` card with copy-paste examples beats any man-page row); community curation with a simple page format.
- What's bad: quality/staleness variance across pages.
- OMH (fleet-internal, no public URL — per local skill `infrastructure/omh-operations`): orchestration layer over Hermes Agent (`/dag-ulw` DAG runs, category→model chains, evidence gates). Precedent for *palette-as-agent-front-end* (typed intents → categorized executors). Its documented failure mode is the cautionary tale: ceremony-heavy lanes burned ~499k input tokens for zero artifacts in a 2026-10-31 smoke — if Foyer ever fronts agent dispatch, keep per-invocation ceremony near zero.

## 3. PART 3 — Existing KDE-native / adjacent launcher projects
(all repo facts API-checked 2026-11-07 unless noted)
- **Albert** — https://albertlauncher.github.io/ · https://github.com/albertlauncher/albert — Qt6/C++ + Python plugins; **custom "Albert license v1.1"** (LICENSE.md, fetched); active (pushed 2026-11-03, ~8.0k stars). Not Plasma-integrated: own widget UI, X11-era windowing assumptions.
- **Ulauncher** — https://github.com/Ulauncher/Ulauncher — Python/GTK3; **GPL** (LICENSE fetched, © 2015 Aleksandr Gornostal); active (2026-11-05, ~4.5k stars). Foreign toolkit, no compositor integration.
- **Kando** — https://kando.menu/ · https://github.com/kando-menu/kando — Qt6/QML cross-platform **pie/radial menu** (mouse/gesture-first, explicitly not keyboard-search); **MIT** (LICENSE.md fetched); very active (2026-11-06, ~6.6k stars). Adjacent, not a competitor to a search palette.
- **Walker** — https://github.com/abenz1267/walker — GTK4 **layer-shell** launcher for generic Wayland; **GPL-3.0** (API field); pushed 2026-10-08, ~3.1k stars. Proves the layer-shell launcher pattern ships at scale — outside KDE.
- **rofi** — https://github.com/davatorium/rofi — **MIT/X11** (COPYING fetched); active (2026-11-07, ~16.5k stars); X11-native switcher/launcher with Wayland support path (details UNVERIFIED here). `lbonn/rofi` = historical wayland fork (API description: "see davatorium/rofi").
- **fuzzel** — https://codeberg.org/dnkl/fuzzel — wlroots layer-shell launcher (foot author); MIT per project page (UNVERIFIED this session; repo is Codeberg-only, hence GitHub 404s).
- **KDE's own swappable menus** — Kickoff alternatives mechanism ("Show Alternatives…", UserBase §2.5); third-party menu plasmoids circulate (OnzeMenu-6, Fancy Menu names) but their repo identity could NOT be verified this session (GitHub 404 on guessed paths) — verify before citing further.
- **Gap finding (the opportunity)**: no active project combines KDE-native stack (Kirigami/QQC2-Breeze + LayerShellQt + KRunner's runner library) with a modern palette UI. Albert/Ulauncher are toolkit outsiders; Kando is radial; rofi/fuzzel/walker are wlroots-world. **The "Raycast for KDE" slot is genuinely empty.**

## 4. Source list
**KDE implementation surface**
- LayerShellQt repo/README (usage, CMake): https://github.com/KDE/layer-shell-qt · https://invent.kde.org/plasma/layer-shell-qt
- Layer-shell protocol explainer (linked from README): https://drewdevault.com/2018/07/29/Wayland-shells.html
- KWindowEffects API (enableBlurBehind/BackgroundContrast): https://api.kde.org/kwindoweffects.html
- KDE blur Wayland protocol: https://wayland.app/protocols/kde-blur (xml in https://invent.kde.org/libraries/plasma-wayland-protocols)
- KGlobalAccel: https://github.com/KDE/kglobalaccel · https://invent.kde.org/frameworks/kglobalaccel
- KRunner plugin docs (runner model, single-runner D-Bus mode): https://develop.kde.org/docs/plasma/krunner/
- Kickoff user docs: https://userbase.kde.org/Plasma/Kickoff
- QQuickStyle (org.kde.breeze application): https://doc.qt.io/qt-6/qquickstyle.html
- KColorScheme: https://api.kde.org/frameworks/kconfigwidgets/html/classKColorScheme.html
- Kirigami: https://github.com/KDE/kirigami
- Source files fetched & saved under `src/`: `layer-shell-qt-README.md`, `window.h` (full LayerShellQt API), `kws-effects.cpp` (KWindowSystem wayland blur client), `dialog.cpp` (libplasma PlasmaCore.Dialog — blur calls at ~L222/238, no layer-shell use), `krunner-main.cpp` (QT_WAYLAND_DISABLE_FIXED_POSITIONS hack + layer-shell comment).

**Precedents**
- Raycast: https://www.raycast.com/ · https://manual.raycast.com/
- Spotlight: https://support.apple.com/guide/mac-help/spotlight-search-mchlp1008/mac
- Albert: https://albertlauncher.github.io/
- Ulauncher: https://ulauncher.io/ · https://docs.ulauncher.io/en/latest/themes/themes.html
- PowerToys Run: https://learn.microsoft.com/en-us/windows/powertoys/run
- GNOME search: https://developer.gnome.org/hig/patterns/nav/search.html · https://salivity.github.io/gnome/article/how-gnome-unified-search-works-for-files-and-apps · https://en.wikipedia.org/wiki/TinySPARQL · https://discourse.gnome.org/t/gnome-activities-overview-search-with-substring/29453
- Linear: https://linear.app/changelog/2019-12-18-new-command-menu · https://linear.app/docs/search · https://linear.app/docs/select-issues · https://linear.app/now/invisible-details
- tldr: https://tldr.sh/ · https://github.com/tldr-pages/tldr
- Kando: https://kando.menu/ · https://github.com/kando-menu/kando

**Provenance & confidence notes**
- Host facts: probed by shell on gdtower (Bazzite 45, Plasma/KWin 6.8.2, Qt 6.11.2) — §1.0.
- Web facts: fetched directly from the pages above (web_extract) or from raw source files (curl of github/jsdelivr mirrors); the primary SearXNG backend was returning junk during this session (known degraded mode), so nothing load-bearing rests on search snippets.
- GitHub API rate-limited some repo lookups; license claims come from fetched LICENSE/COPYING files where possible (Albert/Ulauncher/Kando/rofi verified this way, Walker via API field, fuzzel UNVERIFIED).
- Open items for the spike: (1) KWin blur-on-layer-surface runtime check; (2) Kirigami PlatformTheme→accent wiring; (3) kglobalaccel registration end-to-end through one login; (4) show-time budget measurement (<150 ms target).

<!-- END OF DIGEST v1.0 — 2026-11-07 -->

