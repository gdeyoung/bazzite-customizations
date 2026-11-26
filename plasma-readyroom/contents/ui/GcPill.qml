import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Clickable pill / link chip. Takes a `tap` callback PROPERTY instead of an
// onClicked handler so files using many of these never declare the same
// signal handler twice (Plasma fails the whole applet on duplicates).
Item {
    id: root

    property string text: ""
    property string glyph: ""
    property bool active: false
    property bool linkStyle: false          // true = flat link, false = pill
    property var tap: function() {}

    implicitWidth: row.implicitWidth
        + (linkStyle ? 0 : Kirigami.Units.largeSpacing * 2)
    implicitHeight: linkStyle
        ? label.implicitHeight
        : Math.max(Kirigami.Units.gridUnit * 0.8, row.implicitHeight)

    readonly property color fg: active
        ? (linkStyle ? Kirigami.Theme.highlightColor : Kirigami.Theme.highlightColor)
        : (linkStyle ? Kirigami.Theme.linkColor : Kirigami.Theme.textColor)

    Rectangle {
        // Pill background (hidden for links).
        anchors.fill: parent
        visible: !root.linkStyle
        radius: height / 2
        color: root.active
            ? Qt.alpha(Kirigami.Theme.highlightColor, 0.35)
            : Qt.alpha(Kirigami.Theme.textColor, mouse.containsMouse ? 0.14 : 0.08)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Text {
            visible: root.glyph !== ""
            text: root.glyph
            font.family: "Symbols Nerd Font"
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: root.fg
        }

        Text {
            id: label
            text: root.text
            color: root.fg
            font: Kirigami.Theme.smallFont
            font.weight: root.active ? Font.Bold : Font.Normal
            opacity: root.linkStyle || root.active ? 1.0 : 0.85
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tap()
    }
}
