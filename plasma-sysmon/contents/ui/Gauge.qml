import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Gauge — labeled horizontal percent gauge for the GPU section (VRAM / GTT).
Item {
    id: g
    property string label: ""
    property real pct: 0
    property color color: "#7aa2f7"

    implicitHeight: Kirigami.Units.gridUnit * 0.9
    Layout.fillWidth: true

    ColumnLayout {
        anchors.fill: parent
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            Text { text: g.label; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
            Item { Layout.fillWidth: true }
            Text { text: Math.round(Math.min(100, Math.max(0, g.pct))) + "%"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1, Math.max(0, g.pct / 100))
                radius: 3
                color: g.color
            }
        }
    }
}
