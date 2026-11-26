import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One sentence of cause plus one thing to do about it — the shape every
// missing capability takes in this port. Port of ui/GcDegradedRow.qml.
// Height collapses when invisible; the action emits via `tap`.
Rectangle {
    id: root

    property string message: ""
    property string actionText: ""
    property var tap: function() {}

    implicitHeight: visible ? row.implicitHeight + Kirigami.Units.largeSpacing * 2 : 0
    radius: Kirigami.Units.smallSpacing / 2
    color: Qt.alpha(Kirigami.Theme.textColor, 0.06)

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.message
            color: Kirigami.Theme.textColor
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        GcPill {
            visible: root.actionText !== ""
            text: root.actionText
            linkStyle: true
            tap: function() { root.tap() }
        }
    }
}
