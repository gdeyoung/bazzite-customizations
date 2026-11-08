import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import "Control.js" as Control
import QtQuick.Controls as QQC2

// §V7-6 ExitTab — state block (§T-4 banner strings + routing-health
// pill [DMTH]) → hairline → picker list (None · direct first, then
// candidates alphabetical; [WIN] radio grammar; one gesture, no
// confirm). Fills Trayscale gap #3.
Item {
    id: tab

    required property var ctx

    // The currently-active exit peer (null when none).
    readonly property var activeExit: {
        const ps = ctx.peers || []
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].ExitNode === true) return ps[i]
        }
        return null
    }
    readonly property bool viaMullvad:
        activeExit === null && ctx.status
        && String(ctx.status.activeMullvadExit || "") !== ""

    // Warn conditions (§V7-6, derivable — no new data):
    // (a) active exit peer is offline; (b) prefs pin an exit IP while
    //     no peer carries the ExitNode flag.
    readonly property string warnCause: {
        if (activeExit !== null && activeExit.Online !== true)
            return ctx.peerName(activeExit) + " is offline"
        if (activeExit === null) {
            const prefs = Model.parsePrefs(ctx.gatePrefs)
            if (prefs.ok && prefs.exitNodeIp !== "" && !viaMullvad)
                return prefs.exitNodeIp
                       + " configured but no peer is routing — pick another"
        }
        return ""
    }
    readonly property bool routing: activeExit !== null
                                    && activeExit.Online === true

    // Candidates: §T-4's raw 0.0.0.0/0 test, alphabetical. Split for
    // the §V8-4 MULLVAD REGIONS section — same allowlisted exit-set op.
    readonly property var candidates: ctx.exitNodes || []
    readonly property var tailnetNodes: {
        const all = ctx.exitNodes || []
        const out = []
        for (let i = 0; i < all.length; i++) {
            if (!Model.isMullvadPeer(all[i])) out.push(all[i])
        }
        return out
    }
    // §V8-2c: Model excludes mullvad peers from ctx.peers/exitNodes
    // entirely, so this reads the dedicated ctx.mullvadExitNodes lane.
    readonly property var mullvadNodes: ctx.mullvadExitNodes || []
    property string mullvadFilter: ""
    readonly property var mullvadShown: {
        const q = mullvadFilter.toLowerCase()
        if (q === "") return mullvadNodes
        return mullvadNodes.filter(function (n) {
            return String(n.HostName || "").toLowerCase().indexOf(q) >= 0
                || String(ctx.peerName(n)).toLowerCase().indexOf(q) >= 0
        })
    }
    readonly property var activeMullvadName: {
        const am = ctx.status && ctx.status.activeMullvadExit
            ? String(ctx.status.activeMullvadExit) : ""
        if (am === "") return ""
        for (let i = 0; i < mullvadNodes.length; i++) {
            const dns = String(mullvadNodes[i].DNSName || "").replace(/\.+$/, "")
            if (dns === am || dns.indexOf(am) === 0 || am.indexOf(dns) === 0)
                return dns
        }
        return ""
    }

    // §T-4 target name while an op flies.
    readonly property bool switching: ctx.ctlBusy
                                       && ctx.currentOp.indexOf("exit") === 0

    function guMul(m) { return Math.round(Kirigami.Units.gridUnit * m) }

    PC3.ScrollView {
        id: pickScroll
        anchors.fill: parent
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: pickScroll.width - Kirigami.Units.gridUnit * 0.8
            spacing: Kirigami.Units.smallSpacing

            // ---- state block (pinned zone, §V7-6 #1)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing * 0.5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: "network-vpn"
                        isMask: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.7
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.7
                        color: tab.routing ? Kirigami.Theme.highlightColor
                                           : Kirigami.Theme.textColor
                        opacity: tab.routing ? 1 : 0.62
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        text: {
                            if (tab.activeExit !== null)
                                return "▸ exit node: <b>"
                                       + ctx.peerName(tab.activeExit) + "</b>"
                            if (tab.viaMullvad)
                                return "▸ exit node: <b>"
                                       + ctx.status.activeMullvadExit + "</b>"
                            return "no exit node · direct"
                        }
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }
                }

                // routing-health pill [DMTH] — chip + word (never
                // color-only); cause line beneath when warning.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        id: pill
                        readonly property bool warn: tab.warnCause !== ""
                        readonly property bool live: tab.routing
                        width: pillLabel.implicitWidth
                               + Kirigami.Units.smallSpacing * 2
                        height: Kirigami.Units.gridUnit * 0.9
                        radius: height / 2
                        border.width: 1
                        border.color: warn ? Kirigami.Theme.neutralTextColor
                                  : live ? Kirigami.Theme.highlightColor
                                         : Kirigami.Theme.textColor
                        color: "transparent"
                        PC3.Label {
                            id: pillLabel
                            anchors.centerIn: parent
                            text: pill.warn ? "⚠ not routing"
                                  : pill.live ? "● routing" : "● direct"
                            color: pill.warn ? Kirigami.Theme.neutralTextColor
                                  : pill.live ? Kirigami.Theme.highlightColor
                                         : Kirigami.Theme.textColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.bold: true
                        }
                        HoverHandler { id: pillHover }
                        QQC2.ToolTip.text: pill.warn
                            ? "the configured exit node is not routing traffic"
                            : live ? "traffic is routing through the exit node"
                                   : "traffic goes direct — no exit node"
                        QQC2.ToolTip.visible: pillHover.hovered
                    }
                    Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
                }
                PC3.Label {
                    Layout.fillWidth: true
                    visible: tab.warnCause !== ""
                    text: tab.warnCause
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    wrapMode: Text.WordWrap
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ---- §V8-1.4 caps section header (Omarchy grammar) -------
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: "ROUTE ALL TRAFFIC THROUGH"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }

            // ---- picker list ------------------------------------------
            // Row 0: None · direct
            PickerRow {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                ctx: tab.ctx
                title: "None (direct)"
                address: ""
                osText: ""
                conn: "use your own internet connection"
                selected: tab.activeExit === null && !tab.viaMullvad
                busyTarget: false
                interactive: ctx.controlsEnabled && !ctx.ctlBusy
                onPicked: ctx.runControlOp("exit-clear", "")
            }

            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: tab.tailnetNodes.length > 0
                text: "TAILNET EXIT NODES"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }

            // candidate rows — §T-4 one-gesture switching (tailnet only;
            // mullvad nodes render in their own section below)
            Repeater {
                model: tab.tailnetNodes
                PickerRow {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    ctx: tab.ctx
                    peer: modelData
                    title: ctx.peerName(modelData)
                    address: String((modelData.TailscaleIPs || [])[0] || "")
                    osText: osToken(modelData.OS)
                    conn: ctx.peerIsDirect(modelData) ? "direct"
                           : ("relay · " + ctx.peerRelay(modelData))
                    selected: tab.activeExit !== null
                              && tab.activeExit.id === modelData.id
                    busyTarget: ctx.ctlSwitching !== ""
                                && ctx.ctlSwitching
                                   === String(modelData.DNSName || "")
                    interactive: ctx.controlsEnabled && !ctx.ctlBusy
                    onPicked: ctx.runControlOp("exit-set",
                                               Control.exitTarget(modelData))
                }
            }

            // ---- §V8-4 MULLVAD REGIONS (visible only when the tailnet
            // has Mullvad exit nodes — Trayscale parity)
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: tab.mullvadNodes.length > 0
                text: "MULLVAD REGIONS"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            PC3.TextField {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: tab.mullvadNodes.length > 8
                placeholderText: "Filter " + tab.mullvadNodes.length + " regions…"
                text: tab.mullvadFilter
                onTextChanged: tab.mullvadFilter = text
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            Repeater {
                model: tab.mullvadShown
                PickerRow {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    ctx: tab.ctx
                    peer: modelData
                    title: ctx.peerName(modelData)
                    address: String((modelData.TailscaleIPs || [])[0] || "")
                    osText: "mullvad"
                    conn: ""
                    selected: tab.activeMullvadName !== ""
                              && String(modelData.DNSName || "").replace(/\.+$/, "")
                                 === tab.activeMullvadName
                    busyTarget: ctx.ctlSwitching !== ""
                                && ctx.ctlSwitching
                                   === String(modelData.DNSName || "")
                    interactive: ctx.controlsEnabled && !ctx.ctlBusy
                    onPicked: ctx.runControlOp("exit-set",
                                               Control.exitTarget(modelData))
                }
            }
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: tab.mullvadNodes.length > 0
                         && tab.mullvadShown.length === 0
                text: "no regions match"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            // §T-4 in-flight marker row
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: tab.switching
                text: "switching…"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            // empty state (§V7-6 #3)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit
                Layout.bottomMargin: Kirigami.Units.gridUnit
                visible: tab.tailnetNodes.length === 0 && tab.mullvadNodes.length === 0
                spacing: Kirigami.Units.smallSpacing * 0.5
                Text {
                    Layout.fillWidth: true
                    text: "NO EXIT-CAPABLE PEERS ONLINE"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    Layout.rightMargin: Kirigami.Units.gridUnit
                    text: "a peer must advertise 0.0.0.0/0 before it can route your traffic"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }
    }

    function osToken(os) {
        const key = String(os || "").toLowerCase()
        if (key === "linux") return "Linux"
        if (key === "windows") return "Windows"
        if (key === "macos") return "macOS"
        if (key === "ios") return "iOS"
        if (key === "android") return "Android"
        return ""
    }
}
