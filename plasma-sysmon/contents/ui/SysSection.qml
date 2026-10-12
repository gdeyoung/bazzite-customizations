import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// SysSection — collapsible panel section. Header row (title, right-aligned
// summary, chevron); children below when expanded. The default slot holds
// the section body. Ported from gdeyoung/omarchy-sysmon; Style.* tokens
// swapped for Kirigami theme tokens.
ColumnLayout {
    id: sec
    property string title: ""
    property string summary: ""
    property bool expanded: true
    default property alias body: bodyHolder.children

    spacing: Kirigami.Units.smallSpacing

    function toggle() { sec.expanded = !sec.expanded }

    Rectangle {
        id: headerBg
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.smallSpacing / 2
        color: headerMouse.containsMouse
            ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.4)
            : Kirigami.Theme.backgroundColor

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sec.toggle()
            hoverEnabled: true
        }

        RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing * 2

            Text {
                text: sec.title
                color: Kirigami.Theme.textColor
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                // Summary can carry DMI-derived strings — force plain text.
                text: sec.summary
                textFormat: Text.PlainText
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
            Text {
                text: sec.expanded ? "▾" : "▸"
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
        }
    }

    ColumnLayout {
        id: bodyHolder
        visible: sec.expanded
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
    }
}
