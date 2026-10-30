import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// SectionCard — flat card atom: white 4% fill, radius 8, 12px padding,
// micro-caps title + right value in the header, body content below.
// Default children are re-parented into the body column.
Rectangle {
    id: card
    default property alias content: body.data
    property string title: ""
    property string rightText: ""

    radius: 8
    color: Qt.alpha(Kirigami.Theme.textColor, 0.04)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: card.title
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 10
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: card.rightText !== ""
                text: card.rightText
                color: Kirigami.Theme.textColor
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
        }
    }
}
