import QtQuick
import org.kde.kirigami as Kirigami

// One geocoding search result: name + region · country. Click pins the place.
Rectangle {
    id: row
    required property var ctx
    required property var modelData
    required property var place

    signal picked()

    width: parent ? parent.width : 200
    implicitHeight: Kirigami.Units.gridUnit * 1.9
    radius: Kirigami.Units.smallSpacing
    color: ma.containsMouse
        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                  Kirigami.Theme.textColor.b, 0.12)
        : "transparent"

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.largeSpacing
        text: row.place
            ? row.place.name + "  ·  "
              + [row.place.admin1, row.place.country_code].filter(Boolean).join(" · ")
            : ""
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Units.gridUnit * 0.58 * ctx.scaleF
        elide: Text.ElideRight
        width: parent.width - Kirigami.Units.largeSpacing * 2
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
    }
}
