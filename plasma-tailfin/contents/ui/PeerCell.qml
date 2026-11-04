import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Control.js" as Control
import "Model.js" as Model

// §R-4 peer cell — one grid cell, online or muted-offline variant.
// Base height 1.5·gu (fit-budget row height); grows only for the
// transient §T-4 "switching…" line on the in-flight target cell.
Item {
    id: cell

    required property var peer
    required property var ctx

    readonly property bool offline: !peer.Online
    readonly property var rawPeer: ctx.rawPeers[String(peer && peer.id)] || {}
    readonly property var routes: ctx.subnetRoutes(peer)
    readonly property bool isSwitchTarget: ctx.ctlSwitching !== ""
        && Control.exitTarget(peer) === ctx.ctlSwitching

    // Line 2 grammar (§R-7, joiner " · "): online = ip · dns [ · routes];
    // offline = ip · last seen <x> | never seen. Full string in tooltip.
    readonly property string line2: {
        const parts = []
        const ips = (peer && peer.TailscaleIPs) || []
        if (ips.length > 0) parts.push(String(ips[0]))
        if (offline) {
            const lastSeen = Model.fmtLastSeen(peer.LastSeen)
            parts.push(lastSeen === "never" ? "never seen" : "last seen " + lastSeen)
        } else {
            const dns = String((peer && peer.DNSName) || "")
            if (dns !== "") parts.push(dns)
            if (routes.length > 0) parts.push(routes.join(", "))
        }
        return parts.join(" · ")
    }

    // Spec §R-4: cell is 1.5·gu tall, PERIOD — content elides/clips to
    // fit; only the transient §T-4 "switching…" line may extend it (and
    // that state auto-clears). Never take Math.max with content height:
    // implicit two-line content ≈ 61 px and silently halves capacity.
    implicitHeight: Kirigami.Units.gridUnit * 1.5
        + (cell.isSwitchTarget ? Kirigami.Units.gridUnit * 0.75 : 0)
    clip: true

    ColumnLayout {
        id: cellCol
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // State dot (§R-4): 0.35·gu circle, token colors only.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.gridUnit * 0.35
                implicitHeight: Kirigami.Units.gridUnit * 0.35
                radius: width / 2
                color: cell.offline ? Kirigami.Theme.disabledTextColor
                                    : Kirigami.Theme.positiveTextColor
                opacity: cell.offline ? 0.6 : 1.0
            }

            Text {
                Layout.fillWidth: true
                text: ctx.peerName(cell.peer)
                color: cell.offline ? Kirigami.Theme.disabledTextColor
                                    : Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.62
                elide: Text.ElideRight
            }

            // Right-aligned muted tags, fixed order: ACTIVE then exit
            // (§R-7 — "exit" stays lowercase per §T-9-as-shipped).
            Text {
                visible: cell.peer.Active === true && !cell.offline
                text: "ACTIVE"
                color: Kirigami.Theme.neutralTextColor
                font: Kirigami.Theme.smallFont
            }
            Text {
                visible: cell.peer.ExitNode === true
                text: "exit"
                color: Kirigami.Theme.neutralTextColor
                font: Kirigami.Theme.smallFont
            }

            // §T-4 use-as-exit — candidates only, hidden on the active
            // exit node and whenever the operator gate is disabled.
            PC3.ToolButton {
                visible: ctx.controlsEnabled
                         && !cell.peer.ExitNode
                         && Control.isExitCandidate(cell.peer, cell.rawPeer)
                enabled: !ctx.ctlBusy
                flat: true
                text: "use"
                QQC2.ToolTip.text: "use " + ctx.peerName(cell.peer) + " as exit node"
                QQC2.ToolTip.visible: hovered
                leftPadding: Kirigami.Units.smallSpacing * 1.5
                rightPadding: Kirigami.Units.smallSpacing * 1.5
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onClicked: ctx.runControlOp(
                    "exit-set", Control.exitTarget(cell.peer))
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: cell.line2
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideMiddle
            QQC2.ToolTip.text: cell.line2
            // Labels are not Controls: `hovered` doesn't exist here and
            // throws ReferenceError on the live host the moment the
            // tooltip binding evaluates (harness shots never hover, so
            // only the live journal sees it).
            QQC2.ToolTip.visible: line2Hover.hovered
            HoverHandler { id: line2Hover }
        }

        // §T-4 transient in-flight marker, target cell only.
        PC3.Label {
            Layout.fillWidth: true
            visible: cell.isSwitchTarget
            text: "switching…"
            color: Kirigami.Theme.neutralTextColor
            font: Kirigami.Theme.smallFont
        }
    }
}
