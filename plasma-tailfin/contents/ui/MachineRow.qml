import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V8-1.2 MachineRow — Omarchy MachineRow grammar, two-line:
//   [glyph] [name  / "role · ↓rx ↑tx" | "os · offline"] [right rail: copy]
// The v0.7 six-column single-line PeerRow is RETIRED (owner: text cut
// off). Row click → detail (§V7-5 kept). Copy button on the right rail
// shares the rail x with every other control (V8-1.3).
Item {
    id: row

    required property var ctx
    required property var peer
    required property var modelData
    required property int index
    property int focusIndex: -1

    signal activated(var peer)
    signal copyRequested(var peer)

    readonly property bool online: peer.Online === true
    readonly property bool isExitNode: peer.ExitNode === true
    readonly property bool isCandidate:
        online && !isExitNode && peer.ExitNodeOption === true
    readonly property string name: ctx.peerName(peer)
    readonly property bool focused: focusIndex === index

    function osIcon() {
        const key = String(peer.OS || "").toLowerCase()
        if (key === "linux") return "computer"
        if (key === "windows") return "computer-symbolic"
        if (key === "macos") return "computer-apple"
        if (key === "ios") return "smartphone"
        if (key === "android") return "smartphone"
        return "computer"
    }

    function fmtRate(bytesPerSec) {
        const b = Number(bytesPerSec) || 0
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
        if (b >= 1024) return Math.round(b / 1024) + " KB/s"
        return b + " B/s"
    }

    // Omarchy sub line: role first, then live rates; offline wins.
    readonly property string subText: {
        if (!online) {
            const os = String(peer.OS || "")
            return os !== "" ? os.toLowerCase() + " · offline" : "offline"
        }
        const parts = []
        if (isExitNode) parts.push("exit node")
        else if (isCandidate) parts.push("exit option")
        const rm = ctx.rateMap || {}
        const key = String(peer.DNSName || peer.id || "")
        const r = rm[key]
        if (r && (r.rx > 0 || r.tx > 0)) {
            parts.push("↓" + fmtRate(r.rx) + " ↑" + fmtRate(r.tx))
        }
        if (parts.length === 0) {
            const relay = ctx.peerIsDirect(peer) ? "direct" : "relayed"
            parts.push(relay)
        }
        return parts.join(" · ")
    }

    readonly property color mutedColor: Kirigami.Theme.textColor

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.9)

    Rectangle {
        anchors.fill: parent
        visible: rowMouse.containsMouse || row.focused || row.isExitNode
        color: row.focused || row.isExitNode
               ? Kirigami.Theme.highlightColor : Kirigami.Theme.highlightColor
        opacity: row.isExitNode ? 0.10 : rowMouse.containsMouse ? 0.06
                : row.focused ? 0.10 : 0
        radius: Kirigami.Units.smallSpacing
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated(row.peer)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing * 0.5
        anchors.rightMargin: Kirigami.Units.smallSpacing * 0.25
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignVCenter
            source: row.osIcon()
            isMask: true
            color: row.online ? Kirigami.Theme.textColor : row.mutedColor
            opacity: row.online ? 0.9 : 0.45
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PC3.Label {
                Layout.fillWidth: true
                text: row.name
                elide: Text.ElideRight
                color: Kirigami.Theme.textColor
                opacity: row.online ? 1.0 : 0.55
                font.pixelSize: Kirigami.Units.gridUnit * 0.75
                font.bold: row.isExitNode
            }
            PC3.Label {
                Layout.fillWidth: true
                text: row.subText
                elide: Text.ElideRight
                color: row.mutedColor
                opacity: 0.55
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
            }
        }

        // Right rail (§V8-1.3): copy-IP button (Trayscale parity,
        // V8-2 clipboard lane) + detail chevron.
        PC3.ToolButton {
            flat: true
            icon.name: "edit-copy-symbolic"
            display: PC3.AbstractButton.IconOnly
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
            opacity: rowMouse.containsMouse ? 0.85 : 0.45
            QQC2.ToolTip.text: qsTr("Copy address")
            QQC2.ToolTip.visible: hovered
            onClicked: row.copyRequested(row.peer)
        }
        PC3.Label {
            text: "›"
            color: Kirigami.Theme.textColor
            opacity: rowMouse.containsMouse ? 0.8 : 0.35
            font.pixelSize: Kirigami.Units.gridUnit * 1.05
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
