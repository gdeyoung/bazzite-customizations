import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import QtQuick.Controls as QQC2

// §V7-5 PeerDetailPage — pushed onto PeersTab's StackView. Back row +
// title + labeled groups (IDENTITY / CONNECTION / TRAFFIC / SUBNET
// ROUTES / EXIT NODE). Density lives HERE, not on the row [TS].
// Rates: ctx.rateMap[id] computed in main.qml across poll ticks.
Item {
    id: page

    required property var ctx
    required property var peer
    // null-safe during pop transitions (closeDetail nulls ctx.detailPeer
    // while the pop animation still evaluates bindings)
    readonly property var pd: peer !== null && peer !== undefined ? peer : ({})

    signal back()

    function guMul(m) { return Math.round(Kirigami.Units.gridUnit * m) }

    // Peer may be replaced by a same-id object on each tick — all
    // bindings re-evaluate; identity fields stay stable.
    readonly property bool online: pd.Online === true
    readonly property bool isExitNode: pd.ExitNode === true
    readonly property bool isCandidate:
        online && !isExitNode && pd.ExitNodeOption === true
    readonly property var exitRoutes: ctx.subnetRoutes(peer) || []
    readonly property var rates: ctx.rateMap[String(pd.id)] || null

    function osToken(os) {
        const key = String(os || "").toLowerCase()
        if (key === "linux") return "Linux"
        if (key === "windows") return "Windows"
        if (key === "macos") return "macOS"
        if (key === "ios") return "iOS"
        if (key === "android") return "Android"
        return ""
    }
    function displayLastSeen(iso) {
        const rel = Model.fmtLastSeen(iso)
        if (rel.indexOf("-") !== 4) return rel
        const t = Date.parse(String(iso || ""))
        if (isNaN(t)) return rel
        const days = Math.floor((Date.now() - t) / 86400000)
        return days >= 365 ? ">1y" : days + "d"
    }
    function connPath() {
        if (!online) return "offline"
        if (ctx.peerIsDirect(peer)) return "direct"
        const relay = ctx.peerRelay(peer)
        return relay !== "" ? "relay · " + relay : ""
    }
    function stateText() {
        if (!online) return "offline · last seen " + displayLastSeen(pd.LastSeen)
        return pd.Active === true ? "online · active" : "online · idle"
    }

    PC3.ScrollView {
        id: detailScroll
        anchors.fill: parent
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: detailScroll.width - Kirigami.Units.gridUnit * 0.8
            spacing: Kirigami.Units.smallSpacing

            // ---- back row (§V7-5): flat ToolButton, T4 label
            PC3.ToolButton {
                Layout.topMargin: Kirigami.Units.smallSpacing * 0.5
                text: "← PEERS"
                flat: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
                QQC2.ToolTip.text: "Back to peers"
                QQC2.ToolTip.visible: hovered
                onClicked: page.back()
            }

            // ---- title block
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: ctx.peerName(peer)
                color: Kirigami.Theme.textColor
                font.pixelSize: guMul(0.8)
                font.bold: true
                elide: Text.ElideRight
            }
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                text: [osToken(pd.OS), connPath(), stateText()]
                    .filter(function (p) { return p !== "" }).join(" · ")
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ---- group factory: T4 label + rows (label muted left,
            //      value right, 1.85·gu, tnum on numbers, selectable)
            Repeater {
                // IDENTITY
                model: [
                    { label: "dns name", value: String(pd.DNSName || "") },
                    { label: "ipv4", value: String((pd.TailscaleIPs || [])[0] || "") },
                    { label: "ipv6", value: String((pd.TailscaleIPv6 || [])[0] || "") }
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                    spacing: Kirigami.Units.smallSpacing
                    visible: modelData.value !== ""
                    PC3.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        text: modelData.label
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.value
                        textFormat: Text.AutoText
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.features: ({ "tnum": 1 })
                        elide: Text.ElideMiddle
                        // selectable per §V7-5 #4 (no clipboard API)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: page.online
                text: "CONNECTION"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            Repeater {
                // CONNECTION (rows meaningful only while online; offline
                // state already carries the facts in the title line)
                model: page.online ? [
                    { label: "os", value: osToken(pd.OS) },
                    { label: "path", value: connPath() },
                    { label: "state", value: stateText() }
                ] : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                    spacing: Kirigami.Units.smallSpacing
                    visible: modelData.value !== ""
                    PC3.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        text: modelData.label
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.value
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            // ---- TRAFFIC [§V7-5 NEW — the Trayscale gap]: totals +
            //      derived rates; `—` until a second sample, `idle` at 0
            PC3.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: page.online
                text: "TRAFFIC"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            Repeater {
                model: page.online ? [
                    { label: "received ↓",
                      value: Model.fmtBytes(pd.RxBytes || 0)
                             + " · " + (page.rates
                                        ? (page.rates.idle ? "idle"
                                           : page.rates.ready ? page.rates.rx
                                           : "—") : "—") + "/s" },
                    { label: "sent ↑",
                      value: Model.fmtBytes(pd.TxBytes || 0)
                             + " · " + (page.rates
                                        ? (page.rates.idle ? "idle"
                                           : page.rates.ready ? page.rates.tx
                                           : "—") : "—") + "/s" }
                ] : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        text: modelData.label
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.value
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            // ---- SUBNET ROUTES (conditional): 0.0.0.0/0 suppressed on
            //      exit peers (tautology, §V-4 #1)
            PC3.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: page.exitRoutes.length > 0
                text: "SUBNET ROUTES"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            Repeater {
                model: page.exitRoutes
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                           Layout.preferredHeight: 1 }
                    PC3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            // ---- EXIT NODE (conditional, §T-4 semantics verbatim)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: page.isCandidate || page.isExitNode
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    text: "EXIT NODE"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                    font.letterSpacing: 0.4
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        text: page.isExitNode ? "current exit node"
                              : "this peer can route your traffic"
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }
                    PC3.Button {
                        visible: ctx.controlsEnabled
                        enabled: !ctx.ctlBusy
                        text: page.isExitNode ? "stop" : "use exit"
                        QQC2.ToolTip.text: page.isExitNode
                                ? "stop using exit node"
                                : "use " + ctx.peerName(peer) + " as exit node"
                        QQC2.ToolTip.visible: hovered
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                        topPadding: Kirigami.Units.smallSpacing * 0.5
                        bottomPadding: Kirigami.Units.smallSpacing * 0.5
                        leftPadding: Kirigami.Units.smallSpacing * 1.5
                        rightPadding: Kirigami.Units.smallSpacing * 1.5
                        onClicked: {
                            if (page.isExitNode)
                                ctx.runControlOp("exit-clear", "")
                            else
                                ctx.runControlOp("exit-set",
                                                 String(pd.DNSName || ""))
                        }
                    }
                }
                // §T-4 in-flight marker on the detail action
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    visible: ctx.ctlBusy
                    text: "switching…"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }
    }
}
