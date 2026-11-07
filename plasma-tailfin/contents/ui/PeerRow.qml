import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "Model.js" as Model

// §W-5 PeerRow — the money row (replaces v0.4 CensusCell + CandidateRow).
// Full-width, one column, 33px (1.85·gu); 41px @ gu=22.
//
//   x=0    ● 6px state dot (positive online / disabled offline)
//   x=14   NAME            T2 (0.72·gu DemiBold), elide-right
//          + trailing badge (ACTIVE EXIT > exit > subnet CIDR) + [use]
//          SUBLINE         T3 textColor @ 0.62, elide-right, tnum
//   in-flight target only: third line `switching…` (+13px, §T-4 transient)
//
// Subline grammar §W-14: <OS> · <ip> · direct|via <relay> [· ↓ rx ↑ tx]
// (online+active) / <OS> · <ip> · last seen <t> (offline). OS renders as
// TEXT — Breeze ships no OS-brand icons and Model.osIcon emits Nerd Font
// codepoints (tofu on stock Bazzite, §R-9 flag 3).
//
// Rows are NON-INTERACTIVE (no hover background, default cursor — nothing
// pretends clickable); the only interactive element is the `use` button on
// candidate rows. Offline rows: whole-row opacity 0.62 (dimmed, not
// hidden — Omarchy law). §W-15.2: the v0.4 `ACTIVE` tag (peer.Active =
// session traffic) is deleted; liveliness lives in ↓/↑ counters.
Item {
    id: row

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    required property var peer
    // Qt6 Repeater over a JS array of OBJECTS exposes no `modelData`
    // unless the delegate declares it required (v0.3 PeerCell law).
    required property var modelData

    readonly property bool online: peer.Online === true
    readonly property bool isExitNode: peer.ExitNode === true
    readonly property bool isCandidate:
        online && !isExitNode && peer.ExitNodeOption === true
    readonly property bool isSwitchTarget:
        ctx.ctlSwitching !== "" && ctx.ctlSwitching === String(peer.DNSName || "")
    readonly property string name: ctx.peerName(peer)
    // Subnet badge only on non-exit peers (candidates' 0.0.0.0/0 is
    // stripped by subnetRoutes; the tautology stays cut, §V-4 ledger #1).
    readonly property var routes:
        (isCandidate || isExitNode) ? [] : (ctx.subnetRoutes(peer) || [])

    // §W-4: muted information is textColor @ 0.62 — NOT disabledTextColor
    // (the measured v0.4 low-contrast defect).
    readonly property color mutedColor: Kirigami.Theme.textColor

    function osToken(os) {
        const key = String(os || "").toLowerCase()
        if (key === "linux") return "linux"
        if (key === "windows") return "windows"
        if (key === "macos") return "macOS"
        if (key === "ios") return "iOS"
        if (key === "android") return "android"
        return ""
    }

    readonly property string subline: {
        const parts = []
        const os = osToken(peer.OS)
        if (os !== "") parts.push(os)
        const ip = String((peer.TailscaleIPs || [])[0] || "")
        if (ip !== "") parts.push(ip)
        if (online) {
            // Admin-console Connection column from local data (§W-5):
            // CurAddr non-empty ⇒ direct; else via <DERP region>.
            if (ctx.peerIsDirect(peer)) {
                parts.push("direct")
            } else {
                const relay = ctx.peerRelay(peer)
                if (relay !== "") parts.push("via " + relay)
            }
            // Counters only while session-active (cumulative counters are
            // meaningless idle noise, §W-5).
            if (peer.Active === true) {
                parts.push("↓ " + Model.fmtBytes(peer.RxBytes || 0)
                           + " ↑ " + Model.fmtBytes(peer.TxBytes || 0))
            }
        } else {
            parts.push("last seen " + Model.fmtLastSeen(peer.LastSeen))
        }
        return parts.join(" · ")
    }

    // Tooltip / Accessible.name (§W-5): full DNSName, both IPs, all
    // routes, last-seen when offline — the census detail that does not
    // fit the row lives here.
    readonly property string fullText: {
        const parts = [String(peer.DNSName || "")]
        const ips = peer.TailscaleIPs || []
        for (let i = 0; i < ips.length; i++) parts.push(String(ips[i]))
        const rts = ctx.subnetRoutes(peer) || []
        if (rts.length > 0) parts.push("routes: " + rts.join(", "))
        if (!online) parts.push("last seen " + Model.fmtLastSeen(peer.LastSeen))
        return parts.filter(function (p) { return p !== "" }).join(" · ")
    }

    // §W-15.8: 400ms flash when THIS row's Online flag flips between
    // ticks (change-blindness rule). Counters never flash. Tracked in a
    // plain property (not a binding) so full-array peer replacement
    // still reads as a flip, not a fresh row.
    property bool _wasOnline: false
    property bool flashing: false
    Component.onCompleted: _wasOnline = row.online
    onPeerChanged: {
        if (peer === null || peer === undefined) return
        if (row.online !== row._wasOnline) {
            row._wasOnline = row.online
            row.flashing = true
            flashTimer.restart()
        }
    }
    Timer {
        id: flashTimer
        interval: 400
        onTriggered: row.flashing = false
    }

    Accessible.name: fullText
    Accessible.role: Accessible.ListItem
    HoverHandler { id: rowHover }
    QQC2.ToolTip.text: fullText
    QQC2.ToolTip.visible: rowHover.hovered

    implicitHeight: Kirigami.Units.gridUnit * (isSwitchTarget ? 2.57 : 1.85)

    // Flash overlay: highlightColor @ 0.25, decayed by the timer.
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.highlightColor
        opacity: row.flashing ? 0.25 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Offline dim (Omarchy: dimmed, not hidden) applies to the whole row
    // content; the flash overlay above stays outside so a flip reads.
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0
        opacity: row.online ? 1 : 0.62

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // State dot column: one x-axis for every row (§W-4).
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.78
                Layout.preferredHeight: 1
                Rectangle {
                    // 6px dot at the column's left edge (x=0).
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.gridUnit * 0.35
                    height: Kirigami.Units.gridUnit * 0.35
                    radius: width / 2
                    color: row.online ? Kirigami.Theme.positiveTextColor
                                      : Kirigami.Theme.disabledTextColor
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                text: row.name
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // Role badge — exactly ONE renders (§W-5 priority order).
            PC3.Label {
                visible: row.isExitNode
                text: "ACTIVE EXIT"
                color: Kirigami.Theme.positiveTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
            }
            PC3.Label {
                visible: row.isCandidate
                text: "exit"
                color: row.mutedColor
                opacity: 0.62
                font: Kirigami.Theme.smallFont
            }
            PC3.Label {
                visible: !row.isCandidate && !row.isExitNode && row.routes.length > 0
                text: row.routes[0] + (row.routes.length > 1
                                      ? " +" + (row.routes.length - 1) : "")
                color: row.mutedColor
                opacity: 0.62
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }

            // §T-4 semantics verbatim, §W-15.3 restyle: single click, no
            // confirm, tooltip teaches, hit ≥ 1.4·gu, hidden on the
            // active-exit row and when the gate is off. Standard
            // (non-flat) PC3.Button — Breeze hover/press/focus/disabled
            // chrome fixes the v0.4 "bare-text use" defect.
            PC3.Button {
                visible: row.isCandidate && row.ctx.controlsEnabled
                enabled: !row.ctx.ctlBusy
                text: i18n("use")
                QQC2.ToolTip.text: "use " + row.name + " as exit node"
                QQC2.ToolTip.visible: hovered
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                topPadding: Kirigami.Units.smallSpacing * 0.5
                bottomPadding: Kirigami.Units.smallSpacing * 0.5
                leftPadding: Kirigami.Units.smallSpacing * 1.5
                rightPadding: Kirigami.Units.smallSpacing * 1.5
                onClicked: row.ctx.runControlOp("exit-set",
                                                String(row.peer.DNSName || ""))
            }
        }

        // Subline — T3 muted 0.62, tnum on the ticking numerics (§W-4).
        // (font members bound individually — whole-object font bind plus
        // a member bind throws at load; SectionLabel law.)
        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 0.78
            text: row.subline
            color: row.mutedColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
        }

        // §T-4 transient: renders only on the in-flight target row.
        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 0.78
            visible: row.isSwitchTarget
            text: "switching…"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
    }
}
