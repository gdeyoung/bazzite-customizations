import QtQuick
import org.kde.kirigami as Kirigami

// TimerPill — small bordered text button for the timer controls, ported from
// the Omarchy TimerPill.qml (same idiom: hairline border, hover fill, bold
// caption label). Colors are passed in by the caller (theme tokens from the
// instantiating context — a component file cannot see it).
Rectangle {
    id: pill

    property string label: ""
    property bool prominent: false
    property color foreground
    property color toneColor: foreground
    property bool dimmed: false
    property var run: null
    signal clicked()

    width: pillText.implicitWidth + (prominent ? Kirigami.Units.smallSpacing * 6 : Kirigami.Units.smallSpacing * 4)
    height: Math.max(pillText.implicitHeight + Kirigami.Units.smallSpacing * 2,
        Kirigami.Units.gridUnit * 1.5)
    radius: Kirigami.Units.smallSpacing / 2
    opacity: pill.dimmed ? 0.3 : 1
    border.width: 1
    // Primary verbs read as primary (ux-review-v2 P1-7): prominent = the
    // selected-tab idiom — persistent tone border + tinted fill + tone text,
    // not recolored text alone. Ghost pills stay hover-only.
    border.color: pill.prominent || (!pill.dimmed && pillMouse.containsMouse)
        ? pill.toneColor
        : Qt.alpha(pill.foreground, 0.4)
    color: pill.prominent ? Qt.alpha(pill.toneColor, 0.18)
        : (!pill.dimmed && pillMouse.containsMouse ? Qt.alpha(pill.toneColor, 0.15) : "transparent")

    Text {
        id: pillText
        anchors.centerIn: parent
        text: pill.label
        color: pill.prominent ? pill.toneColor : pill.foreground
        font.bold: true
        font.pixelSize: 11 // fleet micro tier (sysmon v0.8)
        font.letterSpacing: 1
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        enabled: !pill.dimmed
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            pill.clicked()
            if (pill.run) pill.run()
        }
    }
}
