import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// A bordered action button (PC3.Button underneath, so keyboard focus and
// activation come for free). Emits via the `tap` callback property.
PC3.Button {
    id: root

    property string glyph: ""
    property var tap: function() {}

    flat: true
    font: Kirigami.Theme.smallFont

    // PC3 emits clicked(); we forward once (single handler per file).
    onClicked: root.tap()

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Text {
            visible: root.glyph !== ""
            text: root.glyph
            font.family: "Symbols Nerd Font"
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.textColor
            Layout.alignment: Qt.AlignVCenter
        }
        PC3.Label {
            text: root.text
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.textColor
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
