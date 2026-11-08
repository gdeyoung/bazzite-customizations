import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V8-4 MachinesTab — PeersTab machinery (search → pinned header →
// lane → offline fold, StackView list↔detail) with the Omarchy row
// grammar (MachineRow two-line) and the Omarchy footer summary strip:
// "N online · N offline — hidden · v0.8.0".
Item {
    id: tab

    required property var ctx

    property int focusIndex: -1

    property bool offlineExpanded: ctx.showOffline === true
    readonly property bool zeroOnline:
        ctx.edgeState === "ok" && !ctx.needsLogin
        && ctx.onlinePeers.length === 0 && ctx.offlinePeers.length > 0
    onZeroOnlineChanged: { if (zeroOnline) offlineExpanded = true }

    function searchable() {
        return ctx.edgeState === "ok" && !ctx.needsLogin && ctx.peers.length > 0
    }
    function sortedOnline() {
        const list = ctx.onlinePeers.slice()
        list.sort(function (a, b) {
            return ctx.peerName(a).localeCompare(ctx.peerName(b))
        })
        return list
    }
    function resultsList() {
        return ctx.peerQuery !== "" && searchable() ? ctx.searchResults : []
    }
    function focusFirstResult() {
        if (resultsList().length > 0) focusIndex = 0
    }
    function focusStep(delta) {
        const n = resultsList().length
        if (n === 0) return
        focusIndex = focusIndex < 0
                      ? (delta > 0 ? 0 : n - 1)
                      : Math.max(0, Math.min(n - 1, focusIndex + delta))
    }

    function searchRowFocus() {
        if (searchRow.visible) {
            searchRow.field.forceActiveFocus()
            searchRow.field.selectAll()
        }
    }
    function searchRowBlur() {
        searchRow.field.focus = false
    }

    function copyPeer(peer) {
        const ips = (peer && peer.TailscaleIPs) || []
        const s = ips.length > 0 ? String(ips[0]) : ""
        if (s !== "") ctx.copyToClipboard(s)
    }

    function openDetail(peer) {
        ctx.detailPeer = peer
        if (stack.depth === 1) stack.push(detailComponent)
    }
    function closeDetail() {
        ctx.detailPeer = null
    }
    Connections {
        target: ctx
        function onDetailPeerChanged() {
            if (ctx.detailPeer === null && stack.depth > 1) stack.pop()
        }
    }

    QQC2.StackView {
        id: stack
        anchors.fill: parent
        initialItem: listPage

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240 }
                NumberAnimation { property: "x"
                                  from: Kirigami.Units.gridUnit * 2; to: 0
                                  duration: 240; easing.type: Easing.OutQuad }
            }
        }
        popExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
                NumberAnimation { property: "x"; to: Kirigami.Units.gridUnit * 2
                                  duration: 200; easing.type: Easing.InQuad }
            }
        }

        ColumnLayout {
            id: listPage
            spacing: 0

            SearchRow {
                id: searchRow
                visible: tab.ctx.searchOpen && tab.searchable()
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                ctx: tab.ctx
                onRequestFirstResult: tab.focusFirstResult()
            }

            // caps section header (V8-1.4)
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    text: tab.ctx.peerQuery !== ""
                          ? "MATCHES · " + tab.ctx.searchResults.length
                            + " OF " + tab.ctx.peers.length
                          : tab.zeroOnline ? "OFFLINE" : "ONLINE"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                    font.letterSpacing: 0.4
                    font.features: ({ "tnum": 1 })
                }
                Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
                Repeater {
                    model: tab.subseqOnlyTokens()
                    PC3.Label {
                        required property var modelData
                        text: "~" + modelData
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            PC3.ScrollView {
                id: lane
                Layout.fillWidth: true
                Layout.fillHeight: true
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    id: laneContent
                    width: Math.round(Kirigami.Units.gridUnit * 38.4)
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        Layout.bottomMargin: Kirigami.Units.gridUnit * 2
                        visible: tab.ctx.edgeState === "ok"
                                 && !tab.ctx.needsLogin
                                 && tab.ctx.peers.length === 0
                        text: "NO MACHINES · TAILNET EMPTY"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        visible: tab.zeroOnline
                        text: "0 of " + tab.ctx.peers.length
                              + " machines online · showing all offline"
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        visible: tab.ctx.peerQuery !== "" && tab.searchable()
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.gridUnit
                            Layout.bottomMargin: Kirigami.Units.gridUnit
                            visible: tab.ctx.searchResults.length === 0
                            text: "NO MATCHING MACHINES"
                            color: Kirigami.Theme.textColor
                            opacity: 0.62
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Repeater {
                            model: tab.ctx.searchResults
                            MachineRow {
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                ctx: tab.ctx
                                peer: modelData
                                focusIndex: tab.focusIndex
                                onActivated: function (p) { tab.openDetail(p) }
                                onCopyRequested: function (p) { tab.copyPeer(p) }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: tab.ctx.peerQuery === "" && tab.searchable()
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: tab.zeroOnline ? [] : tab.sortedOnline()
                            MachineRow {
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                ctx: tab.ctx
                                peer: modelData
                                focusIndex: -1
                                onActivated: function (p) { tab.openDetail(p) }
                                onCopyRequested: function (p) { tab.copyPeer(p) }
                            }
                        }
                        PC3.Button {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                            Layout.rightMargin: Kirigami.Units.smallSpacing
                            visible: tab.ctx.offlinePeers.length > 0
                                     && tab.ctx.peerQuery === ""
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                            topPadding: Kirigami.Units.smallSpacing * 0.5
                            bottomPadding: Kirigami.Units.smallSpacing * 0.5
                            text: tab.ctx.offlinePeers.length + " OFFLINE · "
                                  + (tab.offlineExpanded ? "HIDE" : "SHOW")
                            onClicked: tab.offlineExpanded = !tab.offlineExpanded
                        }
                        Repeater {
                            model: tab.ctx.offlinePeers
                            MachineRow {
                                visible: tab.offlineExpanded
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                ctx: tab.ctx
                                peer: modelData
                                focusIndex: -1
                                onActivated: function (p) { tab.openDetail(p) }
                                onCopyRequested: function (p) { tab.copyPeer(p) }
                            }
                        }
                    }
                }
            }

            // ---- §V8-1.6 footer summary strip (Omarchy) — pinned ----
            Kirigami.Separator { Layout.fillWidth: true }
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing * 0.5
                Layout.bottomMargin: Kirigami.Units.smallSpacing * 0.5
                text: {
                    const on = tab.ctx.onlinePeers.length
                    const off = tab.ctx.offlinePeers.length
                    return on + " online · " + off + " offline — "
                           + (tab.offlineExpanded ? "shown" : "hidden")
                }
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: detailComponent
        PeerDetailPage {
            ctx: tab.ctx
            peer: tab.ctx.detailPeer
            onBack: tab.closeDetail()
        }
    }

    function subseqOnlyTokens() {
        const q = String(ctx.peerQuery || "")
        if (q === "" || ctx.searchResults.length === 0) return []
        const tokens = q.toLowerCase().split(/\s+/).filter(function (t) {
            return t !== ""
        })
        const out = []
        for (let ti = 0; ti < tokens.length && out.length < 3; ti++) {
            const tok = tokens[ti]
            let best = 0
            for (let pi = 0; pi < ctx.searchResults.length && best < 3; pi++) {
                const p = ctx.searchResults[pi]
                const fields = [p.DisplayName, p.HostName, p.DNSName,
                                (p.TailscaleIPs || []).join(" ")]
                for (let fi = 0; fi < fields.length && best < 3; fi++) {
                    best = Math.max(best, tokenScore(tok, fields[fi]))
                }
            }
            if (best === 1) out.push(tok)
        }
        return out
    }
    function tokenScore(token, field) {
        const f = String(field || "").toLowerCase()
        const t = String(token || "").toLowerCase()
        if (f === "" || t === "") return 0
        if (f.indexOf(t) === 0) return 3
        if (f.indexOf(t) !== -1) return 2
        let i = 0
        for (let j = 0; j < f.length && i < t.length; j++) {
            if (f.charAt(j) === t.charAt(i)) i++
        }
        return i === t.length ? 1 : 0
    }
}
