# KDE Plasma 6 Plugin & Extension Framework: Developer & Agent Reference Manual

This manual provides an authoritative technical reference for developing plugins, widgets, and scripts for the KDE Plasma 6 desktop environment. It maps the architectural paradigms of modern Wayland shell toolkits (such as Omarchy's Quickshell framework for Hyprland) to KDE's native extension interfaces.

---

## 1. Architectural Mapping: Omarchy / Quickshell vs. KDE Plasma 6

| Layer | Omarchy / Hyprland Architecture | KDE Plasma 6 Equivalent |
| :--- | :--- | :--- |
| **Shell Host Process** | `omarchy-shell` (Quickshell long-running instance) | `plasmashell` (Qt 6 / KF6 host process) |
| **Panel / Bar Widgets** | Quickshell Plugins (`manifest.json` + QML) | **Plasma Widgets (Plasmoids)** (`metadata.json` + QML) |
| **Window Management** | Hyprland C++ Plugins / `hyprctl` / IPC | **KWin Scripts** (QML / JS engine in `kwin_wayland`) |
| **Command Palette / Search**| Omni / Quickshell overlay plugins | **KRunner Plugins** (C++ or out-of-process D-Bus runners) |
| **UI Definition Language** | QtQuick / QML (Declarative) | QtQuick / QML with Kirigami & PlasmaComponents |
| **Manifest Contract** | `manifest.json` | `metadata.json` (`KPackage` specification) |
| **Isolated Test Runner** | Standalone Quickshell launcher | `plasmoidviewer` / `plasmawindowed` |
| **CLI Package Tool** | `omarchy plugin [install|clone]` | `kpackagetool6` |

---

## 2. Plasma 6 Widget (Plasmoid) Specification

Plasma 6 introduces major architectural updates over Plasma 5. All Plasma 6 widgets require the `X-Plasma-API-Minimum-Version: "6.0"` declaration and use `PlasmoidItem` from `org.kde.plasma.plasmoid` as the root item.

### 2.1 Standard Directory Structure
A complete Plasmoid is packaged as a `KPackage` directory layout:

```text
~/.local/share/plasma/plasmoids/org.myorg.mywidget/
├── metadata.json
└── contents/
    ├── config/
    │   ├── config.qml             # Config page registration
    │   └── main.xml               # KConfig XML schema for settings
    └── ui/
        ├── main.qml               # Primary widget entry point (PlasmoidItem)
        ├── FullRepresentation.qml # Expanded popup view (optional)
        └── configGeneral.qml      # Configuration dialog UI page
```

### 2.2 Manifest Contract (`metadata.json`)
The `metadata.json` file defines the plugin identity, required API versions, category, and entry points:

```json
{
    "KPlugin": {
        "Id": "org.myorg.mywidget",
        "Name": "System Pulse",
        "Description": "Real-time telemetry and process monitor",
        "Icon": "utilities-system-monitor",
        "Authors": [
            {
                "Name": "Developer Name",
                "Email": "dev@example.com"
            }
        ],
        "Category": "System Information",
        "Version": "1.0.0",
        "License": "GPL-2.0-or-later"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0",
    "X-Plasma-NotificationArea": false
}
```

### 2.3 UI Implementation (`contents/ui/main.qml`)
In Plasma 6, widgets dynamically adapt to their placement (panel vs. desktop):

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Tell Plasma whether to render compact (panel) or full (desktop/popup)
    preferredRepresentation: compactRepresentation

    // Properties exposed to Plasmoid configuration
    readonly property string customTitle: Plasmoid.configuration.title || "Telemetry"

    // 1. Compact Representation (Mounted in panel / status bar)
    compactRepresentation: MouseArea {
        id: compactArea
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.5

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "utilities-system-monitor"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: "42%"
                font.bold: true
            }
        }
    }

    // 2. Full Representation (Popup window when clicked, or desktop containment)
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing

            Kirigami.Heading {
                level: 2
                text: root.customTitle
            }

            PlasmaComponents.Label {
                text: "Memory Pressure: Normal\nActive Agents: 4"
                Layout.fillWidth: true
            }

            PlasmaComponents.Button {
                text: "Flush Cache"
                icon.name: "edit-clear"
                Layout.alignment: Qt.AlignRight
                onClicked: {
                    console.log("Action triggered from Plasmoid")
                }
            }
        }
    }
}
```

### 2.4 Configuration Management
Plasma provides a declarative schema and two-way bound settings engine:

1. **Schema Definition (`contents/config/main.xml`)**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
      http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile name=""/>
    <group name="General">
        <entry name="title" type="String">
            <default>Telemetry</default>
        </entry>
        <entry name="refreshInterval" type="Int">
            <default>5</default>
        </entry>
    </group>
</kcfg>
```

2. **Config Page Registration (`contents/config/config.qml`)**:
```qml
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "configure"
        source: "configGeneral.qml"
    }
}
```

3. **Config UI (`contents/ui/configGeneral.qml`)**:
```qml
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page
    property alias cfg_title: titleField.text

    QQC2.TextField {
        id: titleField
        Kirigami.FormData.label: "Widget Title:"
    }
}
```

---

## 3. Window Management & Tiling: KWin Scripting Specification

For controlling window geometry, tiling layouts, workspace rules, and window events (equivalent to Hyprland plugins), KDE uses **KWin Scripts**.

### 3.1 Script Package Layout
```text
~/.local/share/kwin/scripts/org.myorg.mytiler/
├── metadata.json
└── contents/
    └── code/
        └── main.js
```

### 3.2 Manifest Contract (`metadata.json`)
```json
{
    "KPlugin": {
        "Id": "org.myorg.mytiler",
        "Name": "Auto-Tiling Engine",
        "Description": "Dynamic tiling rules for Wayland",
        "Icon": "preferences-system-windows",
        "Authors": [{ "Name": "Dev", "Email": "dev@example.com" }],
        "Version": "1.0",
        "License": "MIT"
    },
    "KPackageStructure": "KWin/Script"
}
```

### 3.3 Core Script API (`contents/code/main.js`)
KWin exposes global objects: `workspace` and `options`.

```javascript
// Listen to new window creations
workspace.windowAdded.connect(function(client) {
    if (client.normalWindow && !client.skipTaskbar) {
        print("New window managed: " + client.caption + " [" + client.resourceClass + "]");
        
        // Auto-tile or reposition
        if (client.resourceClass === "org.wezfurlurl.wezterm") {
            // Reposition window geometry (Plasma 6 geometry object)
            client.frameGeometry = {
                x: 100,
                y: 100,
                width: 1200,
                height: 800
            };
        }
    }
});

// React to workspace switching
workspace.currentDesktopChanged.connect(function(desktop) {
    print("Switched to desktop: " + desktop);
});
```

---

## 4. Command Palette & Runners: KRunner D-Bus Protocol

KRunner allows writing search and execution plugins in any language (Python, Rust, Go) via an out-of-process D-Bus interface (`org.kde.krunner1`).

### 4.1 Required D-Bus Interface
A runner daemon registers on the session bus and implements three methods:

| Method Name | Signature | Description |
| :--- | :--- | :--- |
| `Actions` | `() -> a(sss)` | Returns available context actions `[(id, text, icon)]` |
| `Match` | `(s) -> a(sssida{sv})` | Computes matches for search query `s`. Returns `[(id, text, icon, type, relevance, properties)]` |
| `Run` | `(ss) -> ()` | Executes action when user selects a match (`id`, `actionId`) |

### 4.2 Minimal Python Runner Template
```python
#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE_NAME = "org.kde.runners.myagent"
OBJECT_PATH = "/myagent"

class AgentRunner(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method("org.kde.krunner1", in_signature="", out_signature="a(sss)")
    def Actions(self):
        return []

    @dbus.service.method("org.kde.krunner1", in_signature="s", out_signature="a(sssida{sv})")
    def Match(self, query):
        if not query.startswith("agent "):
            return []
        
        cmd = query[6:].strip()
        # Returns: [(id, title, icon, match_type, relevance (0.0-1.0), properties)]
        return [(
            "agent_task_1",
            f"Dispatch to Agent: {cmd}",
            "system-run",
            100,  # Exact/High match
            0.9,
            {"subtext": "Queue task in agent orchestration pipeline"}
        )]

    @dbus.service.method("org.kde.krunner1", in_signature="ss", out_signature="")
    def Run(self, match_id, action_id):
        print(f"Triggered runner match: {match_id}")

if __name__ == "__main__":
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()
    name = dbus.service.BusName(SERVICE_NAME, session_bus)
    runner = AgentRunner(session_bus)
    loop = GLib.MainLoop()
    loop.run()
```

---

## 5. Developer Lifecycle & Autonomous Agent Tooling

When generating or testing KDE Plasma plugins using an AI coding agent, leverage these CLI tools:

### 5.1 Isolated Widget Testing
```bash
# Preview widget in an isolated window (Panel mode)
plasmoidviewer -a ~/.local/share/plasma/plasmoids/org.myorg.mywidget -f horizontal

# Preview widget in Desktop containment mode
plasmoidviewer -a ~/.local/share/plasma/plasmoids/org.myorg.mywidget -f planar

# Test with DPI scaling (HiDPI validation)
QT_SCALE_FACTOR=2 plasmoidviewer -a ~/.local/share/plasma/plasmoids/org.myorg.mywidget
```

### 5.2 Package Installation & Inspection
```bash
# Install plasmoid for user
kpackagetool6 --type Plasma/Applet --install /path/to/source_dir

# Upgrade existing plasmoid
kpackagetool6 --type Plasma/Applet --upgrade /path/to/source_dir

# List installed applets
kpackagetool6 --type Plasma/Applet --list

# Remove plasmoid
kpackagetool6 --type Plasma/Applet --remove org.myorg.mywidget
```

### 5.3 Live Debugging & Shell Reloading
```bash
# Open interactive KWin/Plasma JavaScript console
plasma-interactive-console --kwin
plasma-interactive-console --plasma

# Tail live QML and shell logs
journalctl -f /usr/bin/plasmashell

# Reload plasmashell in development session (without logging out)
kquitapp6 plasmashell && kstart plasmashell
```

---

## 6. Official Documentation & Authoritative References

* [KDE Plasma Widget Official Tutorial](https://develop.kde.org/docs/plasma/widget/): Complete reference covering setup, properties, configuration panels, and QML types.
* [Porting Plasmoids to KF6](https://develop.kde.org/docs/plasma/widget/porting_kf6/): Mandatory Plasma 6 architectural standards and breaking changes from KF5.
* [Testing Plasmoids Guide](https://develop.kde.org/docs/plasma/widget/testing/): Official guidance on `plasmoidviewer`, scaling factors, and containment flags.
* [KWin Scripting Tutorial](https://develop.kde.org/docs/plasma/kwin/): Comprehensive guide for window management scripts and tiling engines.
* [KWin Scripting API Reference](https://develop.kde.org/docs/plasma/kwin/api/): Full method and signal reference for `workspace` and client window objects.
* [KRunner Metadata & D-Bus Protocol](https://develop.kde.org/docs/plasma/krunner/metadata/): Specification for writing D-Bus search runners.
* [Agundur KDE Plasma 6 Plasmoid Template](https://github.com/Agundur-KDE/KDE-Plasma-Plasmoid-template): Community reference template for automated CMake and pure QML packaging.
* [Omarchy Shell Plugins Documentation](https://omarchy.org/manual/shell-plugins/): Cross-reference architecture documentation for Quickshell in Omarchy.
