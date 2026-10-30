import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// HwRow — label/value hardware row (v0.7: micro-caps label at fixed 84px so
// values align in columns; body-tier value, elided).
RowLayout {
    id: hwRow
    property string label: ""
    property string value: ""
    property bool show: true
    visible: show
    spacing: 8
    Layout.fillWidth: true

    Text {
        text: hwRow.label
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        Layout.preferredWidth: 84
    }
    Text {
        text: hwRow.value
        textFormat: Text.PlainText
        color: Kirigami.Theme.textColor
        font.pixelSize: 11
        elide: Text.ElideRight
        Layout.fillWidth: true
    }
}
