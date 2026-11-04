import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V-4 census section. mode "online": `ONLINE · <N>` label + 2-col grid
// (or `NO ONLINE PEERS` centered when N=0 and offline > 0, or
// `NO PEERS · TAILNET EMPTY` when the tailnet has nothing at all).
// mode "offline": the toggle row `<N> OFFLINE · SHOW/HIDE` in place of a
// label, and the muted 2-col grid renders only while expanded.
// 2-col, row-major, alphabetical; 27 px pitch (1.4·gu + 2).
ColumnLayout {
    id: section

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    required property string mode          // "online" | "offline"
    readonly property bool isOnline: mode === "online"

    property alias expanded: toggleRow.expanded

    spacing: 2

    // ---- Label / toggle row ------------------------------------------
    SectionLabel {
        visible: section.isOnline
        rawText: section.isOnline
            ? ("Online · " + section.ctx.censusPeers.length)
            : ""
    }

    Text {
        // §V-4 census empty states (online mode only). Plain Text:
        // PC3.Label does not expose horizontalAlignment.
        Layout.fillWidth: true
        visible: section.isOnline && section.ctx.censusPeers.length === 0
        text: (section.ctx.offlinePeers.length > 0 || section.ctx.exitNodes.length > 0)
              ? "NO ONLINE PEERS" : "NO PEERS · TAILNET EMPTY"
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        horizontalAlignment: Text.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
    }

    // §V-4 offline toggle — the ONLY interactive element outside the
    // control surface. Show/hide flips this session; showOffline config
    // seeds the default.
    RowLayout {
        id: toggleRow
        visible: !section.isOnline && section.ctx.offlinePeers.length > 0
        Layout.fillWidth: true
        property bool expanded: section.ctx ? section.ctx.showOfflineCfg : false

        PC3.Button {
            flat: true
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            text: section.ctx.offlinePeers.length + " OFFLINE · "
                  + (toggleRow.expanded ? "HIDE" : "SHOW")
            onClicked: toggleRow.expanded = !toggleRow.expanded
        }
    }

    // ---- 2-col grid ---------------------------------------------------
    GridLayout {
        visible: section.isOnline || toggleRow.expanded
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 2

        Repeater {
            model: section.isOnline ? section.ctx.censusPeers
                                    : (toggleRow.expanded ? section.ctx.offlinePeers
                                                          : [])
            CensusCell {
                Layout.fillWidth: true
                ctx: section.ctx
                peer: modelData
                online: section.isOnline
            }
        }
    }
}
