# Porting an Omarchy plugin → Plasma 6 (one-session recipe)

The Omarchy feeling on Bazzite = the same probes + models, a KDE-native shell.
Ground truth reference for structure: `../../plasma-sysmon/` (shipped port).

## 1. Inventory the source
- `BarWidget.qml` → compactRepresentation (panel chip)
- `Panel.qml` → fullRepresentation (popup; self-size via implicitHeight)
- `Model.js` / zone data → port VERBATIM (pure JS, no Quickshell deps)
- probe scripts (`*.sh`) → copy byte-identical; only paths/inventory differ per host
- `manifest.json` → `metadata.json` (KPackageStructure/Applet, Min-Version 6.0)

## 2. Translation table (Quickshell → Plasma)
| Quickshell | Plasma 6 |
|---|---|
| `PanelWindow` + widget | `PlasmoidItem` root + compact/full children |
| `Process { command: [...] }` | `DataSource { engine:"executable"; connectedSources:[cmd]; interval: N }` (plasma5support 2.0, unaliased) |
| `ShellRoot` config hub | `Plasmoid.configuration.*` + `contents/config/main.xml` |
| `PopupWindow` | fullRepresentation + `root.expanded` |
| `FileView { path: ... }` | DataSource `connectedSources:["cat <path>"]` on interval, or Timer + DataSource re-link |
| `Qt.resolveUrl` | `Qt.resolvedUrl` |
| `Kirigami.Units.smallRadius` | `Kirigami.Units.smallSpacing / 2` |
| glyph/text styling | same glyphs; colors from PlasmaCore.Theme / Kirigami.Theme ONLY |

## 3. Settings (KConfig XT)
`contents/config/main.xml` declares keys; `contents/config/config.qml` renders
the page (KCM.SimpleKCM from org.kde.kcmutils). Settings UI from the Omarchy
widget's SettingsView map 1:1 to controls.

## 4. Install (NEVER during a build session — install is a separate, listed step)
```
kpackagetool6 -t Plasma/Applet -i <dir>          # first install
kpackagetool6 -t Plasma/Applet -u <dir>          # upgrade
systemctl --user restart plasma-plasmashell.service   # NEVER pkill plasmashell
```

## 5. Verify (in this order)
1. Static: `tools/check_qml.py <widget-dir>` → 0 errors.
2. Probe: `tools/check_qml.py <widget-dir> --probe-run <probe.sh>` (read-only probes only).
3. Live (install day only): heartbeat file `/tmp/<id>-hb.json` advances;
   `journalctl --user -u plasma-plasmashell.service` shows no QML errors naming
   your files; screenshot the panel chip and popup (spectacle -b -n).
4. Desktop-containment instance for popup compile-test, removed afterwards.

## 6. House rules (bazzite-customizations)
- User-level only: `~/.local`, no sudo, no rpm-ostree layering, reversible.
- Numbers or it didn't happen: measured verify values in the README.
- Nothing private ships: endpoints/paths are parameters, no LAN specifics.
- Credit the upstream Omarchy plugin (ours, but record the source pin).
