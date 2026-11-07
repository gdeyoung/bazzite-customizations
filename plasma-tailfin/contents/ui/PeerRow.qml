import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "Model.js" as Model

// §V6-2 PeerRow — the slot grid (v0.6 rewrite of the §W-5 money row).
// The row is no longer prose: every attribute lands in a reserved slot
// with a hard x-axis, so a column can be read top-to-bottom (§V6-1).
//
//   LINE 1  ● STATUS dot · NAME (IDENTITY) · ROUTE chip · ROLE · ACTION
//   LINE 2  OS+CONN · ADDRESS (right edge x310-rel) · TRAFFIC (x579-rel)
//
// Height FIXED at 2.0·gu (36px @gu18) — no content-driven height, ever;
// lane spacing 0 ⇒ row pitch is exactly 2.0·gu (kills the 32–40px jitter
// measured in the v0.5 audit, B1). Offline rows: identical slots,
// whole-row content opacity 0.62 (Omarchy dimmed-not-hidden law).
// Active exit = a state of THIS row: highlightColor tint @0.12 + ROLE
// badge `EXIT NODE` + `stop` button (§V6-6). Rows non-interactive at
// rest; the one sanctioned exception is search-focus mode (§V6-11).
Item {
    id: row

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    required property var peer
    // Qt6 Repeater over a JS array of OBJECTS exposes no `modelData`
    // unless the delegate declares it required (v0.3 PeerCell law).
    required property var modelData

    // §V6-11 search-focus mode: index within the visible result list,
    // or -1 when no row is focused. Owned by PopupShell.
    property int focusIndex: -1
    // Qt6 required-properties mode: declaring modelData required removes
    // the context-property fallbacks, so index must be declared too.
    required property int index
    readonly property int myIndex: index

    readonly property bool online: peer.Online === true
    readonly property bool isExitNode: peer.ExitNode === true
    readonly property bool isCandidate:
        online && !isExitNode && peer.ExitNodeOption === true
    readonly property bool isSwitchTarget:
        ctx.ctlSwitching !== "" && ctx.ctlSwitching === String(peer.DNSName || "")
    readonly property string name: ctx.peerName(peer)
    // Route chip only on non-exit peers (candidates' 0.0.0.0/0 stays cut,
    // §V-4 ledger #1). Survives offline (§W-10).
    readonly property var routes:
        (isCandidate || isExitNode) ? [] : (ctx.subnetRoutes(peer) || [])
    // §V6-19 route-warning row marking (display-only heuristic).
    readonly property bool routeWarned: {
        const warns = ctx.health || []
        for (let i = 0; i < warns.length; i++) {
            if (String(warns[i]).toLowerCase().indexOf("route") >= 0) return true
        }
        return false
    }

    // §W-4: muted information is textColor @ 0.62 — NOT disabledTextColor.
    readonly property color mutedColor: Kirigami.Theme.textColor

    function osToken(os) {
        // §V6-3: brand case, consistently (audit P2).
        const key = String(os || "").toLowerCase()
        if (key === "linux") return "Linux"
        if (key === "windows") return "Windows"
        if (key === "macos") return "macOS"
        if (key === "ios") return "iOS"
        if (key === "android") return "Android"
        return ""
    }

    // §V6-3 display transform: relative only. Model.fmtLastSeen is
    // test-pinned and ISOs past 30d — map the ISO branch to `Nd` / `>1y`
    // here (Model.js untouched; the absolute datetime lives in tooltip).
    function displayLastSeen(iso) {
        const rel = Model.fmtLastSeen(iso)
        if (rel.indexOf("-") !== 4) return rel
        const t = Date.parse(String(iso || ""))
        if (isNaN(t)) return rel
        const days = Math.floor((Date.now() - t) / 86400000)
        return days >= 365 ? ">1y" : days + "d"
    }

    // ---- LINE 2 slot strings (§V6-3 grammar) -------------------------
    readonly property string osConn: {
        const os = osToken(peer.OS)
        if (!online) return os === "" ? "" : os + " · offline"
        if (ctx.peerIsDirect(peer)) return os === "" ? "direct" : os + " · direct"
        const relay = ctx.peerRelay(peer)
        if (relay !== "") {
            const head = os === "" ? "" : os + " · "
            return head + "relay · " + relay
        }
        return os
    }
    readonly property string address:
        String((peer.TailscaleIPs || [])[0] || "")
    readonly property string trafficText: {
        if (!online) return "last seen " + displayLastSeen(peer.LastSeen)
        if (peer.Active === true) {
            return "↓ " + Model.fmtBytes(peer.RxBytes || 0)
                   + " · ↑ " + Model.fmtBytes(peer.TxBytes || 0)
        }
        return "idle"
    }

    // §V6-10 matched-character bolding (search mode): greedy in-order
    // token walk over NAME — the same subsequence shape the engine
    // performs, re-derived for display only. Never bolds a span that
    // didn't match; HTML-escapes NAME before injecting <b>.
    readonly property string nameMarkup: {
        const q = String(ctx.peerQuery || "")
        if (q === "") return ""
        const esc = row.name.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                             .replace(/>/g, "&gt;")
        const marks = new Array(esc.length).fill(false)
        let pos = 0
        const tokens = q.toLowerCase().split(/\s+/).filter(function (t) {
            return t !== ""
        })
        const lower = esc.toLowerCase()
        for (let ti = 0; ti < tokens.length; ti++) {
            const tok = tokens[ti]
            for (let ci = 0; ci < tok.length; ci++) {
                const found = lower.indexOf(tok[ci], pos)
                if (found < 0) return ""   // token not walkable in NAME: bold nothing
                marks[found] = true
                pos = found + 1
            }
        }
        let out = ""
        let inBold = false
        for (let i = 0; i < marks.length; i++) {
            if (marks[i] !== inBold) {
                out += marks[i] ? "<b>" : "</b>"
                inBold = marks[i]
            }
            out += esc[i]
        }
        if (inBold) out += "</b>"
        return out
    }

    // Tooltip / Accessible.name (§W-5): full DNSName, both IPs, all
    // routes, absolute last-seen when offline — census detail lives here.
    readonly property string fullText: {
        const parts = [String(peer.DNSName || "")]
        const ips = peer.TailscaleIPs || []
        for (let i = 0; i < ips.length; i++) parts.push(String(ips[i]))
        if (ctx.peerIsDirect && !ctx.peerIsDirect(peer) && online) {
            const relay = ctx.peerRelay(peer)
            if (relay !== "") parts.push("relayed via DERP " + relay)
        }
        const rts = ctx.subnetRoutes(peer) || []
        if (rts.length > 0) parts.push("routes: " + rts.join(", "))
        if (!online) {
            parts.push("last seen "
                       + new Date(peer.LastSeen || 0).toLocaleString(Qt.locale()))
        }
        return parts.filter(function (p) { return p !== "" }).join(" · ")
    }

    // §W-15.8: 400ms flash when THIS row's Online flag flips between
    // ticks. Tracked in a plain property so full-array peer replacement
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

    // §V6-2: fixed heights. Switch-target row grows transiently (§T-4).
    implicitHeight: Kirigami.Units.gridUnit * (isSwitchTarget ? 2.72 : 2.0)

    // Layer order (§V6-6): flash > tint > content.
    // §V6-6 active-exit whole-row tint — the one tinted row in the list.
    Rectangle {
        anchors.fill: parent
        visible: row.isExitNode
        color: Kirigami.Theme.highlightColor
        opacity: 0.12
    }

    // §V6-11 search-focus row background (the one sanctioned interactive
    // row state; highlightColor @0.08).
    Rectangle {
        anchors.fill: parent
        visible: row.focusIndex === row.myIndex && row.focusIndex >= 0
        color: Kirigami.Theme.highlightColor
        opacity: 0.08
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }

    // Offline dim applies to the whole row content (flash/tint stay
    // outside so a flip or tint reads at full strength).
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0
        opacity: row.online ? 1 : 0.62

        // ---- LINE 1: STATUS · IDENTITY · ROUTE · ROLE · ACTION ------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.95
            spacing: Kirigami.Units.smallSpacing * 0.5

            // STATUS slot — 0.9·gu column, 6px dot at x0 (§V6-1 axis 4).
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.9
                Layout.preferredHeight: 1
                Rectangle {
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.gridUnit * 0.35
                    height: Kirigami.Units.gridUnit * 0.35
                    radius: width / 2
                    color: row.online ? Kirigami.Theme.positiveTextColor
                                      : Kirigami.Theme.disabledTextColor
                }
            }

            // IDENTITY — T2 DemiBold, elide; rich-text bold marks in
            // search mode (§V6-10; never widens the slot).
            PC3.Label {
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                textFormat: row.nameMarkup !== ""
                            ? Text.StyledText : Text.AutoText
                text: row.nameMarkup !== "" ? row.nameMarkup : row.name
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // ROUTE slot (6.8·gu, right-aligned, elide-left keeps the
            // mask; §V6-19 ⚠ marks route advertisers during route-class
            // health warnings).
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6.8
                Layout.preferredHeight: 1
                visible: true
                RowLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing * 0.5
                    Text {
                        visible: row.routeWarned
                                 && row.ctx.subnetRoutes(row.peer).length > 0
                        text: "⚠"
                        color: Kirigami.Theme.neutralTextColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.6
                        QQC2.ToolTip.text: "route-related health warning · see popup top"
                        QQC2.ToolTip.visible: rwarnHover.hovered
                        HoverHandler { id: rwarnHover }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: row.routes.length > 0
                        horizontalAlignment: Text.AlignRight
                        text: row.routes[0] + (row.routes.length > 1
                                              ? " +" + (row.routes.length - 1) : "")
                        color: row.mutedColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideLeft
                    }
                }
            }

            // ROLE slot (5.2·gu, right-aligned): vpn icon + EXIT NODE on
            // the active row (bold textColor — §V6-6, never green or
            // highlight-as-text) / muted `exit` on candidates (§W-10:
            // role survives offline, never a use button).
            RowLayout {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5.2
                spacing: Kirigami.Units.smallSpacing * 0.5
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 0.7
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.7
                    visible: row.isExitNode || row.isCandidate
                    source: "network-vpn"
                    isMask: true
                    color: row.isExitNode ? Kirigami.Theme.highlightColor
                                          : Kirigami.Theme.textColor
                    opacity: row.isExitNode ? 1 : 0.62
                }
                PC3.Label {
                    Layout.fillWidth: true
                    visible: row.isExitNode
                    horizontalAlignment: Text.AlignRight
                    text: "EXIT NODE"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                }
                PC3.Label {
                    Layout.fillWidth: true
                    visible: row.isCandidate
                    horizontalAlignment: Text.AlignRight
                    text: "exit"
                    color: row.mutedColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }

            // ACTION slot (reserved in every row — §V6-1 invariant 3;
            // zone x never moves between gate states). `use exit` on
            // candidates / `stop` on the active row (§V6-5/§V6-6): §T-4
            // semantics verbatim — single click, no confirm, one op at a
            // time, hidden gate-off. Neutral Breeze chrome (§V6-13).
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6.0
                Layout.preferredHeight: 1
                PC3.Button {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isCandidate && row.ctx.controlsEnabled
                    enabled: !row.ctx.ctlBusy
                    text: i18n("use exit")
                    QQC2.ToolTip.text: "use " + row.name + " as exit node"
                    QQC2.ToolTip.visible: hovered
                    height: Kirigami.Units.gridUnit * 1.4
                    topPadding: Kirigami.Units.smallSpacing * 0.5
                    bottomPadding: Kirigami.Units.smallSpacing * 0.5
                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                    onClicked: row.ctx.runControlOp("exit-set",
                                                    String(row.peer.DNSName || ""))
                }
                PC3.Button {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isExitNode && row.ctx.controlsEnabled
                    enabled: !row.ctx.ctlBusy
                    text: i18n("stop")
                    QQC2.ToolTip.text: "stop using exit node"
                    QQC2.ToolTip.visible: hovered
                    height: Kirigami.Units.gridUnit * 1.4
                    topPadding: Kirigami.Units.smallSpacing * 0.5
                    bottomPadding: Kirigami.Units.smallSpacing * 0.5
                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                    onClicked: row.ctx.runControlOp("exit-clear", "")
                }
            }
        }

        // ---- LINE 2: OS+CONN · ADDRESS · gutter · TRAFFIC ------------
        // ADDRESS right-edges land on one axis; TRAFFIC right-edges land
        // on the row's right edge (§V6-1 invariants 1–2).
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 0.9
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.95
            spacing: 0

            PC3.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8.6
                text: row.osConn
                color: row.mutedColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
            }
            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
            PC3.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 7.2
                horizontalAlignment: Text.AlignRight
                text: row.address
                color: row.mutedColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                elide: Text.ElideMiddle
            }
            // Scan gutter — 1.6·gu fixed break between ADDRESS and
            // TRAFFIC (§V6-1: the column gap is structure, not filler).
            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                Layout.preferredHeight: 1
            }
            PC3.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                horizontalAlignment: Text.AlignRight
                text: row.trafficText
                color: row.mutedColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                elide: Text.ElideLeft
            }
        }

        // §T-4 transient: renders only on the in-flight target row.
        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 0.9
            visible: row.isSwitchTarget
            text: "switching…"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }

    // Flash overlay on top of everything (§W-15.8).
    Rectangle {
        anchors.fill: parent
        z: 5
        color: Kirigami.Theme.highlightColor
        opacity: row.flashing ? 0.25 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
