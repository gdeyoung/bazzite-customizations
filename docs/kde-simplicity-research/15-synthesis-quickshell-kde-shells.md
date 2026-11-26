---
title: "Synthesis II — Quickshell shells on KDE Plasma 6 (End-4Dots-KDE, NextKde/KOS, quickshell-kde)"
date: 2026-11-12
batch: kde-simplicity-research wave 2
dossiers: 10-end4dots-kde.md, 11-nextkde-kos.md, 12-quickshell-kde-architecture.md, 13-quickshell-framework-capabilities.md, 14-omarchy-plugin-ecosystem.md
prior: 00-SYNTHESIS-REPORT.md (2026-11-04)
method: 5 parallel research lanes, 96 API calls, primary-source verified (GitHub API/raw files, quickshell.org docs, Fedora dist-git, COPR api_3, Omarchy registry.json). Static analysis only — no runtime install was performed.
---

# Synthesis II — the Quickshell-on-KDE shell wave, audited

## 1. Verdict in one paragraph

The Foyer companion-chrome doctrine **survives contact with the counterexamples**. The
three most complete public attempts to put a Quickshell shell *over* Plasma 6 each
confirm the 2026-11-04 conclusion from a different angle: **end-4dots-kde** started
pure-QML and, the moment it got serious (dev branch, Oct 2026), left QML for compiled
C++ — a `plasma-window-management` Wayland plugin, a kglobalaccel component, a compiled
KWin effect — and never even attempted a Quickshell launcher (they ship fuzzel; KRunner
stays). **NextKde/KOS** (863★, ~7 commits/day) achieved a *working* full takeover — but
only by forking the compositor: six compiled KWin plugins, two private Wayland
protocols, a native window decoration; its glass effect is currently broken on **KWin
6.8.2 + NVIDIA (issue #329) — the fleet's exact stack**. **quickshell-kde** (2★,
AI-agent-driven) is the quiet one: it stays user-space and compositor-clean, and its
adapter-singleton architecture is the most transferable artifact of the whole batch.
What the wave *did* change: three genuinely new user-space mechanics exist now that
didn't when dossier 02 was written (§3), and the Omarchy port backlog got a hard
quantification (§5).

## 2. Blurb claims vs reality

| Claim (from the research blurb) | Audited reality |
|---|---|
| End-4Dots-KDE "ports End-4 dotfiles to Plasma 6 using Quickshell" | True but demo-grade on `main`: v1.0.0 ships a 0-byte systemd unit (bridge daemon never starts) and a mock `hyprctl` missing `clients -j` — window widgets dead, user issues #7/#10 match. The live `dev` branch is the serious one, rebased onto caelestia-kde (1,078★) with compiled C++ |
| NextKDE "liquid glass aesthetic, floating dock, integrated settings, replaces panels" | All real and mechanically clean (ShellPackage re-point, not hacks), but the glass is a *forked KWin blur effect with Snell's-law refraction shaders + 2 private protocols*. Requires KWin 6.6+ SDK, Quickshell 0.3.x, compilers. Chinese-first audience; no HN/Reddit footprint; KOS is a brand, not an acronym (unverified it expands to anything) |
| quickshell-kde "isolates compositor-specific functionality to work cleanly with KWin" | Accurate but modest: it's two QML singletons (`KWinService`/`WindowService`) + env-var guards + `qdbus6` subprocess transport, window data via KRunner's sanctioned `/WindowsRunner` interface. No Hyprland backend exists (yet). 2★, one-day main, but sprint branches carry a serious "Milestone 3A" composable rearchitecture |

## 3. The three new user-space mechanics (none existed in dossier 02's survey)

1. **ShellPackage re-point** (NextKde `kosctl`): back up `plasmashellrc [Shell]
   ShellPackage`, install a wallpaper-only shell package in `~/.local/share/plasma/`,
   write the key with `kwriteconfig6 --notify false`. plasmashell keeps running
   (wallpaper + KWin integration) while panels/folder-view vanish; uninstall restores.
   The first *legitimate, reversible, zero-compile* panel-takeover primitive.
2. **The KWin-script event bridge** (end-4dots `src/kwin-script` + quickshell-kde
   rung 2): a ~70-line pure-JS KWin script serializes `workspace.windowList()` /
   desktop state and `callDBus`-pushes it to a session-bus service. Event-driven
   window/workspace data, user-space install (`kwinrc [Plugins]` key), no ABI risk.
   Poll-based fallback: KRunner `/WindowsRunner` via `org.kde.krunner1` Match/Run —
   sanctioned, always present, dodges KWin's restriction of
   `zwlr_foreign_toplevel_manager_v1`; 2.5 s latency, indicator-grade only.
3. **Bus-name yielding via conditional Loader** (quickshell-kde): ship notification /
   tray capability behind `Loader { active: configFlag }`, default-off beside Plasma;
   keep `"tray"` out of default bar slots. Turns the SNI-collision rule from
   "don't build it" into "build it, default it to Plasma."

## 4. Framework state that constrains planning (dossier 13)

- Fedora 45 (and Rawhide) ship **Quickshell 0.2.1-git snapshot**; everything that
  changed the KDE story is 0.3-only (polkit agent, idle, NetworkManager,
  `WindowManager` over ext-workspace-v1 — protocol-viable on Plasma ≥ 6.7; the host's
  6.8.2 qualifies). 0.3.2 exists only via COPR `errornointernet` = an rpm-ostree
  layering decision. Stock 0.2.1 already exceeds what end-4dots-kde targets.
- Hard KWin-side gaps unchanged: no compositor blur (`ext-background-effect-v1` — no
  KWin implementation evidence; verify with `wayland-info` in harness), per-window
  capture Hyprland-only, SNI single-watcher collision structural.
- Open Quickshell crash class on exactly our hardware class: monitor hotplug/DPMS
  teardown (#910, #1340), reproduced by caelestia-kde users on Plasma 6.7.5/6.8.2 →
  add DPMS/unplug cycles to the harness suite.
- Ecosystem warning: Noctalia (12k★) *left* the Quickshell runtime for native C++/GLES;
  no major shell targets KWin. Betting a long campaign on QS-shell portability is
  betting on a pre-1.0 API surface.

## 5. Omarchy port backlog, quantified (dossier 14)

Quattro (v4 alpha) is 100% Quickshell QML — Waybar is gone; repo moved to
`omacom/omarchy`. Marketplace `registry.json`: **6,464 plugins**, ~2k/month growth since
Aug 2026, 72% bar widgets, 36 weathers / 27 notifiers (duplication extreme), 138
retirements + 110 repo migrations in 4 months → **pin upstream commits on every port**.
After the Plasma-already-owns-it filter: **~10–15 plugins worth porting** — the
AI/agent-usage lane (`robzolkos.agent-usage`, `arthurr0.claude-usage`,
`felixzsh.codexbar`, `aval4nch.agents-claude-status`), tailscale, docker, todo, and the
**emoji picker — the one genuine Plasma 6 gap found**. The fleet's own 15 gdeyoung
repos remain the primary backlog. Prior art: `majesticio/plasmarchy` (recipe-based
converter; explicitly refuses arbitrary QML translation — independently reaches the
Foyer conclusion) and `Wizmo-inc/plasmarchy` (runs the real Omarchy QS bar inside a
Plasma session; tested Omarchy 4.0.0 / Plasma 6.7.4 / QS 0.3.1). **Nobody does native
applet-by-applet ports at scale — the fleet's campaign is first.**

## 6. Ideas ranked (worth-it cases only)

**I1 — Author dual-target, stop porting (architecture change).** Adopt the
quickshell-kde adapter seam fleet-wide: compositor code lives *only* in QML adapter
singletons (`KWinService` / a `HyprlandService` twin over `hyprctl -j`) behind a
written interface contract, env-var detection (`KDE_FULL_SESSION` /
`HYPRLAND_INSTANCE_SIGNATURE`), UI modules barred from compositor commands, total
no-op degradation off-compositor. One authored plugin then runs on host-12/vivobox
(Omarchy) and the tower (Plasma companion chrome) unchanged — the "port our Omarchy
plugins" problem inverts into an authoring convention. *Worth it:* ~half a day of
structure; eliminates the per-plugin port for every new plugin; both desks share one
repo and one test rig (`.rig/e2e.sh` pattern: private D-Bus + `kwin_wayland --virtual`
— already our harness shape).

**I2 — Build the KWin-script event bridge once, as fleet infrastructure.** The ~70-line
script + `callDBus` pusher (end-4dots) gives event-driven window/workspace data to any
companion-chrome surface, replacing 2.5–3 s qdbus polling. Uses the exact
loadScript/`kwinrc [Plugins]` enable recipe already proven in the hotkey campaign.
*Worth it:* ~1 day incl. harness QA; unblocks taskbar/workspace indicators in Foyer
chrome without compiled code; reverses "WM-wrapper modules dead on Plasma" *for data*
(control still needs C++ — that boundary is now triple-confirmed).

**I3 — Validate ShellPackage re-point once in the harness, then shelve.** The
wallpaper-only-package takeover is the only reversible full-shell escape hatch that
survives the no-layering rule. *Worth it:* 1–2 h to prove the mechanism (kwriteconfig
in, reboot-free `kwin_wayland --replace`-equivalent check in nested harness, restore
out). Ship nothing now — the tower keeps Plasma panels. It becomes the play if a kiosk /
bot-screen / secondary-machine surface ever wants Foyer chrome as the entire desktop.

**I4 — Version discipline: stock 0.2.1 ships, 0.3.2 is the harness triage bench.** No
shipped surface depends on QS 0.3 until the owner makes the COPR-layering call (0.3
buys polkit/NM/idle/WindowManager). Meanwhile 0.3.2 *in the harness* runs any Omarchy
marketplace plugin near-verbatim in a Plasma session — use it as the smoke-test bench
to decide *which* plugins earn a native applet port before spending the 1–5 days each.
*Worth it:* zero production risk, kills bad port candidates early.

**I5 — Port queue (next 5):** (1) an agent-usage applet consolidating the
claude/codex/agent-status lane into one Plasma applet + HTTP-API daemon (fleet pattern,
process-spawn constraint already solved); (2) emoji picker — the catalog's one genuine
Plasma gap; (3) `omarchy-tailfin` (Tailscale status — fleet-relevant, data-shaped);
(4) `omarchy-timemachine` chip (rsync status, proven engine bundled); (5)
`omarchy-sysmon` sibling of the already-proven stocktick sizing work. Pin upstream
commits; skip everything the panel/systemtray already surfaces.

**I6 — Zero-compile steal-list from end-4dots (drop-in recipes):** OSD-mute kwriteconfig
keys (for any edge where QS chrome owns OSD duty), `kglobalshortcutrc` parser +
modmask table for shortcut-cheatsheet widgets, matugen ↔ kde-material-you-colors
templates (QS chrome and Plasma frames track one palette — the cheapest answer to the
"no Breeze integration" theming tax), XDG-autostart `sleep 2 && qs -c` launch pattern.

**I7 — Watch, don't adopt:** caelestia-kde (1,078★ — the real descendant of the
end-4dots line, pushed daily) and NextKde (fastest-moving, but compiled-KWin coupling
breaks on point releases — #329 is our exact KWin). Quickshell-kde sprint branches for
the ModuleRegistry/composable pattern. Monthly glance is enough; no adoption path under
fleet rules.

## 7. Not verified (be honest about it)

All findings are static analysis of source/docs — no shell was installed or run.
Pending harness checks: `wayland-info` on nested kwin for `ext-background-effect-v1`,
`ext-image-copy-capture-v1`, `wlr-foreign-toplevel` (one command each, settles the
blur/capture/toplevel questions); SNI duplicate-icon behavior with Plasma tray live;
NextKde on Bazzite via distrobox (untested upstream, not worth fleet time now).
Dossier-level gaps are listed in each file's final sections.
