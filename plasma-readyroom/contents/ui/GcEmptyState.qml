import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// An empty state that says what is true and what to do about it.
// Port of ui/GcEmptyState.qml.
ColumnLayout {
    id: root

    property string glyph: ""
    property string title: ""
    property string detail: ""

    spacing: Kirigami.Units.smallSpacing

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.glyph
        color: Kirigami.Theme.textColor
        opacity: 0.35
        font.family: "Symbols Nerd Font"
        font.pixelSize: Kirigami.Units.gridUnit * 1.6
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.title
        color: Kirigami.Theme.textColor
        font: Kirigami.Theme.defaultFont
    }

    Text {
        Layout.fillWidth: true
        visible: root.detail !== ""
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.detail
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
    }
}
