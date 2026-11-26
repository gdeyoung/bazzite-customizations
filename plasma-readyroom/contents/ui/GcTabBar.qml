import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Pill-style tab bar mirroring the Omarchy ButtonGroup. Per-tab clicks go
// through the `tap` callback property on each pill (this file declares no
// onClicked at all).
RowLayout {
    id: root

    property var tabs: []            // [{value, label}]
    property string value: ""
    signal picked(string tabValue)

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: root.tabs

        GcPill {
            required property var modelData
            Layout.alignment: Qt.AlignVCenter

            text: modelData.label
            active: root.value === modelData.value
            tap: function() { root.picked(modelData.value) }
        }
    }

    Item { Layout.fillWidth: true }
}
