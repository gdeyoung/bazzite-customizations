import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V-3/§V-5 single-view popup: header → identity → message strip (§T-5
// items 1–4, health restored) → search row → SCROLLING SECTION STACK
// (edge row | search results | EXIT NODES + ONLINE + OFFLINE) → footer.
// Tabs are gone (§V-2). ALL popup sizing lives here and nowhere else
// (single-site rule): width 34·gu fixed; height min(38·gu, 0.9·available).
// The ScrollView wraps the SECTION STACK ONLY — header, identity, strip,
// search, footer stay pinned (§V-5).
Item {
    id: shell

    // The PlasmoidItem root (never named "root" here — shadowing trap).
    required property var ctx

    // §V-8: search state lives on ctx (single source of truth; typing,
    // Esc, ✕, and popup-close clears all funnel through it).
    // (property declared on ctx in main.qml: peerQuery)

    // §T-3/§T-5 popup open/close behavior: reopen dismisses the last op
    // error; close disarms the confirm AND clears the query (§V-8 —
    // fresh open = fresh view).
    onVisibleChanged: {
        if (visible) {
            ctx.ctlError = ctx.ops.lastError = ""
            forceActiveFocus()
        } else {
            ctx.disarmConfirm()
            ctx.peerQuery = ""
        }
    }

    // §V-8 keys: Ctrl+F → focus + select-all; Esc → clear query if
    // non-empty, else blur.
    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            searchRow.field.forceActiveFocus()
            searchRow.field.selectAll()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (ctx.peerQuery !== "") {
                ctx.peerQuery = ""
                event.accepted = true
            } else {
                searchRow.field.focus = false
            }
        }
    }

    // §R-10: no synchronous work in the open handler — stamp refresh
    // defers ~150 ms; clockNow keeps ticking once per second while open
    // so the provenance ●/◐ verdict stays honest.
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

    // ---- Frame (§V-5) ------------------------------------------------
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

        // ---- Header (§V-3): hero selfName + §T-3 power toggle ------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.7
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: shell.ctx.status && shell.ctx.status.selfName
                      ? shell.ctx.status.selfName : "Tailscale"
                color: Kirigami.Theme.textColor
                font.bold: true
                font.pixelSize: Kirigami.Units.gridUnit * 0.8
                elide: Text.ElideRight
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

        // ---- Identity line (§V-4): ● STATE · ip · dns ----------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.1
            visible: shell.ctx.status !== null
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.35
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.35
                radius: width / 2
                color: shell.ctx.running ? Kirigami.Theme.positiveTextColor
                                         : Kirigami.Theme.neutralTextColor
            }

            PC3.Label {
                Layout.fillWidth: true
                text: {
                    const st = shell.ctx.status
                    const parts = [
                        st && st.backendState ? st.backendState.toUpperCase() : "STOPPED",
                        st && st.selfIp ? st.selfIp : "",
                        st && st.selfDnsName ? st.selfDnsName : ""
                    ]
                    return parts.filter(function (p) { return p !== "" }).join(" · ")
                }
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideMiddle
            }
        }

        // ---- Message strip (§T-5 items 1–4 + §V-10 login row) --------
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
        // 4. health warnings (§V-2: restored here from the dead Health
        // tab; one line each, wraps, order preserved)
        Repeater {
            model: shell.ctx.health
            Text {
                Layout.fillWidth: true
                text: "⚠ " + modelData
                color: Kirigami.Theme.negativeTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                wrapMode: Text.WordWrap
            }
        }
        // §V-10 needs-login row (strip position, not the edge row)
        PC3.Label {
            Layout.fillWidth: true
            visible: shell.ctx.needsLogin
            text: "NEEDS LOGIN · RUN: tailscale login"
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }

        // ---- Search row (§V-8) ---------------------------------------
        // Hidden when there is nothing to search: 0 peers or any of the
        // down/missing/login/parse edge states.
        SearchRow {
            id: searchRow
            Layout.fillWidth: true
            visible: shell.ctx.edgeState === "ok" && !shell.ctx.needsLogin
                     && shell.ctx.peers.length > 0
            ctx: shell.ctx
        }

        // ---- Section stack (the ONLY scrolling region) ----------------
        PC3.ScrollView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            // §V-5: scrollbar lane reserved so it never covers a
            // use/× button — right margin inside the content column.
            ColumnLayout {
                id: stackContent
                width: stack.width - Kirigami.Units.smallSpacing * 2
                spacing: 2

                // -- edge row (§V-10): replaces sections, standing
                //    header/strip/footer stay mounted outside.
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit * 2
                    Layout.bottomMargin: Kirigami.Units.gridUnit * 2
                    visible: shell.ctx.edgeState !== "ok"
                    text: shell.ctx.edgeOverlayText()
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                // 0 peers, running (§V-10): tailnet empty
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

                // -- search mode (§V-8): one 1-col result list replaces
                //    the sections.
                ColumnLayout {
                    visible: shell.ctx.peerQuery !== ""
                             && shell.ctx.edgeState === "ok"
                             && shell.ctx.peers.length > 0
                    Layout.fillWidth: true
                    spacing: 2

                    SectionLabel {
                        rawText: shell.ctx.searchResults.length > 0
                                 ? "Matches · " + shell.ctx.searchResults.length
                                 : ""
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: shell.ctx.searchResults.length === 0
                        text: "NO MATCHING PEERS"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        horizontalAlignment: Text.AlignHCenter
                        Layout.topMargin: Kirigami.Units.gridUnit
                        Layout.bottomMargin: Kirigami.Units.gridUnit
                    }
                    Repeater {
                        model: shell.ctx.searchResults
                        CandidateRow {
                            Layout.fillWidth: true
                            ctx: shell.ctx
                            peer: modelData
                            result: true
                        }
                    }
                }

                // -- sections (normal mode)
                ColumnLayout {
                    visible: shell.ctx.peerQuery === ""
                             && shell.ctx.edgeState === "ok"
                             && !shell.ctx.needsLogin
                             && shell.ctx.peers.length > 0
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    ExitNodeSection {
                        Layout.fillWidth: true
                        ctx: shell.ctx
                    }
                    CensusSection {
                        Layout.fillWidth: true
                        ctx: shell.ctx
                        mode: "online"
                    }
                    CensusSection {
                        id: offlineSection
                        Layout.fillWidth: true
                        ctx: shell.ctx
                        mode: "offline"
                    }
                }
            }
        }

        // ---- Footer (§V-4): provenance + gate verdict ------------------
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
                font: Kirigami.Theme.smallFont
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
