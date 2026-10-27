import QtQuick
import org.kde.kirigami as Kirigami

// One location tab chip: Here + pinned places. Active pinned chip gets an ✕
// hint — clicking an already-active pinned tab removes it (as upstream).
Item {
    id: chip
    required property var panel
    required property var tab
    required property bool isActive

    signal chosen()

    implicitWidth: chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
    implicitHeight: Kirigami.Units.gridUnit * 1.55

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: chip.isActive ? Kirigami.Theme.textColor : "transparent"
        border.width: 1
        border.color: chip.isActive ? Kirigami.Theme.textColor
                                    : Kirigami.Theme.disabledTextColor
        opacity: ma.containsMouse ? 1.0 : 0.7

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: chip.tab ? chip.tab.name : ""
                color: chip.isActive ? Kirigami.Theme.backgroundColor
                                     : Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
                font.bold: chip.isActive
            }
            Text {
                visible: chip.tab && chip.tab.pinned && chip.isActive
                text: "✕"
                color: Kirigami.Theme.backgroundColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.chosen()
    }
}
