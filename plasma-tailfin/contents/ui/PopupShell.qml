import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V6 popup: pinned chrome (header → message strip → ExitStrip →
// revealed search row) → ONE SCROLLING PEER LANE → pinned action-bar
// footer. The v0.3 verdict IS the architecture: one big long list that
// scrolls. No tabs, no exit section — exit candidates are rows with a
// labeled `use exit` action; the active exit is a state of its row
// (§V6-6) confirmed by the ExitStrip (§V6-7).
//
// ALL popup sizing lives here and nowhere else (single-site rule):
// width 34·gu fixed; height min(38·gu, 0.9·available). The frame NEVER
// resizes on data, search, expand, or op flight — the lane is the
// overflow valve.
Item {
    id: shell

    // The PlasmoidItem root (never named "root" here — shadowing trap).
    required property var ctx

    // §W-9 searchable: nothing to search on 0 peers or the
    // down/missing/login/parse edge states.
    function searchable() {
        return ctx.edgeState === "ok" && !ctx.needsLogin && ctx.peers.length > 0
    }

    // §W-2 online rows alphabetical (one list, one order).
    function sortedOnline() {
        const list = ctx.onlinePeers.slice()
        list.sort(function (a, b) {
            return ctx.peerName(a).localeCompare(ctx.peerName(b))
        })
        return list
    }

    // Offline toggle: session-local state seeded from the showOffline
    // config (v0.4 behavior carries; no new config keys).
    property bool offlineExpanded: ctx.showOffline === true

    // §V6-17: when 0 peers are online the offline block auto-expands
    // (default, not a lock — the toggle still collapses it; resets when
    // peers return or the popup closes).
    readonly property bool zeroOnline:
        ctx.edgeState === "ok" && !ctx.needsLogin
        && ctx.onlinePeers.length === 0 && ctx.offlinePeers.length > 0

    onZeroOnlineChanged: {
        if (zeroOnline) offlineExpanded = true
    }

    // §V6-11 search-focus index: -1 = none. Rows render the ring.
    property int focusIndex: -1
    function resultsList() {
        return ctx.peerQuery !== "" && searchable() ? ctx.searchResults : []
    }
    function focusFirstResult() {
        if (resultsList().length > 0) focusIndex = 0
    }
    function focusLastResult() {
        const n = resultsList().length
        if (n > 0) focusIndex = n - 1
    }
    function focusStep(delta) {
        const n = resultsList().length
        if (n === 0) return
        focusIndex = focusIndex < 0
                      ? (delta > 0 ? 0 : n - 1)
                      : Math.max(0, Math.min(n - 1, focusIndex + delta))
    }
    // §V6-11 Enter on the focused result row: candidate → exit-set;
    // active row → exit-clear; anything else no-op.
    function activateFocused() {
        const list = resultsList()
        if (focusIndex < 0 || focusIndex >= list.length) return
        const p = list[focusIndex]
        if (!ctx.controlsEnabled || ctx.ctlBusy) return
        if (p.ExitNode === true) {
            ctx.runControlOp("exit-clear", "")
        } else if (p.Online === true && p.ExitNodeOption === true) {
            ctx.runControlOp("exit-set", String(p.DNSName || ""))
        }
    }

    // §T-3/§T-5 open/close: reopen dismisses the last op error; close
    // disarms the confirm, clears the query AND collapses search
    // (§W-9 — fresh open = fresh view).
    onVisibleChanged: {
        if (visible) {
            ctx.ctlError = ctx.ops.lastError = ""
            forceActiveFocus()
        } else {
            ctx.disarmConfirm()
            ctx.peerQuery = ""
            ctx.searchOpen = false
            focusIndex = -1
            if (offlineExpanded && !ctx.showOffline) offlineExpanded = false
        }
    }

    // §W-9 keys: Ctrl+F → reveal + focus + select-all; Esc → clear the
    // query, else collapse the revealed field, else blur. §V6-11 adds
    // ↑/↓/Enter over result rows while the query is live.
    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            if (shell.searchable()) {
                ctx.searchOpen = true
                searchRow.field.forceActiveFocus()
                searchRow.field.selectAll()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (ctx.peerQuery !== "") {
                ctx.peerQuery = ""
                shell.focusIndex = -1
            } else if (ctx.searchOpen) {
                ctx.searchOpen = false
                shell.forceActiveFocus()
            } else {
                searchRow.field.focus = false
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Down && ctx.peerQuery !== "") {
            shell.focusStep(1)
            event.accepted = shell.focusIndex >= 0
        } else if (event.key === Qt.Key_Up && ctx.peerQuery !== "") {
            if (shell.focusIndex <= 0) {
                shell.focusIndex = -1
                searchRow.field.forceActiveFocus()
            } else {
                shell.focusStep(-1)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return
                   && ctx.peerQuery !== "" && shell.focusIndex >= 0) {
            shell.activateFocused()
            event.accepted = true
        }
    }

    // §R-10: no synchronous work in the open handler — stamp refresh
    // defers ~150 ms; clockNow ticks once per second while open so the
    // provenance ●/◐ verdict stays honest.
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

    // ScrollView.contentItem is the inner Flickable (may be null before
    // component completion — every use guards it).
    readonly property var laneFlick: lane.contentItem

    // ---- Frame (§W-3; §V-5/§R-2 unchanged) ---------------------------
    Layout.minimumWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: shellHeight()
    Layout.preferredHeight: shellHeight()

    function shellHeight() {
        const full = Kirigami.Units.gridUnit * 38
        const avail = ctx && ctx.availPopupHeight > 0 ? ctx.availPopupHeight : 0
        return avail > 0 ? Math.min(full, Math.floor(avail * 0.9)) : full
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 1.25
        spacing: Kirigami.Units.smallSpacing

        // ---- HEADER (§V6-14): identity + search ONLY. The power
        // control moved to the footer (§V6-8). ----------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
            spacing: Kirigami.Units.smallSpacing

            // Self identity block — single render site (dedup rule).
            // Self is NOT a row in the list, so lane counts equal chip
            // counts exactly. Dot sits in the 0.9·gu STATUS column —
            // one dot axis top to bottom (§V6-1 invariant 4).
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

                // §V6-14 identity grammar: `this device` names WHO the
                // block is about (audit M1); the routing fact lives
                // here when no strip renders; RUNNING is deleted (the
                // dot says up; vocabulary collision dies, audit B4).
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
                        const dns = st && st.selfDnsName ? st.selfDnsName : ""
                        if (!shell.ctx.running) {
                            return ["stopped", ip, dns].filter(
                                        function (p) { return p !== "" })
                                        .join(" · ")
                        }
                        const exit = shell.ctx.exitBannerText()
                        const route = exit !== "" ? "via " + exit : "direct"
                        return ["this device", route, ip, dns].filter(
                                    function (p) { return p !== "" }).join(" · ")
                    }
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideMiddle
                }
            }
            HoverHandler { id: selfHover }
            QQC2.ToolTip.text: {
                const st = shell.ctx.status
                return st ? [st.selfDnsName, st.selfIp].filter(
                            function (p) { return p }).join(" · ") : ""
            }
            QQC2.ToolTip.visible: selfHover.hovered

            // §W-9: search revealed by this checkable button (or Ctrl+F)
            // — the header's ONLY control now (§V6-14).
            PC3.ToolButton {
                visible: shell.searchable()
                flat: true
                checkable: true
                checked: shell.ctx.searchOpen
                icon.name: "edit-find"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: i18n("Search peers (Ctrl+F)")
                QQC2.ToolTip.visible: hovered
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onToggled: shell.ctx.searchOpen = checked
            }
        }

        // ---- MESSAGE STRIP (§W-8; §T-5 items 1–3 verbatim, then the
        // §V6-18 health block) --------------------------------------
        // 1. armed warning (§T-3)
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlArmed
            text: "tailnet goes down here — remote access via ts.net drops until reconnect"
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
        // 2. op error (§T-5)
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlError !== ""
            text: shell.ctx.ctlError
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
        // 3. operator-gate hint (§T-1) — the ONLY site
        PC3.Label {
            Layout.fillWidth: true
            visible: !shell.ctx.controlsEnabled && shell.ctx.gateHint !== ""
            text: shell.ctx.gateHint
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }
        // 4. §V6-18 health block — ONE bounded advisory block (the
        // measured 4.14:1 orange text wall dies; the tint+glyph+border
        // carries the warning class, the words stay ≥7:1 readable).
        Rectangle {
            Layout.fillWidth: true
            visible: (shell.ctx.health || []).length > 0
            radius: Kirigami.Units.smallSpacing
            border.width: 1
            border.color: Kirigami.Theme.neutralTextColor
            opacity: 1
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                anchors.margins: parent.border.width
                radius: parent.radius - parent.border.width
                color: Kirigami.Theme.neutralTextColor
                opacity: 0.10
            }
            implicitHeight: healthCol.implicitHeight
                             + Kirigami.Units.smallSpacing * 2
            ColumnLayout {
                id: healthCol
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing * 0.5

                // Count header when >1 (the blob becomes bounded,
                // counted, separable — audit M6).
                Text {
                    visible: (shell.ctx.health || []).length > 1
                    text: "HEALTH · " + shell.ctx.health.length
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                    font.letterSpacing: 0.4
                }
                Repeater {
                    model: shell.ctx.health
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing * 0.5
                        Text {
                            text: "⚠"
                            color: Kirigami.Theme.neutralTextColor
                            font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        }
                        Text {
                            readonly property string full: String(modelData)
                            Layout.fillWidth: true
                            text: full
                            color: Kirigami.Theme.textColor
                            opacity: 0.85
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            HoverHandler { id: warnHover }
                            QQC2.ToolTip.text: full
                            QQC2.ToolTip.visible: warnHover.hovered
                        }
                    }
                }
            }
        }
        // §V-10 needs-login strip row (edge string ALSO renders in the
        // lane, §W-12 — the strip row is the standing reminder).
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.needsLogin
            text: "NEEDS LOGIN · RUN: tailscale login"
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }

        // ---- EXIT STRIP (§V6-7): confirmation-only, active-only ----
        ExitStrip {
            Layout.fillWidth: true
            ctx: shell.ctx
        }

        // ---- SEARCH ROW (§W-9): revealed only, above the lane -------
        SearchRow {
            id: searchRow
            visible: shell.ctx.searchOpen && shell.searchable()
            Layout.fillWidth: true
            ctx: shell.ctx
            onRequestFirstResult: shell.focusFirstResult()
        }

        // ---- LANE (§V6-2/§V6-16): the ONLY scroll region -----------
        PC3.ScrollView {
            id: lane
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            // §V-5 carries: scrollbar lane reserved so it never covers a
            // badge/button — measured: the floating Plasma scrollbar is
            // ~10px at gu=18, so reserve 0.8·gu past the content margins.
            ColumnLayout {
                id: laneContent
                width: lane.width - Kirigami.Units.gridUnit * 0.8
                       - Kirigami.Units.smallSpacing * 2
                // §V6-16: spacing 0 — the fold cuts ROWS, not gaps; a
                // half-visible name is the universal "there's more"
                // signal (audit M2).
                spacing: 0

                // -- edge rows (§W-12): PlaceholderMessage anatomy —
                //    32px status icon + one string, centered; header,
                //    strip, footer stay mounted (never a bare screen).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit * 2
                    Layout.bottomMargin: Kirigami.Units.gridUnit * 2
                    Layout.alignment: Qt.AlignHCenter
                    visible: shell.ctx.edgeState !== "ok"
                             || shell.ctx.needsLogin
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

                // -- 0 peers, running (§W-12)
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit * 2
                    Layout.bottomMargin: Kirigami.Units.gridUnit * 2
                    visible: shell.ctx.edgeState === "ok"
                             && !shell.ctx.needsLogin
                             && shell.ctx.peers.length === 0
                    text: "NO PEERS · TAILNET EMPTY"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignHCenter
                }

                // -- search mode (§W-9/§V6-9/§V6-10): IN PLACE — label
                //    states the denominator, matched chars bold in the
                //    rows, offline toggle hides.
                ColumnLayout {
                    visible: shell.ctx.peerQuery !== "" && shell.searchable()
                    Layout.fillWidth: true
                    spacing: 0

                    SectionLabel {
                        word: shell.ctx.searchResults.length > 0 ? "MATCHES" : ""
                        countText: shell.ctx.searchResults.length > 0
                                   ? shell.ctx.searchResults.length
                                     + " OF " + shell.ctx.peers.length : ""
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit
                        Layout.bottomMargin: Kirigami.Units.gridUnit
                        visible: shell.ctx.searchResults.length === 0
                        // §V6-9: the query echo IS the explanation.
                        text: "NO MATCHES · “" + shell.ctx.peerQuery + "”"
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: shell.ctx.searchResults
                        PeerRow {
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                            focusIndex: shell.focusIndex
                        }
                    }
                }

                // -- normal mode: the one list (§W-2) / all-offline
                //    aggregate mode (§V6-17)
                ColumnLayout {
                    visible: shell.ctx.peerQuery === "" && shell.searchable()
                    Layout.fillWidth: true
                    spacing: 0

                    SectionLabel {
                        // §V6-17.2: a zero-count ONLINE header is noise —
                        // when nothing is online the section IS offline.
                        word: shell.zeroOnline
                              ? "OFFLINE" : "ONLINE"
                        countText: shell.zeroOnline
                                   ? shell.ctx.offlinePeers.length
                                   : shell.ctx.onlinePeers.length
                    }

                    // §V6-17.3: the aggregate line — the number the
                    // audit demands, filling the former 472px void.
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: shell.zeroOnline
                        text: "0 of " + shell.ctx.peers.length
                              + " peers online · showing all offline"
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: shell.zeroOnline ? [] : shell.sortedOnline()
                        PeerRow {
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                            focusIndex: -1
                        }
                    }

                    // §W-10 offline toggle — standard (non-flat) Button,
                    // full-width, copy byte-identical to v0.4. Hidden
                    // while a query is active.
                    PC3.Button {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: shell.ctx.offlinePeers.length > 0
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                        topPadding: Kirigami.Units.smallSpacing * 0.5
                        bottomPadding: Kirigami.Units.smallSpacing * 0.5
                        text: shell.ctx.offlinePeers.length + " OFFLINE · "
                              + (shell.offlineExpanded ? "HIDE" : "SHOW")
                        onClicked: shell.offlineExpanded = !shell.offlineExpanded
                    }

                    // Offline rows — dimmed 0.62, only while expanded;
                    // candidates keep their `exit` role (survives the
                    // collapse) but never a use button (§W-10).
                    Repeater {
                        model: shell.ctx.offlinePeers
                        PeerRow {
                            visible: shell.offlineExpanded
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                            focusIndex: -1
                        }
                    }
                }
            }
        }

        // §V6-16 lane-bottom fade: 10px gradient, visible iff the lane
        // can scroll — at list end the fade is gone and the last row
        // sits clear of the footer hairline (audit M2/P4).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.55
            Layout.topMargin: -Kirigami.Units.gridUnit * 0.55
            z: 5
            visible: shell.laneFlick !== null && shell.laneFlick !== undefined
                     && shell.laneFlick.atYEnd === false
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop {
                    position: 1.0
                    color: Kirigami.Theme.backgroundColor
                }
            }
        }
        // §V6-16 fade references shell.laneFlick (declared at shell
        // scope — property declarations cannot be layout children).

        // ---- FOOTER (§V6-20): action bar + provenance ---------------
        Kirigami.Separator {
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.55
            spacing: Kirigami.Units.smallSpacing

            // §V6-20 freshness, relative (absolute in the tooltip).
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

            Item { Layout.preferredWidth: Kirigami.Units.largeSpacing - Kirigami.Units.smallSpacing }

            // §V6-8: the power control — §T-3 state machine VERBATIM
            // (labels, armed negative palette, 500ms dead-zone, 4s
            // window, disarm-perform), now a labeled standard Button at
            // the footer's right edge, ≥0.8·gu from the popup edge.
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
    }
}
