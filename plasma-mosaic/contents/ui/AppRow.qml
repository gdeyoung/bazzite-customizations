import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Overview app row, 36px (spec §D): icon 20 · name · stacked category bar
// 120x8 (scaled so the LARGEST app fills the track) · bytes (tabular, right)
// · status dot. Row click / Enter opens App detail. Kept flat — no Loaders.
Item {
    id: row

    required property var app
    required property real maxBytes      // global max across the full list
    readonly property bool isCurrent: ListView.isCurrentItem

    signal activated()

    width: ListView.view ? ListView.view.width : 0
    height: 36
    implicitHeight: 36

    Accessible.role: Accessible.ListItem
    Accessible.name: (app ? app.name : "") + ", " +
        MosaicStore.appSizeText(app) + ", " + MosaicStore.statusLabel(app ? app.status : "")

    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            row.forceActiveFocus()
            row.activated()
        }
    }

    // Kirigami-style focus ring + hover wash
    Rectangle {
        anchors.fill: parent
        visible: row.activeFocus
        color: "transparent"
        border.color: Kirigami.Theme.highlightColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing / 2
    }
    Rectangle {
        anchors.fill: parent
        visible: tap.containsMouse && !row.activeFocus
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.06)
    }
    // hairline under every row (Google-Finance pattern)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.12)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            source: row.app && row.app.icon ? row.app.icon : "application-x-executable"
            isMask: false
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 80
            text: row.app ? row.app.name : ""
            color: Kirigami.Theme.textColor
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        // stacked category bar — x-proportional segments of this app's
        // config/data/cache/state bytes, largest app fills the track
        Item {
            Layout.preferredWidth: 120
            Layout.preferredHeight: 8
            Layout.alignment: Qt.AlignVCenter

            Rectangle { // track
                anchors.fill: parent
                radius: 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.10)
            }
            Repeater {
                model: row.app ? MosaicStore.barSegments(row.app, row.maxBytes) : []
                Rectangle {
                    x: modelData.x
                    y: 0
                    width: modelData.w
                    height: 8
                    radius: 2
                    color: modelData.color
                }
            }
        }

        Text {
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignRight
            text: MosaicStore.appSizeText(row.app)
            color: Kirigami.Theme.textColor
            font.pixelSize: 13
        }
        Rectangle {
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: MosaicStore.statusColor(row.app ? row.app.status : "")
        }
    }

    Keys.onReturnPressed: row.activated()
    Keys.onEnterPressed: row.activated()
}
