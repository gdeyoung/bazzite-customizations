import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V8-1.2 picker row — Omarchy ExitNodeRow grammar, two-line:
//   [radio] [name / "address · os · conn" sub]  (selected = tinted card)
// The v0.7 four-column single-line row is retired (owner: text cut
// off). One click fires the op, no confirm (§T-4 pinned).
Item {
    id: prow

    required property var ctx
    property var peer: null
    property string title: ""
    property string address: ""
    property string osText: ""
    property string conn: ""
    property bool selected: false
    property bool busyTarget: false
    property bool interactive: true

    signal picked()

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.6)

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
        radius: Kirigami.Units.smallSpacing
    }
    Rectangle {
        anchors.fill: parent
        visible: hit.containsMouse && prow.interactive
        color: Kirigami.Theme.highlightColor
        opacity: 0.06
        radius: Kirigami.Units.smallSpacing
    }

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.9
            Layout.fillHeight: true
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PC3.Label {
                Layout.fillWidth: true
                text: prow.title
                color: Kirigami.Theme.textColor
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.75)
                font.weight: prow.selected ? Font.Bold : Font.DemiBold
                elide: Text.ElideRight
            }
            PC3.Label {
                Layout.fillWidth: true
                text: [prow.address, prow.osText, prow.conn]
                        .filter(function (p) { return p !== "" })
                        .join(" · ")
                      + (prow.busyTarget ? "  ·  switching…" : "")
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
            }
        }

        Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 0.5 }
    }

    Accessible.role: Accessible.RadioButton
    Accessible.name: title
    HoverHandler { id: rowHover }
    QQC2.ToolTip.text: prow.peer
        ? "use " + prow.ctx.peerName(prow.peer) + " as exit node"
        : "stop using an exit node — go direct"
    QQC2.ToolTip.visible: rowHover.hovered && prow.interactive
}
