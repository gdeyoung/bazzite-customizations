import QtQuick
import org.kde.kirigami as Kirigami

// Small clickable text/glyph (＋ add tab, ⟳ refresh, Radar ↗, ✕ close,
// ⚙ configure). The MouseArea lives in this file so the popup never needs
// more than its single handler budget of onClicked per file.
Item {
    id: chip
    property var trigger: null
    property string label: ""
    property bool emphasize: false
    property bool round: true

    implicitWidth: Math.max(labelRow.implicitWidth + Kirigami.Units.largeSpacing * 2,
                            round ? Kirigami.Units.gridUnit * 1.55 : 0)
    implicitHeight: Kirigami.Units.gridUnit * 1.55

    Rectangle {
        anchors.fill: parent
        radius: chip.round ? height / 2 : Kirigami.Units.smallSpacing
        color: chip.emphasize ? Kirigami.Theme.textColor : "transparent"
        border.width: 1
        border.color: chip.emphasize ? Kirigami.Theme.textColor
                                     : (ma.containsMouse ? Kirigami.Theme.textColor
                                                         : Kirigami.Theme.disabledTextColor)
        opacity: chip.emphasize || ma.containsMouse ? 1.0 : 0.75

        Text {
            id: labelRow
            anchors.centerIn: parent
            text: chip.label
            color: chip.emphasize ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.trigger ? chip.trigger() : null
    }
}
