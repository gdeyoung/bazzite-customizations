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

    // Candidates: §T-4's raw 0.0.0.0/0 test, alphabetical.
    readonly property var candidates: ctx.exitNodes || []

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

            // ---- picker list ------------------------------------------
            // Row 0: None · direct
            PickerRow {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                ctx: tab.ctx
                title: "None · direct"
                address: ""
                osText: ""
                conn: "direct"
                selected: tab.activeExit === null && !tab.viaMullvad
                busyTarget: false
                interactive: ctx.controlsEnabled && !ctx.ctlBusy
                onPicked: ctx.runControlOp("exit-clear", "")
            }

            // candidate rows — §T-4 one-gesture switching
            Repeater {
                model: tab.candidates
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
                visible: tab.candidates.length === 0
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
