import QtQuick
import org.kde.kirigami as Kirigami

// City search field for the [+] tab. Enter runs the Open-Meteo geocoding
// search through the panel's one-shot dataengine pipeline.
Rectangle {
    id: field
    required property var panel
    property alias searchText: input.text

    signal submitted()

    implicitHeight: Kirigami.Units.gridUnit * 1.9
    implicitWidth: 200

    radius: Kirigami.Units.smallSpacing
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                   Kirigami.Theme.textColor.b, 0.08)
    border.width: 1
    border.color: input.activeFocus ? Kirigami.Theme.textColor
                                    : Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                                              Kirigami.Theme.disabledTextColor.g,
                                              Kirigami.Theme.disabledTextColor.b, 0.6)

    TextInput {
        id: input
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Units.gridUnit * 0.6
        onAccepted: field.submitted()

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !input.text && !input.activeFocus
            text: "Search city, press Enter…"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.6
        }
    }
}
