import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §W-2 v0.5 popup: pinned chrome (header → message strip → routing band
// → revealed search row) → ONE SCROLLING PEER LANE → pinned footer.
// The v0.3 verdict IS the architecture: one big long list that scrolls.
// No tabs, no exit section, no census grid — exit candidates are rows
// (badge + use); the active exit node is a marked row AND the band.
//
// ALL popup sizing lives here and nowhere else (single-site rule):
// width 34·gu fixed; height min(38·gu, 0.9·available). The frame NEVER
// resizes on data, search, expand, or op flight — the lane is the
// overflow valve, and everything between band and footer is lane (the
// v0.4 121px dead band is structurally impossible here).
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
        }
    }

    // §W-9 keys: Ctrl+F → reveal + focus + select-all; Esc → clear the
    // query if non-empty, else collapse the revealed field, else blur.
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
            } else if (ctx.searchOpen) {
                ctx.searchOpen = false
                shell.forceActiveFocus()
            } else {
                searchRow.field.focus = false
            }
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

        // ---- HEADER (§W-7, 40px): self block + [search][power] -----
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
            spacing: Kirigami.Units.smallSpacing

            // Self identity block — single render site (dedup rule).
            // Self is NOT a row in the list (its facts are the header),
            // so lane counts equal chip counts exactly.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.35
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.35
                        radius: width / 2
                        color: shell.ctx.running
                               ? Kirigami.Theme.positiveTextColor
                               : Kirigami.Theme.neutralTextColor
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

                PC3.Label {
                    Layout.fillWidth: true
                    visible: shell.ctx.status !== null
                    text: {
                        const st = shell.ctx.status
                        const parts = [
                            st && st.backendState ? st.backendState.toUpperCase() : "STOPPED",
                            st && st.selfIp ? st.selfIp : "",
                            st && st.selfDnsName ? st.selfDnsName : ""
                        ]
                        return parts.filter(function (p) { return p !== "" }).join(" · ")
                    }
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font: Kirigami.Theme.smallFont
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
            // — the Trayscale/plasma-nm port. Hidden when nothing to
            // search.
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

            // §T-3 verbatim: normal textColor at rest, negative only
            // while armed; disabled palette only when actually disabled.
            PC3.ToolButton {
                visible: shell.ctx.controlsEnabled
                enabled: !shell.ctx.ctlBusy
                flat: true
                text: shell.ctx.ctlBusy ? "working…"
                      : shell.ctx.ctlArmed ? "Confirm disconnect"
                      : shell.ctx.running ? "Disconnect" : "Connect"
                palette.windowText: shell.ctx.ctlArmed
                                    ? Kirigami.Theme.negativeTextColor
                                    : Kirigami.Theme.textColor
                leftPadding: Kirigami.Units.smallSpacing * 1.5
                rightPadding: Kirigami.Units.smallSpacing * 1.5
                topPadding: Kirigami.Units.smallSpacing
                bottomPadding: Kirigami.Units.smallSpacing
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onClicked: shell.ctx.powerClicked()
            }
        }

        // ---- MESSAGE STRIP (§W-8; §T-5 items 1–4, order verbatim) ---
        // 1. armed warning (§T-3)
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlArmed
            text: "tailnet goes down here — remote access via ts.net drops until reconnect"
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        // 2. op error (§T-5)
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.ctlError !== ""
            text: shell.ctx.ctlError
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        // 3. operator-gate hint (§T-1) — the ONLY site
        PC3.Label {
            Layout.fillWidth: true
            visible: !shell.ctx.controlsEnabled && shell.ctx.gateHint !== ""
            text: shell.ctx.gateHint
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        // 4. health warnings — one row each, order preserved; wrap ≤2
        // lines then elide, full text in tooltip (§W-8). neutral/orange:
        // advisories, not failures (§W-15.5 deviation, ledgered).
        Repeater {
            model: shell.ctx.health
            Text {
                readonly property string full: "⚠ " + modelData
                Layout.fillWidth: true
                text: full
                color: Kirigami.Theme.neutralTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                HoverHandler { id: warnHover }
                QQC2.ToolTip.text: full
                QQC2.ToolTip.visible: warnHover.hovered
            }
        }
        // §V-10 needs-login strip row (edge string ALSO renders in the
        // lane, §W-12 — the strip row is the standing reminder).
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.needsLogin
            text: "NEEDS LOGIN · RUN: tailscale login"
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }

        // ---- ROUTING BAND (§W-6): both modes, only while running ----
        RoutingBand {
            visible: shell.ctx.running
            Layout.fillWidth: true
            ctx: shell.ctx
        }

        // ---- SEARCH ROW (§W-9): revealed only, above the lane -------
        SearchRow {
            id: searchRow
            visible: shell.ctx.searchOpen && shell.searchable()
            Layout.fillWidth: true
            ctx: shell.ctx
        }

        // ---- LANE (§W-5): the ONLY scroll region --------------------
        PC3.ScrollView {
            id: lane
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            // §V-5 carries: scrollbar lane reserved so it never covers a
            // badge/use/× — measured: the floating Plasma scrollbar is
            // ~10px at gu=18, so reserve 0.8·gu past the content margins
            // (vision-audit of the first v0.5 run showed ACTIVE EXIT and
            // CIDR badges clipped at smallSpacing*2).
            ColumnLayout {
                id: laneContent
                width: lane.width - Kirigami.Units.gridUnit * 0.8
                       - Kirigami.Units.smallSpacing * 2
                spacing: 2
                // Fold clearance: the last row always clears the footer
                // hairline at full scroll (vision-audit polish).
                Layout.bottomMargin: Kirigami.Units.smallSpacing

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

                // -- search mode (§W-9): IN PLACE — label flips to
                //    MATCHES, offline toggle hides, results render as
                //    ordinary PeerRows. No replacement, no void.
                ColumnLayout {
                    visible: shell.ctx.peerQuery !== "" && shell.searchable()
                    Layout.fillWidth: true
                    spacing: 2

                    SectionLabel {
                        rawText: shell.ctx.searchResults.length > 0
                                 ? "Matches · " + shell.ctx.searchResults.length : ""
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit
                        Layout.bottomMargin: Kirigami.Units.gridUnit
                        visible: shell.ctx.searchResults.length === 0
                        text: "NO MATCHING PEERS"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: shell.ctx.searchResults
                        PeerRow {
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                        }
                    }
                }

                // -- normal mode: the one list (§W-2)
                ColumnLayout {
                    visible: shell.ctx.peerQuery === "" && shell.searchable()
                    Layout.fillWidth: true
                    spacing: 2

                    SectionLabel {
                        rawText: "Online · " + shell.ctx.onlinePeers.length
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit
                        Layout.bottomMargin: Kirigami.Units.gridUnit
                        visible: shell.ctx.onlinePeers.length === 0
                        text: "NO ONLINE PEERS"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: shell.sortedOnline()
                        PeerRow {
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                        }
                    }

                    // §W-10 offline toggle — standard (non-flat) Button,
                    // full-width, copy byte-identical to v0.4; Breeze
                    // chrome fixes the "SHOW looked like footer text"
                    // defect. Hidden while a query is active.
                    PC3.Button {
                        Layout.fillWidth: true
                        visible: shell.ctx.offlinePeers.length > 0
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                        topPadding: Kirigami.Units.smallSpacing * 0.5
                        bottomPadding: Kirigami.Units.smallSpacing * 0.5
                        text: shell.ctx.offlinePeers.length + " OFFLINE · "
                              + (shell.offlineExpanded ? "HIDE" : "SHOW")
                        onClicked: shell.offlineExpanded = !shell.offlineExpanded
                    }

                    // Offline rows — dimmed 0.62, only while expanded;
                    // candidates keep their `exit` badge (role survives
                    // the collapse) but never a use button (§W-10).
                    Repeater {
                        model: shell.ctx.offlinePeers
                        PeerRow {
                            visible: shell.offlineExpanded
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                        }
                    }
                }
            }
        }

        // ---- FOOTER (§W-13; v0.4 verbatim) + tnum -------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: {
                    const stale = shell.ctx.statusStampMs === 0
                        || (shell.ctx.clockNow - shell.ctx.statusStampMs)
                           > shell.ctx.pollSeconds * 3 * 1000
                    const stamp = shell.ctx.statusStampMs > 0
                        ? new Date(shell.ctx.statusStampMs).toLocaleTimeString(Qt.locale(), "hh:mm:ss")
                        : "--:--:--"
                    return stale ? "◐ STALE · " + stamp : "● AS OF " + stamp
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.features: ({ "tnum": 1 })
                QQC2.ToolTip.text: "POLL EVERY " + shell.ctx.pollSeconds + " S"
                QQC2.ToolTip.visible: footHover.hovered
                HoverHandler { id: footHover }
            }

            PC3.Label {
                text: shell.ctx.gateState === "enabled"
                      ? "CONTROL ENABLED · " + shell.ctx.gateOperator
                      : shell.ctx.gateState === "disabled" ? "CONTROL DISABLED"
                      : "CONTROL UNAVAILABLE"
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
