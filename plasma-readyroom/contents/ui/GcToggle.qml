import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Toggle row: label + honest sub-label + drawn switch. Emits via the `tap`
// callback property (no onClicked here) so parents stay duplicate-handler-free.
ColumnLayout {
    id: root

    property string label: ""
    property string description: ""
    property bool checked: false
    property var tap: function() {}

    spacing: Kirigami.Units.smallSpacing / 2

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            Layout.fillWidth: true
            text: root.label
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
        }

        Rectangle {
            id: switchPill
            readonly property bool on: root.checked
            implicitWidth: Kirigami.Units.gridUnit * 1.6
            implicitHeight: Kirigami.Units.gridUnit * 0.75
            radius: height / 2
            color: on ? Kirigami.Theme.highlightColor
                      : Qt.alpha(Kirigami.Theme.textColor, 0.25)

            Rectangle {
                readonly property real m: Kirigami.Units.smallSpacing * 0.35
                x: switchPill.on ? parent.width - width - m : m
                y: m
                width: parent.height - 2 * m
                height: width
                radius: width / 2
                color: Kirigami.Theme.backgroundColor
                Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tap()
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.description !== ""
        wrapMode: Text.WordWrap
        text: root.description
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
    }
}
