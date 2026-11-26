import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// Compact panel chip (spec §C): mosaic glyph + mapped total. Four states:
// never scanned (glyph + "not scanned"), idle (total), scanning (spinner,
// total dims to 60% and keeps its last value), error (red status dot on the
// glyph, total keeps last-good value). Owns its click: toggles the popup.
Item {
    id: chip

    property var applet                        // the PlasmoidItem root (main.qml)
    readonly property bool everScanned: MosaicStore.hasSnapshot
    readonly property string totalText: everScanned && MosaicStore.snapshot.summary
        ? MosaicStore.formatBytes(MosaicStore.snapshot.summary.bytes,
                                  MosaicStore.snapshot.meta && MosaicStore.snapshot.meta.limited)
        : ""
    readonly property bool scanning: MosaicStore.scanState === "running"

    // MEASURE the widest lockup (fleet rule) — total column worst case and the
    // not-scanned caption — so the click cell never shrinks under content.
    TextMetrics {
        id: tmTotal
        font.pixelSize: 12
        text: "\u2265 888.8 TB"
    }
    TextMetrics {
        id: tmEmpty
        font.pixelSize: 11
        font.letterSpacing: 0.4
        text: "not scanned"
    }
    readonly property real cellW: Math.max(48,
        8 + 16 + 6 + Math.max(tmTotal.width, tmEmpty.width) + 10)

    width: cellW
    implicitWidth: cellW
    Layout.preferredWidth: cellW
    Layout.minimumWidth: 48
    Layout.fillHeight: true

    MouseArea {
        id: click
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (chip.applet) chip.applet.expanded = !chip.applet.expanded
    }

    Row {
        anchors.centerIn: parent
        spacing: 6

        Item {
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter

            PC3.BusyIndicator {
                anchors.centerIn: parent
                visible: chip.scanning
                running: chip.scanning
                width: 14
                height: 14
            }
            Image {
                anchors.centerIn: parent
                visible: !chip.scanning
                width: 16
                height: 16
                source: Qt.resolvedUrl("../icons/mosaic.svg")
                sourceSize.width: 16
                sourceSize.height: 16
            }
            // error: 3px red dot on the glyph's bottom-right corner
            Rectangle {
                visible: MosaicStore.scanState === "error"
                x: parent.width - 3
                y: parent.height - 3
                width: 6
                height: 6
                radius: 3
                color: "#f4405c"
                border.color: Kirigami.Theme.backgroundColor
                border.width: 1
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !chip.everScanned && !chip.scanning
            text: "not scanned"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
            elide: Text.ElideRight
            width: Math.min(tmEmpty.width, chip.width - 30)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.everScanned
            text: chip.totalText
            opacity: chip.scanning ? 0.6 : 1.0
            color: Kirigami.Theme.textColor
            font.pixelSize: 12
        }
    }
}
