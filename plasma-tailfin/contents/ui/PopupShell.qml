import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V7 popup shell — TABBED (PEERS · EXIT NODES · DEVICE, §V7-2).
// Pinned chrome: header (identity + search + health pill + §T-3
// power) → message strip (§T-5 items 1–3) → TAB BAR → tab content
// (one scroll region per tab) → footer (provenance + gate verdict).
// ALL popup sizing lives here and nowhere else (single-site rule):
// width 34·gu fixed; height min(38·gu, 0.9·available). The frame
// NEVER resizes on data, search, tab switch, detail push, or op
// flight — the active tab's scroll region is the overflow valve.
Item {
    id: shell

    // The PlasmoidItem root (never named "root" here — shadowing trap).
    required property var ctx

    function searchable() {
        return ctx.edgeState === "ok" && !ctx.needsLogin && ctx.peers.length > 0
    }

    // §V7-3 header line-2 routing fact (glance #2 [MAC]).
    function activeExitPeer() {
        const ps = ctx.peers || []
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].ExitNode === true) return ps[i]
        }
        return null
    }
    function routingText() {
        const ae = activeExitPeer()
        if (ae !== null) {
            return ae.Online === true
                    ? "via " + ctx.peerName(ae)
                    : "⚠ exit not routing"
        }
        if (ctx.status && String(ctx.status.activeMullvadExit || "") !== "")
            return "via " + ctx.status.activeMullvadExit
        return "direct"
    }
    function backendStateCaps() {
        if (ctx.needsLogin) return "NEEDS LOGIN"
        if (!ctx.running) return "STOPPED"
        return "RUNNING"
    }

    // ---- open/close lifecycle (§T-3/§T-5/§V7-2) --------------------
    onVisibleChanged: {
        if (visible) {
            ctx.ctlError = ctx.ops.lastError = ""
            // §V7-2 fresh-open law: PEERS when running, DEVICE when not.
            ctx.selectedTab = ctx.running ? 0 : 2
            forceActiveFocus()
        } else {
            ctx.disarmConfirm()
            ctx.peerQuery = ""
            ctx.searchOpen = false
            ctx.detailPeer = null
        }
    }

    // ---- keys (§V7-9; §W-9 ladder carried, detail-aware) -----------
    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            if (shell.searchable()) {
                ctx.selectedTab = 0           // search means "find a peer"
                ctx.searchOpen = true
                peersTab.searchRowFocus()
            }
            event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier)
                   && (event.key >= Qt.Key_1 && event.key <= Qt.Key_3)) {
            ctx.selectedTab = event.key - Qt.Key_1
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (ctx.detailPeer !== null) {
                ctx.detailPeer = null
            } else if (ctx.peerQuery !== "") {
                ctx.peerQuery = ""
                peersTab.focusIndex = -1
            } else if (ctx.searchOpen) {
                ctx.searchOpen = false
                shell.forceActiveFocus()
            } else {
                peersTab.searchRowBlur()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Left && ctx.detailPeer === null) {
            if (ctx.selectedTab > 0) ctx.selectedTab--
            event.accepted = true
        } else if (event.key === Qt.Key_Right && ctx.detailPeer === null) {
            if (ctx.selectedTab < 2) ctx.selectedTab++
            event.accepted = true
        } else if (event.key === Qt.Key_Down && ctx.peerQuery !== "") {
            peersTab.focusStep(1)
            event.accepted = peersTab.focusIndex >= 0
        } else if (event.key === Qt.Key_Up && ctx.peerQuery !== "") {
            if (peersTab.focusIndex <= 0) {
                peersTab.focusIndex = -1
                peersTab.searchRowFocus()
            } else {
                peersTab.focusStep(-1)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return && ctx.peerQuery !== "") {
            // §V7-9: Enter on the focused result opens DETAIL.
            if (peersTab.focusIndex >= 0) {
                const list = peersTab.resultsList()
                if (peersTab.focusIndex < list.length) {
                    peersTab.openDetail(list[peersTab.focusIndex])
                    event.accepted = true
                    return
                }
            }
            event.accepted = false
        }
    }

    // §R-10: deferred stamp refresh + per-second clock while open.
    Timer {
        interval: 150
        running: shell.visible
        onTriggered: ctx.clockNow = Date.now()
    }
    Timer {
        interval: 1000
        running: shell.visible
        repeat: true
        onTriggered: ctx.clockNow = Date.now()
    }

    // ---- Frame (§V7-3 = §V-5/§W-3 carried) -------------------------
    Layout.minimumWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: shellHeight()
    Layout.preferredHeight: shellHeight()

    function shellHeight() {
        const full = Kirigami.Units.gridUnit * 38
        const avail = ctx && ctx.availPopupHeight > 0 ? ctx.availPopupHeight : 0
        return avail > 0 ? Math.min(full, Math.floor(avail * 0.9)) : full
    }

    // Edge state hides the tab bar + search (§V7-8): chrome = header,
    // strip, footer standing; one centered edge row in the content.
    readonly property bool edgeMode:
        ctx.edgeState !== "ok" || ctx.needsLogin

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 1.25
        spacing: Kirigami.Units.smallSpacing

        // ---- HEADER (§V7-3): identity + [🔍] + [⚠ n] + §T-3 power --
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.9
                        Layout.preferredHeight: 1
                        Rectangle {
                            x: 0
                            width: Kirigami.Units.gridUnit * 0.35
                            height: Kirigami.Units.gridUnit * 0.35
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: shell.ctx.running
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.neutralTextColor
                        }
                    }

                    PC3.Label {
                        Layout.fillWidth: true
                        text: shell.ctx.status && shell.ctx.status.selfName
                              ? shell.ctx.status.selfName : "Tailscale"
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 0.8
                        elide: Text.ElideRight
                    }
                }

                // §V7-3 line 2: STATE CAPS · ip · routing
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 0.9
                    visible: shell.ctx.status !== null
                    text: {
                        const st = shell.ctx.status
                        if (shell.ctx.needsLogin) {
                            return "NEEDS LOGIN · "
                                   + (st && st.selfDnsName ? st.selfDnsName : "")
                        }
                        const ip = st && st.selfIp ? st.selfIp : ""
                        if (!shell.ctx.running) {
                            return ["STOPPED", ip].filter(
                                        function (p) { return p !== "" })
                                        .join(" · ")
                        }
                        return [backendStateCaps(), ip, routingText()].filter(
                                    function (p) { return p !== "" })
                                    .join(" · ")
                    }
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideMiddle
                    QQC2.ToolTip.text: shell.ctx.status
                        ? shell.ctx.status.selfDnsName : ""
                    QQC2.ToolTip.visible: selfHover.hovered
                    HoverHandler { id: selfHover }
                }
            }

            // §W-9 search toggle — switching to PEERS on reveal (§V7-4)
            PC3.ToolButton {
                visible: shell.searchable() && !shell.edgeMode
                flat: true
                checkable: true
                checked: shell.ctx.searchOpen
                icon.name: "edit-find"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: "Search peers (Ctrl+F)"
                QQC2.ToolTip.visible: hovered
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onToggled: {
                    shell.ctx.searchOpen = checked
                    if (checked) shell.ctx.selectedTab = 0
                }
            }

            // §V7-3 HEALTH PILL — count + pointer; text renders once,
            // on DEVICE (dedup law). Click → DEVICE.
            PC3.ToolButton {
                visible: (shell.ctx.health || []).length > 0
                flat: true
                text: "⚠ " + shell.ctx.health.length
                Layout.minimumHeight: Kirigami.Units.gridUnit * 0.9
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                QQC2.ToolTip.text: shell.ctx.health.length
                                   + " health warnings — open the Device tab"
                QQC2.ToolTip.visible: hovered
                onClicked: shell.ctx.selectedTab = 2
            }

            // §T-3 power — §V6-8 button relocated to the header
            // ([TS] StatusSwitch site; v0.6 footer Disconnect deleted).
            PC3.Button {
                visible: shell.ctx.controlsEnabled
                enabled: !shell.ctx.ctlBusy
                text: shell.ctx.ctlBusy ? "working…"
                      : shell.ctx.ctlArmed ? "Confirm disconnect"
                      : shell.ctx.running ? "Disconnect" : "Connect"
                palette.windowText: shell.ctx.ctlArmed
                                    ? Kirigami.Theme.negativeTextColor
                                    : Kirigami.Theme.textColor
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                topPadding: Kirigami.Units.smallSpacing * 0.5
                bottomPadding: Kirigami.Units.smallSpacing * 0.5
                leftPadding: Kirigami.Units.smallSpacing * 1.5
                rightPadding: Kirigami.Units.smallSpacing * 1.5
                onClicked: shell.ctx.powerClicked()
            }
        }

        // ---- MESSAGE STRIP (§V7-3: §T-5 items 1–3 ONLY) -------------
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlArmed
            text: "tailnet goes down here — remote access via ts.net drops until reconnect"
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlError !== ""
            text: shell.ctx.ctlError
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
        PC3.Label {
            Layout.fillWidth: true
            visible: !shell.ctx.controlsEnabled && shell.ctx.gateHint !== ""
            text: shell.ctx.gateHint
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }

        // ---- TAB BAR (§V7-2) — hand-rolled 3-cell row ----------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.0
            Layout.maximumHeight: Kirigami.Units.gridUnit * 2.0
            visible: !shell.edgeMode
            spacing: 0

            Repeater {
                model: ["PEERS", "EXIT NODES", "DEVICE"]
                PC3.AbstractButton {
                    required property int index
                    required property var modelData
                    id: tabCell
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    checkable: true
                    autoExclusive: true
                    checked: shell.ctx.selectedTab === index
                    hoverEnabled: true
                    onClicked: shell.ctx.selectedTab = index

                    background: Rectangle {
                        color: tabCell.pressed
                               ? Kirigami.Theme.highlightColor
                               : tabCell.hovered
                                 ? Kirigami.Theme.highlightColor : "transparent"
                        opacity: tabCell.pressed ? 0.12
                                : tabCell.hovered ? 0.06 : 1
                        // §V7-2 active underline: 2px, full cell width
                        Rectangle {
                            visible: tabCell.checked
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                    contentItem: Text {
                        text: tabCell.modelData
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: tabCell.checked ? Kirigami.Theme.textColor
                               : Kirigami.Theme.textColor
                        opacity: tabCell.checked ? 1.0 : 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.bold: true
                        font.letterSpacing: 0.4
                    }
                    Keys.onPressed: (event) => event.accepted = false
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData
                }
            }
        }
        Kirigami.Separator {
            Layout.fillWidth: true
            visible: !shell.edgeMode
        }

        // ---- TAB CONTENT — one region; edge mode replaces it --------
        StackLayout {
            id: tabsStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 20
            currentIndex: shell.edgeMode ? -1 : shell.ctx.selectedTab
            visible: !shell.edgeMode

            PeersTab {
                id: peersTab
                ctx: shell.ctx
            }
            ExitTab {
                ctx: shell.ctx
            }
            DeviceTab {
                ctx: shell.ctx
            }
        }

        // §V7-8 edge row — single centered string + icon
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: shell.edgeMode
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                source: shell.ctx.needsLogin ? "network-unavailable"
                        : shell.ctx.edgeState === "parseerror"
                          ? "dialog-cancel" : "network-offline-symbolic"
            }
            Text {
                text: shell.ctx.edgeOverlayText()
                color: Kirigami.Theme.negativeTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ---- FOOTER (§V6-20 provenance; Disconnect moved to header) --
        Kirigami.Separator { Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.3
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: {
                    const noStamp = shell.ctx.statusStampMs === 0
                    const ageMs = noStamp ? 0
                                  : shell.ctx.clockNow - shell.ctx.statusStampMs
                    const stale = noStamp
                                  || ageMs > shell.ctx.pollSeconds * 3 * 1000
                    const age = Math.max(0, Math.round(ageMs / 1000))
                    return stale ? "◐ stale · " + age + "s ago"
                                 : "● " + age + "s ago"
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                QQC2.ToolTip.text: {
                    const stamp = shell.ctx.statusStampMs > 0
                        ? new Date(shell.ctx.statusStampMs)
                          .toLocaleTimeString(Qt.locale(), "hh:mm:ss")
                        : "--:--:--"
                    return "as of " + stamp + " · poll every "
                           + shell.ctx.pollSeconds + "s"
                }
                QQC2.ToolTip.visible: footHover.hovered
                HoverHandler { id: footHover }
            }

            PC3.Label {
                text: shell.ctx.gateState === "enabled"
                      ? "CONTROL ENABLED · " + shell.ctx.gateOperator
                      : shell.ctx.gateState === "disabled" ? "CONTROL DISABLED"
                      : "CONTROL UNAVAILABLE"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }
    }
}
