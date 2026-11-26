/*
 * Porting template — Plasma 6 panel widget skeleton.
 * Ported from a Quickshell (Omarchy) BarWidget: keep the JS models and probe
 * scripts verbatim; rewrite ONLY the container layer per the rules below.
 *
 * HARD RULES (each one cost a failed attempt — see the skill):
 *  - Root is PlasmoidItem; compactRepresentation and fullRepresentation are
 *    DIRECT children. `Plasmoid.configuration` holds settings (KConfig XT).
 *  - Executable dataengine: import org.kde.plasma.plasma5support 2.0 —
 *    UNALIASED, versioned. DataSource with the command in connectedSources
 *    and `interval` set; the engine re-runs on the tick.
 *  - onNewData uses formal params: (sourceName, data) => { ... }
 *    NEVER gate on `sourceName in connectedSources` — JS `in` over an ARRAY
 *    tests indices, always false, every payload silently dropped.
 *  - One handler per signal per file (no second onChanged later in the file).
 *  - No hardcoded colors — PlasmaCore.Theme / Kirigami.Theme tokens only.
 *  - Popup self-sizes: Layout.preferredHeight bound to content implicitHeight;
 *    a plain StackLayout sizes to its TALLEST child (override height if tabs).
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.ksvg as KSvg  // frame SVGs (PanelSvgItem lives here, not PlasmaCore)

PlasmoidItem {
    id: root

    // ---- live data: probe runs every `interval` ms, emits one JSON line ----
    DataSource {
        id: probe
        engine: "executable"
        connectedSources: [Qt.resolvedUrl("../scripts/example-probe.sh").toString()
                           .replace("file://", "")]
        interval: 2000
        // Heartbeat side-channel: on successful parse write /tmp/<id>-hb.json.
        // If that file advances, the whole chain works (categorized logging
        // hides console.log, so this is the primary runtime evidence).
        onNewData: (sourceName, data) => {
            const out = data["exit code"] === 0 ? data["stdout"] : "";
            try {
                window.json = JSON.parse(out.trim().split("\n").pop());
                hb.text = JSON.stringify({t: Date.now(),
                                          sample: window.json.value});
                hbWrite.connectedSources = ["echo -n " + "'" + hb.text + "' > /tmp/" + plasmoidId + "-hb.json"];
                hbWrite.connectedSources = [];
            } catch (e) { /* drop bad tick silently — validate the probe itself */ }
        }
    }
    DataSource {
        id: hbWrite   // fire-once helper for the heartbeat file
        engine: "executable"
        interval: 0
    }

    property string plasmoidId: "template"

    // ---- panel form ----
    compactRepresentation: PC3.ItemDelegate {
        id: compact
        Layout.minimumWidth: row.implicitWidth + 2 * KirigamiUnits
        Layout.minimumHeight: row.implicitHeight
        readonly property int KirigamiUnits: 4
        contentItem: RowLayout {
            id: row
            spacing: 4
            Text {
                text: "◈"                       // glyph, as in the Omarchy widget
                color: PlasmaTheme.textColor    // theme tokens only
                font.pixelSize: 14
            }
            PC3.Label {
                text: window.json ? String(window.json.value) : "…"
                font.pixelSize: 12
            }
        }
        MouseArea {
            // PlasmoidItem forwards clicks; this expands the popup
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ---- popup form (self-sizing, no scrollbars) ----
    fullRepresentation: Item {
        Layout.preferredWidth: 320
        Layout.preferredHeight: col.implicitHeight + 16
        Layout.minimumHeight: 120
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            PC3.Label { text: "Title"; font.bold: true }
            PC3.Label {
                text: window.json ? JSON.stringify(window.json, null, 1) : "waiting…"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    // window-scoped state (single source of truth for both representations)
    Item {
        id: window
        property var json: null
    }
}
