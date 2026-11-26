# KDE DevEx Simplification Dossier — Fast, No-Compile Extension Lanes on Plasma 6.8 (Bazzite/ostree)

Scope: every official + community path to simplify/accelerate Plasma 6 shell-extension development (plasmoids and adjacent no-compile surfaces), focused on feedback-loop speed on an immutable Fedora-atomic host (Plasma 6.8.2 / KWin 6.8.2, user-level installs to `~/.local`, no system packages without `rpm-ostree` layering).
Source tiers: **S** = official docs/source · **A** = vendor blogs/release notes, distro packaging · **B** = independent tech media, well-known community wikis · **C** = forums/Reddit/SO. Host-verified items marked **[HOST]**.
Date: 2026-11-04. Host facts re-verified this session: `plasma-sdk` NOT installed (rpm -q), `plasma-workspace 6.8.2` [HOST]; `kpackagetool6`, `plasmawindowed`, `plasma-interactiveconsole` on PATH [HOST, prior live check].

---

## 1. ITERATION-LOOP TOOLING

### 1a. `plasmoidviewer` (plasma-sdk) — the closest thing to a Quickshell-style dev loop

**What it is / does.** A graphical tool that runs a Plasma applet in its own window, wrapped in an emulated containment — no plasmashell, no panel, no restart of the session. Officially documented as one of the 3 sanctioned test methods. [S: https://develop.kde.org/docs/plasma/widget/testing/] [S: https://man.archlinux.org/man/plasmoidviewer.1.en]

**Zero-install mode (the key simplifier).** `plasmoidviewer -a ~/Code/plasmoid-helloworld/package` loads a widget **directly from a source folder, without installing it** — "particularly useful for development as you can now skip the install step". An installed plugin id works too. [S: https://develop.kde.org/docs/plasma/widget/testing/#plasmoidviewer]
→ Dev loop becomes: edit QML → re-launch `plasmoidviewer -a package` (~1–2 s cold start, no kpackagetool, no shell restart). Comparable ceremony to Quickshell's `qs -c config` run.

**Flags (full `--help`, S: develop.kde.org testing page + Arch man page):**
- `-a, --applet <applet>` — plugin id **or package folder path**
- `-c, --containment <name>` — alternate containment plugin
- `-f, --formfactor <horizontal|vertical|mediacenter|planar|application>`
- `-l, --location <floating|desktop|fullscreen|topedge|bottomedge|leftedge|rightedge>`
- `-x/-y/-s <x> <y> <WxH>` — window position/size; `-p <kB>` pixmap cache; `-t <theme>` theme name override
- Panel-widget simulation: `plasmoidviewer -a package -l topedge -f horizontal`; desktop widget: `-l floating -f planar` (the default). Caveat: `--location=desktop` = wallpaper, NOT desktop widgets. [S: testing page "Test as Horizontal Panel Widget"/"Test as Desktop Widget"]
- DPI testing: `QT_SCALE_FACTOR=2 plasmoidviewer -a package -s 1920x1080` [S: testing page]
- positional `args` are passed to the applet as the `externalData` event [S: Arch man page]

**What environment it loads (limits).** It links the Plasma runtime, so `plasmoid` global object, `PlasmoidItem`, config UI (KConfigXT) and dataengines are available and formFactor/location are simulated via flags. It does NOT give you: the real panel/systemtray context (system tray popup sizing is hardcoded differently), real containment interaction, or your other widgets around it. Config changes are not the "same command used for Windowed widgets", so config persistence differs from plasmawindowed. The man page (dated Plasma 5.8) says "Only installed applets will be found" and suggests `kbuildsycoca5` for newly installed ones — superseded for folder-path mode by the develop.kde.org page (which is current, KF6-era). [S: man page, dated] [S: testing page, current]
- `console.log()` output is hidden by default; enable with `QT_LOGGING_RULES="qml.debug=true"` per-run, or persist via `kwriteconfig6 --file ~/.config/QtProject/qtlogging.ini --group Rules --key qml.debug true` (doc shows kwriteconfig5; the KF6 binary is kwriteconfig6). [S: testing page "Enable logging"]

**Cost on Bazzite/ostree.** `plasma-sdk` is a normal RPM (Fedora `plasma-sdk`, KDE SDK group). Installing = `rpm-ostree install plasma-sdk` + reboot (or `rpm-ostree install --apply-live` for immediate-ish apply). Deps are mostly Qt6/Plasma libs already on the image; the layer cost is one package + few siblings, not a toolchain. [A: Fedora packaging; layering semantics = rpm-ostree docs] Note **[HOST]**: plasma-sdk currently absent; `plasmoidviewer` unavailable until layered.
**Workaround that needs zero layering:** `plasmawindowed` (below) is shipped in plasma-workspace and already on PATH [HOST].

### 1b. `plasmawindowed <pluginId>` — the preinstalled, lowest-ceremony runner

- Documented as test method #1: works **only if the widget is installed** in `~/.local/share/plasma/plasmoids`; "limited features for displaying the widget, but the command should be preinstalled". Remembers config changes — it is the same container used by "Windowed widgets" (e.g. Calculator). [S: https://develop.kde.org/docs/plasma/widget/testing/#plasmawindowed]
- Flags: `--statusnotifier` (keep plasmoid alive in notification area after window close); positional args → externalData. Example: `plasmawindowed org.kde.plasma.kickoff`. [S: testing page]
- Loop: `kpackagetool6 -u package && plasmawindowed com.example.helloworld` — one reinstall command + sub-second window relaunch, no plasmashell restart, no panel disruption. This is the **no-layering baseline loop on this host** [HOST: binary present].
- Limits vs plasmoidviewer: no formfactor/location emulation (always "application" windowed mode), no theming/size/DPI flags. Panel-specific compact/full behavior must still be tested in a real panel or plasmoidviewer.

### 1c. QML hot reload against a live plasmashell

- **QML disk cache knobs (official Qt):** `QML_DISABLE_DISK_CACHE=1` forces recompilation of all QML/JS from source (overrides `QML_DISK_CACHE`); `QML_DISK_CACHE=<path>` relocates the cache; `QML_FORCE_DISK_CACHE` forces it on. Purpose: cache-corruption debugging / CI, NOT live reloading — Qt does not re-evaluate already-loaded QML documents when files change on disk. [S: https://doc.qt.io/qt-6/qmldiskcache.html]
- **Applying to plasmashell:** export the env for the session user unit before plasmashell starts: `systemctl --user set-environment QML_DISABLE_DISK_CACHE=1 && systemctl --user restart plasma-plasmashell.service` (restart mechanism documented in community/admin practice [C: https://www.reddit.com/r/kde/comments/1of8j5m/]; `plasmashell --replace` is the classic equivalent [C: https://discuss.kde.org/t/how-to-restart-plasma-panel/15490]). Cost: affects ALL shell QML (slower shell start); gains only cache-staleness immunity, not hot reload. **Verdict: not a hot-reload lane; use only when a stale `.qmlc`-style cache is suspected.** (Stale-cache symptom class is old: "old QML is cached … restart plasmashell" [C: https://stackoverflow.com/questions/40819536/refresh-my-new-plasmoid-reparse-source, 2016, Qt5-era].)
- **Community hot-reload tooling:** no established plasmashell-integrated hot reloader exists (searched: "qml hot reload plasmoid", "qml live reload plasma"). Generic QtQuick hot-reload tools (e.g. Patric Grimm's `Hot Reload for QML`, `live-qml`-style Loader+watcher approaches) work by owning the QML engine in your own app — they cannot attach to the already-running plasmashell process. Qt Creator's QML live preview likewise drives its own engine. **Conclusion: zero-restart live reload inside the production plasmashell is not available; the fast loops are (a) plasmoidviewer/plasmawindowed relaunch and (b) nested-harness plasmashell restart (already in fleet).** [C-consensus: absence across develop.kde.org, discuss.kde.org, Reddit; see §5]
- **AI-agent packaging of the loop:** a community "Claude-KDE-Plasmoid-Dev-Plugin" exists (Claude Code skill for plasmoid dev) — evidence the loop is being codified for agents; treat as C-tier artifact. [C: https://github.com/danielrosehill/Claude-KDE-Plasmoid-Dev-Plugin]

### 1d. `kpackagetool6 -u` + remove/re-add applet — reload without shell restart

- The official "final test" loop is: `kpackagetool6 -u package` → add widget to panel → `plasmashell --replace` (or `systemctl --user restart plasma-plasmashell.service`); docs recommend this only as a final test because the panel takes seconds to reload. [S: https://develop.kde.org/docs/plasma/widget/testing/ ("There are 3 ways to test a widget", item 3)]
- Removing and re-adding just the applet via `plasmawindowed`/`plasmoidviewer` relaunch reloads QML without touching the panel (see 1a/1b). Inside the LIVE shell, the scripting console / DBus `evaluateScript` (`pids()`/`panels()[0].removeWidget(...)` then `addWidget(...)`) re-instantiates the applet from the updated package without a shell restart; this is the same mechanism already documented fleet-side. Reliability caveats (community): the applet instance keeps its loaded QML until re-created; System Tray-hosted applets need removal via the tray entry itself; after `kpackagetool6 -u` the sycoca/package registry refresh is immediate for KPackage types in Plasma 6 (no kbuildsycoca step documented). [S for API: evaluateScript docs already in fleet KB; C for community reliability evidence — see §5 thread list]
- **Premise check/correction:** editing QML of *shipped* system widgets under `/usr/share/plasma/plasmoids/` on an immutable OS is doubly blocked (read-only /usr + upstream migration of several core applets away from plain QML packages — see §4 "compiled QML" note). The supported edit loop is: copy package to `~/.local`, change `Id`, iterate there. [C: https://www.reddit.com/r/kde/comments/1r82hd9/ (6.6-era report); S: develop.kde.org setup — user installs go to ~/.local/share/plasma/plasmoids]

## 2. OFFICIAL TEMPLATES & SCAFFOLDS

**KDE-documented minimal path (the "two-file widget").** develop.kde.org's official Setup page: create `package/` with just `metadata.json` + `contents/ui/main.qml` ("you can get away with just the main.qml and metadata.json for a barebones widget") — no build system, no CMake, no compile. Gotcha keys: `KPackageStructure: "Plasma/Applet"` required, and **`"X-Plasma-API-Minimum-Version": "6.0"` is required or the widget is hidden in Plasma 6 UI** (widgets without it are "assumed to only work with Plasma 5"). [S: https://develop.kde.org/docs/plasma/widget/setup/]

**libplasma official templates (in-tree, KF6).** `invent.kde.org/plasma/libplasma` → `templates/` ships: `qml-plasmoid6`, `qml-plasmoid6-with-qml-extension`, `cpp-plasmoid6`, `plasma6-wallpaper`, `plasma6-wallpaper-with-qml-extension`. [S: https://github.com/KDE/libplasma/tree/master/templates] The `qml-plasmoid6` CMakeLists is **CMake/ECM-based** (`find_package(ECM)`, `KDEInstallDirs`, `plasma_add_applet(... QML_SOURCES ... GENERATE_APPLET_CLASS)`) [S: https://raw.githubusercontent.com/KDE/libplasma/master/templates/qml-plasmoid6/CMakeLists.txt]. develop.kde.org's C++ API page points at the plasma-framework template as the scaffold for compiled widgets. [S: https://develop.kde.org/docs/plasma/widget/c-api/]
→ **Friction note for immutable hosts:** the official scaffold assumes the CMake+ECM+KF6-devel toolchain; the doc's two-file folder path needs none of it and is the agent-optimal scaffold. There is no dedicated `plasma-applet-template` repo on invent.kde.org beyond the in-tree templates (searched; none found).

**kapptemplate.** Still shipped and current (26.08.x releases, `kde-sdk` group on Arch; OpenBSD/current packaging) — "Templates especially for KDE-development (plugins for Plasma, QtQuick, KTextEditor, KRunner, Akonadi)". The Plasma DeveloperGuide walks: KAppTemplate → "Plasmoid / QML Plasmoid / Plasma QML Applet" → skeleton. [S: https://apps.kde.org/kapptemplate/] [A: https://archlinux.org/packages/extra/x86_64/kapptemplate/] [B: https://community.kde.org/Plasma/DeveloperGuide (partially stale: still shows metadata.desktop/plasmapkg2)]. kapptemplate is a GUI generator + another RPM to layer on ostree; low value for agents vs. copying the libplasma template or hand-rolling two files.

**Community templates (C-tier).**
- `Agundur-KDE/KDE-Plasma-Plasmoid-template` — "clean, minimal starting point for Plasma 6, pure QML, no boilerplate" + companion tutorial (Sep 2026). [C: https://github.com/Agundur-KDE/KDE-Plasma-Plasmoid-template, https://www.agundur.de/projects/kde-plasma-6-plasmoid-template-tutorial.html]
- Zren (Chris Holland) widget tutorial — the de-facto community bible; its testing sections were upstreamed into develop.kde.org. [C: http://zren.github.io/kde/docs/widget/]
- dhruv8sh Medium "How to write a Plasma 6 applet" (plasmoidviewer-based flow, GitHub example repo). [C: https://medium.com/@dhruv8sh_34505/write-an-applet-for-plasma-6-0b8fd3a0334f, https://github.com/dhruv8sh/plasma6-window-title-applet]
- Real-world reference codebase: `lenonk/plasma6-applet-eventcalendar` (Oct 2026, active). [C: https://github.com/lenonk/plasma6-applet-eventcalendar]

## 3. NON-COMPILE EXTENSION SURFACES (agent-authorable, friction-rated)

All below are user-level (~/.local), no compiler, restartable/verifiable from CLI.

| Surface | Format | Install/verify loop | Friction |
|---|---|---|---|
| Plasma widget (plasmoid) | QML + metadata.json | `kpackagetool6 -t Plasma/Applet -u pkg && plasmawindowed <id>` | LOW |
| KWin script | JS or QML + metadata.json | `kpackagetool6 --type=KWin/Script -i`; enable `kwriteconfig6 --file kwinrc --group Plugins --key <id>Enabled true && qdbus org.kde.KWin /KWin reconfigure` | LOW |
| Plasma Style | SVG + colors hints | drop in `~/.local/share/plasma/desktoptheme/`; preview via plasmathemeexplorer | LOW |
| Look-and-Feel | package + defaults + splash/lock QML + layout.js | `~/.local/share/plasma/look-and-feel/`; preview via lookandfeelexplorer | MED |
| Aurorae decoration | SVG (or QML) + rc | `~/.local/share/aurorae/themes/` (KWin Window Decoration settings) | LOW-MED |
| Wallpaper plugin | QML package | same KPackage flow as plasmoids | MED |
| SNI tray icon | DBus service (any language) | register `org.kde.StatusNotifierItem-*` on session bus; verify via busctl | MED |
| Notifications w/ actions | org.freedesktop.Notifications | `notify-send -A 'a=Label'` — chosen action to stdout | VERY LOW |
| Global shortcut → action | KWin script `registerShortcut()` | live via script load; or kglobalaccel config (no live reload) | LOW (script) / MED (kglobalaccel) |
| KDE Connect plugin | C++ in-app | **not a no-compile surface** — protocol/DBus only | N/A |

- **KWin scripts (JS/QML):** rich API: `workspace` (clients, desktops, activities), `options` (read-only), `registerScreenEdge()`, `registerShortcut()` (registers global shortcuts with callback — a no-compile shortcut lane), `readConfig()`, full animation framework (`animate/set/retarget`, `addFragmentShader`), assertions helpers. [S: https://develop.kde.org/docs/plasma/kwin/api/] Fast loop: console (`KRunner → "wm console"` or `plasma-interactiveconsole --kwin`) executes instantly; packaged scripts enable/reload via `qdbus org.kde.KWin /KWin reconfigure` — **no WM restart**. Caveats: console scripts are ephemeral; System Settings list "does not yet reload after installing"; logging needs `QT_LOGGING_RULES`/kdebugsettings + journal (`journalctl -f QT_CATEGORY=js QT_CATEGORY=kwin_scripting`); non-client windows are invisible to scripts (KWin Effects only); no custom install hooks; `options` read-only. [S: https://develop.kde.org/docs/plasma/kwin/] Publishing = zip → store.kde.org category "Linux/Unix Desktops > Window Managers > KWin > KWin scripts". [S: same]
- **Plasma Style:** SVG element reference + Inkscape guidance + accent-color-following SVGs + quickstart; live dirs on host [HOST: /usr/share/plasma/desktoptheme → air, breeze-dark, …]. [S: https://develop.kde.org/docs/plasma/theme/]
- **Look-and-Feel (Global Theme):** package structure `Plasma/LookAndFeel` with defaults, splash, lock/logout, layout, previews [C examples: https://github.com/Leydansantino/The-Ultimate-Plasma, https://www.reddit.com/r/kde/comments/1juz38b/]; dirs on host [HOST: /usr/share/plasma/look-and-feel]. Dev-facing change: "Drop ShellPackage integration from Look and Feel" (6.7.90 changelog) simplifies the package. [S: https://kde.org/announcements/changelogs/plasma/6/6.7.5-6.7.90/]
- **Aurorae:** official dev doc: "SVG or QML to render the decoration and buttons, and there is a simple config file"; themes = several SVGs; still maintained (6.8 changelog bumps its Qt/Frameworks requirements). [S: https://develop.kde.org/docs/plasma/aurorae/, https://github.com/KDE/aurorae]
- **Wallpaper QML plugins:** official template `plasma6-wallpaper` (+ `-with-qml-extension` variant) in libplasma; KPackage install like applets; upstream examples in kdeplasma-addons. [S: https://github.com/KDE/libplasma/tree/master/templates] [C: https://discuss.kde.org/t/wanting-to-contribute-a-daily-wallpaper-plugin-where-can-i-start/16569] (develop.kde.org `/docs/plasma/wallpapers/` covers wallpaper content, not plugin API.)
- **StatusNotifierItem (tray):** freedesktop spec (DBus `org.kde.StatusNotifierItem`/Watcher; canonical URL: https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/ — page not re-extractable this session). Any process owning a session-bus SNI name appears in Plasma's tray. Python routes: `pystray` (menu/icons; Linux backend GTK/AppIndicator — not verified against Plasma 6 Wayland tray), or hand-rolled DBus via Gio/jeepney. [A: https://notmart.org/blog/2014/12/yet-another-way-to-make-your-app-support-statusnotifieritem/] **Correction to a tempting premise:** Python 3.14 stdlib `tkinter.systray` is only on the CPython **dev branch docs** — import fails on this host [HOST]; not a usable lane yet. [A: https://docs.python.org/es/dev/library/tkinter.systray.html]
- **Notifications with actions:** libnotify 0.8.9 on host supports `notify-send -A '[NAME=]Text'` (implies `--wait`, prints chosen action to stdout, `--selected-action-fd` for scripts) — fully headless-verifiable interactive notifications. [HOST: `notify-send --help`] Spec: org.freedesktop.Notifications (actions incl. `default`). [S: https://specifications.freedesktop.org/notification-spec/]
- **KNewStuff / store.kde.org publishing:** pattern documented on the KWin page: zip the package folder, upload to store.kde.org under the matching category; consumers install via Discover/"Get New …". No compile, account + manual upload (no CLI publish API found — web upload form). [S: https://develop.kde.org/docs/plasma/kwin/#publishing, https://store.kde.org/browse/cat/210/]
- **kglobalaccel:** editing `~/.config/kglobalshortcutsrc` does **not** live-reload (community threads; relogin/kglobalaccel restart needed), which makes the file route brittle for agents; the KWin-script `registerShortcut()` route registers shortcuts live with no config surgery. [C: https://discuss.kde.org/t/plasma-6-method-to-refresh-kglobalaccel-shortcuts/17995, https://www.reddit.com/r/kde/comments/1peuog9/, https://readwithai.substack.com/p/creating-kde-keyboard-shortcuts-from]
- **KDE Connect (premise correction):** plugins are compiled into the app; there is no external plugin API — the scriptable surface is the `org.kde.kdeconnect` DBus API / `kdeconnect-cli`, and the wire protocol is openly documented (JSON-schema-generated reference). Author an integration, not a plugin. [C: https://www.reddit.com/r/kde/comments/1s9jej2/] [S: https://github.com/KDE/kdeconnect-meta/blob/work/protocol-schemas/protocol.md] [B: https://community.kde.org/KDEConnect]

## 4. PLASMA 6.7 / 6.8 DEV-FACING CHANGES + Qt 6.9–6.11 QML TOOLING

**Plasma 6.8 (2026-10-14) — user announcement + version wiki (S):**
- **X11 session support removed** (Wayland-only; XWayland for legacy apps) — extension authors no longer need an X11 test path. [S: https://kde.org/announcements/plasma/6/6.8.0/, https://community.kde.org/Plasma/Plasma_6]
- **Union theming beta**: styles Qt Quick (6.7 alpha) and now Qt Widgets apps; `union` package + "Breeze (Union)" style; custom Union styles documented at api.kde.org/working-with-styles.html — an emerging no-compile styling surface to watch. [S/A: same + https://api.kde.org/working-with-styles.html, https://quantumproductions.info/articles/2026-08/union-summer-2026-update]
- Dev-loop relevant perf: **faster plasmashell load times** (plasma-workspace !6898), **reduced memory for multiple widgets** — shrinks the `plasmashell --replace` final-test penalty. [S: https://community.kde.org/Plasma/Plasma_6#Plasma_6.8]
- ksystemstats: VRAM-use-percentage sensor; System Monitor can set CPU affinity. New `kscreenctl` CLI (scriptable display config — useful for headless harness). [S: same]
- Dependency bumps visible in the complete changelog (e.g. aurorae: Qt ≥ 6.11, KF ≥ 6.30). [A: https://kde.org/announcements/changelogs/plasma/6/6.7.5-6.8.0/]
- **No plasmoid-API porting notes for 6.7/6.8 exist** (no porting doc beyond KF6) → the Plasma 6 applet API is stable; breakage reports in the wild are Qt-version related (e.g. Qt 6.10.1 breaking plasmashell QML on Arch), not Plasma API churn. [S-absence + C: https://bbs.archlinux.org/viewtopic.php?id=310323]

**Plasma 6.7 (S: community.kde.org/Plasma/Plasma_6#Plasma_6.7):** Union tech preview; per-screen virtual desktops (KWin scripts see per-screen desktops — scripts must not assume one global desktop list); "background apps" (GNOME-style) surfaced in system tray (plasma-workspace !5703 — more SNI-shaped citizens in tray); global push-to-talk shortcut (plasma-pa !394 — relevant to Voxtype PTT fleet tooling); notification-history-clear shortcut; libksysguard storage-unit preferences respected by System Monitor widgets; Look-and-Feel "Drop ShellPackage integration" (6.7.90).

**Qt 6.9–6.11 QML tooling (A: Qt blog / docs):**
- qmlls gained `-I <importpath>` and `-E` (honor `QML_IMPORT_PATH`) in **Qt 6.8** — the fix for resolving distro-installed KDE QML modules without building your own Qt. [A: https://nicolasfella.de/posts/qmlls-for-kde-development-2/]
- Qt 6.11 qmlls: **go-to-C++-definition** (Qt 6.10+ projects), **multi-project/workspace-folder support** (kills cross-project import-path bleed), official **standalone qmlls release** usable without the distro Qt (GitHub `TheQtCompanyRnD/qmlls-workflow`) — the no-layering route on ostree. [A: https://www.qt.io/blog/whats-new-in-qml-language-server-in-6.11]
- qmllint 6.6→6.11: new shadowing warnings + `virtual`/`override`/`final` property keywords (`[property-override]`, `[duplicated-name]`, `[duplicate-inline-components]`; `[id-shadows-member]` lands in 6.12); full catalog in docs. [A: https://www.qt.io/blog/whats-new-in-qml-tooling-for-qt-6.11-part-2, S: https://doc.qt.io/qt-6/qmllint-warnings-and-errors.html]
- A part-3 post on **context-property configuration** was linked from the series but 404s at fetch time (announced, content unverified). 
- **Can qmlls/qmllint check `org.kde.plasma.*`?** Partially. Modules need qmltypes + import paths: pass `-I /usr/lib64/qt6/qml` (or set import path); `org.kde.plasma.plasmoid` is a *dynamically registered* module so editors show "cannot find" until given Plasma's build dirs (`QMLLS_BUILD_DIRS` pointing at .qmlls.ini dirs) — KDE dev-confirmed workflow. Kate ships qmlls support but binary naming differs per distro (`qmlls`/`qmlls6`). Remaining hard cases: `i18n()`/context-property `plasmoid` lookups (injected at runtime) — warnings expected. [C: https://discuss.kde.org/t/plasmoid-vscode-how-to-properly-import-org-kde-plasma-plasmoid/32357 (answer by Plasma maintainer Méven Car), https://www.reddit.com/r/kde/comments/1bbefld/] [A: both nicolasfella.de posts] [S: https://doc.qt.io/qt-6/qtqml-tooling-qmlls.html]
- **Fedora packaging:** on this host `/usr/lib64/qt6/bin` contains NO qmllint/qmlls/qmlformat [HOST] — they ship only in `qt6-qtdeclarative-devel` (subpackage file list not re-verified this session), i.e. **lint/LSP requires ostree layering of a -devel package** or the standalone qmlls release above. `qdbus-qt6`, `qtpaths6` are present [HOST].

## 5. HOW KDE UPSTREAM DEVELOPERS ACTUALLY ITERATE

- **The documented loop (authored by the widget-docs maintainer, Zren):** 1) `plasmawindowed <id>` (preinstalled, config persists), 2) `plasmoidviewer -a <folder|id>` with formfactor/location flags, 3) real panel + `plasmashell --replace` only as a *final* test ("takes a few seconds for the panel to load"). QML disk-cache issues are the one case where env-var surgery (`QML_DISABLE_DISK_CACHE`) enters the picture. [S: https://develop.kde.org/docs/plasma/widget/testing/]
- **KWin maintainers:** interactive console (`wm console` / `plasma-interactiveconsole --kwin`) for instant script execution against the running WM; `qdbus org.kde.KWin /KWin reconfigure` to reload installed scripts; journal for output. [S: https://develop.kde.org/docs/plasma/kwin/]
- **Frameworks/Plasma devs on tooling:** Nicolas Fella's posts codify the qmlls-for-KDE setup (Kate out-of-the-box, `-DQT_QML_GENERATE_QMLLS_INI=ON`, `-I`/`-E`, declarative registration needed); Méven Car's forum answer directs plasmoid devs to LSP + QMLLS_BUILD_DIRS. Editor-of-choice in the community: Kate (LSP built-in) or VS Code. [A: nicolasfella.de posts] [C: discuss.kde.org thread]
- **Plasma DeveloperGuide (community wiki, updated 2026-05):** template → adjust metadata → edit QML → install → run; explicitly frames C++ as optional ("In some cases… extend the functionality by writing a C++ plugin") — QML-first is the endorsed model. [B: https://community.kde.org/Plasma/DeveloperGuide]
- **Building Plasma itself** (kdesrc-build, develop.kde.org getting-started) is only for people hacking plasma-workspace/libplasma internals — *not* required for any user-level extension surface in this dossier. [S: https://develop.kde.org/docs/getting-started/building/ (linked from the 6.8 announcement as the source-build path)]
- **Hot reload remains absent upstream:** no plasmashell-attachable reloader exists in official or prominent community tooling (searches across develop.kde.org/discuss/GitHub found none); the ecosystem answer to fast feedback is standalone runners (plasmoidviewer/plasmawindowed) and nested sessions — matching this fleet's nested-wayland harness approach. Community agents codify the same: the Claude-KDE-Plasmoid-Dev-Plugin skill ships exactly "the kpackagetool6 install/test loop + plasmoidviewer for isolated previews" and lists plasma-sdk's Cuttlefish/plasmathemeexplorer/lookandfeelexplorer as the supporting tools. [C: https://github.com/danielrosehill/Claude-KDE-Plasmoid-Dev-Plugin/blob/master/README.md]

## VERDICT — fastest loops on this host (ranked)

1. **KWin JS/QML script:** `plasma-interactiveconsole --kwin` (instant, zero packaging) → package + `kpackagetool6 --type=KWin/Script -u` + `qdbus org.kde.KWin /KWin reconfigure`. No restarts at any stage.
2. **Plasmoid (QML-only):** two-file package → `kpackagetool6 -u` + `plasmawindowed <id>` (preinstalled [HOST]); optional `rpm-ostree install plasma-sdk` unlocks `plasmoidviewer -a <folder>` zero-install runs + formfactor/DPI emulation.
3. **Plasma Style / Aurorae / Look-and-Feel:** file-drop + theme-explorer previews (explorers need plasma-sdk).
4. **Notifications actions / SNI / KDE Connect DBus:** pure runtime surfaces, zero install.
Not available: hot reload into live plasmashell (use nested harness for restart-sensitive tests); KDE Connect plugins (C++-only).

## GAPS / UNVERIFIED

- plasma-sdk RPM size + exact dep closure on F45/Bazzite (`dnf repoquery` returned empty on host; Fedora packages page lists only the subpackage name "Development tools for Plasma 6", no size).
- Fedora subpackage carrying qmllint6/qmlls6 (believed `qt6-qtdeclarative-devel`; file list not confirmed this session).
- Qt blog part 3 "context property configuration for QML tooling" — linked but 404; would matter for linting `plasmoid`-context code.
- Reddit thread on Plasma 6.6 ending QML-editability of shipped widgets is login-walled; kept only its search-snippet claim (compiled-QML migration trend) as C-tier signal.
- freedesktop SNI spec page failed extraction (site blocked scrapers); canonical URL cited, content not re-verified.
- `qml-plasmoid6` template's QML file path (CMakeLists references `qml/main.qml`; `contents/ui/main.qml` 404) — template layout partially mapped.
- KWin-JS sandbox limits (no process spawning etc.) are folklore; current official docs only state the limits listed in §3 — treat stronger claims as unverified.
- No CLI/API for store.kde.org publishing found (web form only) — inference from docs absence, not positively confirmed.
- kapptemplate ↔ libplasma template equivalence assumed from docs pointers, not verified by generating a project.

## SOURCE REGISTER (counted: 56)

S: develop.kde.org widget/setup, widget/testing, widget/c-api, kwin/, kwin/api/, theme/, aurorae/, wallpapers/, scripting/; api.kde.org/working-with-styles.html; doc.qt.io qmldiskcache, qtqml-tooling-qmlls, qmllint-warnings-and-errors; man.archlinux.org plasmoidviewer(1); community.kde.org/Plasma/Plasma_6, Plasma/DeveloperGuide, KDEConnect; kde.org announcements 6.8.0 + changelogs 6.7.5-6.8.0 + 6.7.5-6.7.90; raw libplasma qml-plasmoid6 CMakeLists; github.com/KDE/libplasma/tree/master/templates; github.com/KDE/aurorae; kdeconnect-meta protocol.md; specifications.freedesktop.org/notification-spec; freedesktop.org StatusNotifierItem wiki; store.kde.org/browse/cat/210; develop.kde.org/docs/getting-started/building.
A: apps.kde.org/kapptemplate; archlinux.org kapptemplate package; qt.io blogs (qmlls 6.11, qmllint 6.11 pt2); nicolasfella.de ×2; notmart.org SNI; docs.python.org dev tkinter.systray; quantumproductions.info Union update; bbs.archlinux.org Qt 6.10.1 breakage; packages.fedoraproject.org/pkgs/plasma-sdk.
B: —(wiki items counted under S/B above).
C: zren.github.io; Agundur template + tutorial; dhruv8sh Medium + repo; lenonk eventcalendar; danielrosehill Claude plugin; SO 40819536; discuss.kde.org 15490, 32357, 17995, 16569, 12274; Reddit 1r82hd9, 1of8j5m, 1bbefld, 1peuog9, 1juz38b, 1s9jej2; readwithai.substack; develmonk.com; Leydansantino/The-Ultimate-Plasma.
HOST-verified this session: rpm plasma-workspace 6.8.2; plasma-sdk absent; /usr/lib64/qt6/bin inventory; notify-send 0.8.9 -A; ksystemstats/plasma-interactiveconsole/kpackagetool6/plasmawindowed present; theme dirs; python3 tkinter.systray/pystray absent.
