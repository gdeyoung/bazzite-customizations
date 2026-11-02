import QtQuick
import org.kde.kirigami as Kirigami

// Outlined status/category chip: 8px dot + 11px label (spec §B/§D).
// Deliberately dumb — every caller colors its own dot.
Rectangle {
    id: chip

    property string text: ""
    property color dotColor: "transparent"
    property bool showDot: true

    implicitHeight: 18
    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing / 2
    color: "transparent"
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.22)
    border.width: 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing / 2 + 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.showDot
            width: 8
            height: 8
            radius: 4
            color: chip.dotColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: Kirigami.Theme.textColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
        }
    }
}
