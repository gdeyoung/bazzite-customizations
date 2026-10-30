import QtQuick
import org.kde.kirigami as Kirigami

// TempPill — header temperature chip (white 4% fill, micro-caps label,
// tnum value colored by threshold: >=85 crit, >=70 warn).
Rectangle {
    id: pill
    property string label: ""
    property real temp: -1
    readonly property color cWarn: "#e5c07b"
    readonly property color cCrit: "#f4405c"

    visible: temp >= 0
    radius: height / 2
    implicitWidth: row.implicitWidth + 12
    implicitHeight: 20
    color: Qt.alpha(Kirigami.Theme.textColor, 0.04)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 10
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(pill.temp) + "\u00B0"
            color: pill.temp >= 85 ? pill.cCrit : (pill.temp >= 70 ? pill.cWarn : Kirigami.Theme.textColor)
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
        }
    }
}
