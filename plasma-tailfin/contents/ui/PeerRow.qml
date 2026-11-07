import QtQuick
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import QtQuick.Controls as QQC2

// §V7-4 PeerRow — single-line 33px slot row, CLICKABLE (opens the peer
// detail page §V7-5). v0.6's two-line grid is deleted: density moved to
// the detail page [TS]. Fixed x-axes identical in every row, online and
// offline (§V6-1's addressable columns carried, one line):
//   DOT 0..0.9·gu | NAME 0.9→12.6 elide | ADDRESS 12.6 w7.2 RIGHT tnum
//   OS 19.8 w2.6 RIGHT | CONN 22.4 w4.4 RIGHT | ROLE 26.8..32.2 RIGHT
// NO per-row action buttons — exit switching lives on the EXIT tab and
// the detail page (deletes v0.6 B2 scatter at the source).
Item {
    id: row

    required property var ctx
    required property var peer
    // Qt6 Repeater over a JS array of OBJECTS exposes no `modelData`
    // unless the delegate declares it required (v0.3 PeerCell law).
    required property var modelData
    required property int index
    readonly property int myIndex: index

    // §V6-11 search-focus ring; -1 = none. Owned by PeersTab.
    property int focusIndex: -1

    signal activated(var peer)          // click / Enter → detail (§V7-9)

    readonly property bool online: peer.Online === true
    readonly property bool isExitNode: peer.ExitNode === true
    readonly property bool isCandidate:
        online && !isExitNode && peer.ExitNodeOption === true
    readonly property string name: ctx.peerName(peer)

    // §W-4 muted = textColor @ 0.62 (never disabledTextColor).
    readonly property color mutedColor: Kirigami.Theme.textColor

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.85)  // 33px
    width: Math.round(Kirigami.Units.gridUnit * 32.2)           // axis span

    function osToken(os) {
        const key = String(os || "").toLowerCase()
        if (key === "linux") return "Linux"
        if (key === "windows") return "Windows"
        if (key === "macos") return "macOS"
        if (key === "ios") return "iOS"
        if (key === "android") return "Android"
        return ""
    }

    // §V6-3 carried: relative display only; ISO branch → `Nd` / `>1y`
    // (Model.js untouched; absolute datetime lives in the tooltip).
    function displayLastSeen(iso) {
        const rel = Model.fmtLastSeen(iso)
        if (rel.indexOf("-") !== 4) return rel
        const t = Date.parse(String(iso || ""))
        if (isNaN(t)) return rel
        const days = Math.floor((Date.now() - t) / 86400000)
        return days >= 365 ? ">1y" : days + "d"
    }

    // ---- CONN slot text (§V6-3 grammar, relocated to its own slot)
    readonly property string connText: {
        if (!online) return "offline"
        if (ctx.peerIsDirect(peer)) return "direct"
        const relay = ctx.peerRelay(peer)
        return relay !== "" ? "relay · " + relay : ""
    }
    readonly property string osText: osToken(peer.OS)
    readonly property string address:
        String((peer.TailscaleIPs || [])[0] || "")

    // ---- ROLE: exactly ONE (§V7-4 priority active > capable > routes)
    readonly property var routes:
        (isCandidate || isExitNode) ? [] : (ctx.subnetRoutes(peer) || [])
    readonly property string roleText:
        isExitNode ? "EXIT NODE"
        : isCandidate ? "exit"
        : routes.length > 0
          ? routes[0] + (routes.length > 1 ? " +" + (routes.length - 1) : "")
          : ""

    // ---- §V6-10 matched-char bolding (search mode): greedy in-order
    // token walk over NAME — display-only, never bolds a non-match.
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
                if (found < 0) return ""
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

    // Tooltip / Accessible.name (§W-5 carried): full DNSName, both IPs,
    // routes, absolute last-seen when offline.
    readonly property string fullText: {
        const parts = [String(peer.DNSName || peer.HostName || "")]
        const ips = peer.TailscaleIPs || []
        for (let i = 0; i < ips.length; i++) parts.push(String(ips[i]))
        if (peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0)
            parts.push(String(peer.TailscaleIPv6[0]))
        if (!ctx.peerIsDirect(peer) && online) {
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

    // §W-15.8: 400ms flash on Online flip (tracked across full-array
    // peer replacement); counters never flash.
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
    Timer { id: flashTimer; interval: 400; onTriggered: row.flashing = false }

    Accessible.name: fullText
    Accessible.role: Accessible.ListItem
    HoverHandler { id: rowHover }
    QQC2.ToolTip.text: fullText
    QQC2.ToolTip.visible: rowHover.hovered

    // ---- interaction (§V7-9): hover @0.06, click → activated -------
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated(row.peer)
    }
    Rectangle {
        anchors.fill: parent
        visible: hit.containsMouse
        color: Kirigami.Theme.highlightColor
        opacity: 0.06
    }
    // §V6-11 search-focus ring kept (keyboard results mode).
    Rectangle {
        anchors.fill: parent
        visible: row.focusIndex === row.myIndex && row.focusIndex >= 0
        color: Kirigami.Theme.highlightColor
        opacity: 0.08
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }
    // Flash overlay on top (§W-15.8).
    Rectangle {
        anchors.fill: parent
        z: 5
        color: Kirigami.Theme.highlightColor
        opacity: row.flashing ? 0.25 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // ---- slots; content dims 0.62 offline (OMA law) ------------------
    Item {
        anchors.fill: parent
        opacity: row.online ? 1 : 0.62

        // DOT — 6px, 0.9·gu column (axis 4: one dot axis top to bottom)
        Item {
            x: 0
            width: Math.round(Kirigami.Units.gridUnit * 0.9)
            height: parent.height
            Rectangle {
                width: Math.round(Kirigami.Units.gridUnit * 0.35)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                color: row.online ? Kirigami.Theme.positiveTextColor
                                  : Kirigami.Theme.disabledTextColor
            }
        }

        // NAME — T2 DemiBold elide right; bold marks in search mode
        PC3.Label {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(Kirigami.Units.gridUnit * 0.9)
            anchors.right: parent.left
            anchors.rightMargin: Math.round(
                Kirigami.Units.gridUnit * (32.2 - 12.6))
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            textFormat: row.nameMarkup !== ""
                        ? Text.StyledText : Text.AutoText
            text: row.nameMarkup !== "" ? row.nameMarkup : row.name
            color: Kirigami.Theme.textColor
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.72)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        // ADDRESS — right, tnum
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 12.6)
            width: Math.round(Kirigami.Units.gridUnit * 7.2)
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: row.address
            color: row.mutedColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
        }

        // OS — right, brand case; slot reserved when unknown
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 19.8)
            width: Math.round(Kirigami.Units.gridUnit * 2.6)
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: row.osText
            color: row.mutedColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }

        // CONN — right
        PC3.Label {
            x: Math.round(Kirigami.Units.gridUnit * 22.4)
            width: Math.round(Kirigami.Units.gridUnit * 4.4)
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: row.connText
            color: row.mutedColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }

        // ROLE — right edge = content right edge (§V7-13 #7)
        Row {
            spacing: Kirigami.Units.smallSpacing * 0.5
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Kirigami.Icon {
                visible: row.isExitNode
                source: "network-vpn"
                isMask: true
                width: Math.round(Kirigami.Units.gridUnit * 0.7)
                height: Math.round(Kirigami.Units.gridUnit * 0.7)
                anchors.verticalCenter: parent.verticalCenter
                color: Kirigami.Theme.highlightColor
            }
            PC3.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: row.roleText
                color: row.isExitNode ? Kirigami.Theme.textColor : row.mutedColor
                opacity: row.isExitNode ? 1 : 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: row.isExitNode
            }
        }
    }
}
