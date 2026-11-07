import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V7-6 picker row — radio + name + ADDRESS/OS/CONN slots on the peer
// row x-axes (§V7-4 geometry reused). Radio at the DOT column. [WIN]
// grammar: selecting an option closes the menu — here: one click fires
// the op, no confirm (§T-4 pinned).
Item {
    id: prow

    required property var ctx
    // Optional peer (None row has none). Present only for hover conn lookups.
    property var peer: null
    property string title: ""
    property string address: ""
    property string osText: ""
    property string conn: ""
    property bool selected: false
    property bool busyTarget: false      // in-flight target row (§T-4)
    property bool interactive: true      // gate-off renders read-only

    signal picked()

    implicitHeight: Math.round(Kirigami.Units.gridUnit * (busyTarget ? 2.72 : 1.85))
    width: Math.round(Kirigami.Units.gridUnit * 32.2)

    MouseArea {
        id: hit
        anchors.fill: parent
        enabled: prow.interactive
        hoverEnabled: prow.interactive
        cursorShape: prow.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: prow.picked()
    }
    // selected tint (§V6-6 grammar kept) then hover on top
    Rectangle {
        anchors.fill: parent
        visible: prow.selected
        color: Kirigami.Theme.highlightColor
        opacity: 0.10
    }
    Rectangle {
        anchors.fill: parent
        visible: hit.containsMouse && prow.interactive
        color: Kirigami.Theme.highlightColor
        opacity: 0.06
    }

    Item {
        anchors.fill: parent
        opacity: prow.interactive ? 1 : 0.62

        // RADIO — 0.5·gu circle in the DOT column
        Item {
            x: 0
            width: Math.round(Kirigami.Units.gridUnit * 0.9)
            height: parent.height
            Rectangle {
                width: Math.round(Kirigami.Units.gridUnit * 0.5)
                height: width
                radius: width / 2
                anchors.centerIn: parent
                border.width: 1
                border.color: prow.selected ? Kirigami.Theme.highlightColor
                                            : Kirigami.Theme.textColor
                color: "transparent"
                Rectangle {
                    visible: prow.selected
                    anchors.centerIn: parent
                    width: parent.width - 4
                    height: width
                    radius: width / 2
                    color: Kirigami.Theme.highlightColor
                }
            }
        }

        // NAME — T2 DemiBold; bold+textColor when selected
        PC3.Label {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(Kirigami.Units.gridUnit * 0.9)
            anchors.right: parent.left
            anchors.rightMargin: Math.round(
                Kirigami.Units.gridUnit * (32.2 - 12.6))
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: prow.title
            color: Kirigami.Theme.textColor
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.72)
            font.weight: prow.selected ? Font.Bold : Font.DemiBold
            elide: Text.ElideRight
        }

        // ADDRESS
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 12.6)
            width: Math.round(Kirigami.Units.gridUnit * 7.2)
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: prow.address
            color: Kirigami.Theme.textColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
        }

        // OS
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 19.8)
            width: Math.round(Kirigami.Units.gridUnit * 2.6)
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: prow.osText
            color: Kirigami.Theme.textColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }

        // CONN
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 22.4)
            width: Math.round(Kirigami.Units.gridUnit * (32.2 - 22.4))
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: prow.conn
            color: Kirigami.Theme.textColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
    }

    // §T-4 in-flight third line on the target row
    PC3.Label {
        anchors.left: parent.left
        anchors.leftMargin: Math.round(Kirigami.Units.gridUnit * 0.9)
        anchors.bottom: parent.bottom
        visible: prow.busyTarget
        text: "switching…"
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    }

    Accessible.role: Accessible.RadioButton
    Accessible.name: title
    HoverHandler { id: rowHover }
    QQC2.ToolTip.text: prow.peer
        ? "use " + prow.ctx.peerName(prow.peer) + " as exit node"
        : "stop using an exit node — go direct"
    QQC2.ToolTip.visible: rowHover.hovered && prow.interactive
}
