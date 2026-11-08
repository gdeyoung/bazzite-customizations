import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import QtQuick.Controls as QQC2

// §V8-4 ConnectionTab — Omarchy `connection` tab grammar: HeroCard
// (identity + connect toggle §T-3) → THIS DEVICE → HEALTH →
// PREFERENCES (the four WRITABLE toggles, §V8-2 T2–T5) → READ-ONLY
// facts. Optimistic flip with revert-on-probe (Omarchy setPref
// pattern): pending[flag] holds the hoped-for value until the
// §T-1 debug-prefs re-probe lands (endControlOp re-probes) and
// clears the map — a failed op reverts to the daemon's truth.
Item {
    id: tab

    required property var ctx

    readonly property var prefs: Model.parsePrefs(ctx.gatePrefs)
    readonly property var health: ctx.health || []

    // §V8-2 optimistic toggle state, keyed by flag name.
    property var prefPending: ({})

    // Omarchy allowLanRelevant: exit node active (or already allowed).
    function exitActive() {
        const ps = ctx.peers || []
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].ExitNode === true) return true
        }
        return false
    }

    function prefChecked(flag, daemonValue) {
        const p = prefPending[flag]
        return p === undefined ? daemonValue : p
    }
    function prefToggled(flag, on) {
        const m = {}
        for (const k in prefPending) m[k] = prefPending[k]
        m[flag] = on
        prefPending = m
        ctx.runControlOp("pref-set", flag + ":" + (on ? "true" : "false"))
    }

    Connections {
        target: ctx
        // Probe landed: drop optimism, trust the daemon.
        function onGatePrefsChanged() { tab.prefPending = {} }
        // Op failed mid-flight: revert immediately (ctlError shows why).
        function onCtlErrorChanged() {
            if (ctx.ctlError !== "") tab.prefPending = {}
        }
    }

    PC3.ScrollView {
        id: connScroll
        anchors.fill: parent
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: connScroll.width - Kirigami.Units.gridUnit * 0.8
            spacing: Kirigami.Units.smallSpacing * 0.5

            // ---- HERO (§V8-1.5): identity + connect toggle ---------
            HeroCard {
                ctx: tab.ctx
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // ---- THIS DEVICE ----------------------------------------
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: "THIS DEVICE"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                spacing: Kirigami.Units.smallSpacing
                visible: ctx.status && ctx.status.selfDnsName !== ""
                PC3.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    text: "dns name"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                QQC2.TextField {
                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignRight
                    text: ctx.status ? ctx.status.selfDnsName : ""
                    readOnly: true
                    selectByMouse: true
                    background: null
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PC3.ToolButton {
                    flat: true
                    icon.name: "edit-copy-symbolic"
                    display: PC3.AbstractButton.IconOnly
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                    opacity: 0.55
                    QQC2.ToolTip.text: qsTr("Copy")
                    QQC2.ToolTip.visible: hovered
                    onClicked: ctx.copyToClipboard(ctx.status ? ctx.status.selfDnsName : "")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                spacing: Kirigami.Units.smallSpacing
                PC3.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    text: "address"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                QQC2.TextField {
                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignRight
                    text: (ctx.status && ctx.status.selfIp ? ctx.status.selfIp : "")
                          + "  ·  " + ctx.onlinePeers.length
                          + " of " + ctx.peers.length + " online"
                    readOnly: true
                    selectByMouse: true
                    background: null
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PC3.ToolButton {
                    flat: true
                    icon.name: "edit-copy-symbolic"
                    display: PC3.AbstractButton.IconOnly
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                    opacity: 0.55
                    QQC2.ToolTip.text: qsTr("Copy")
                    QQC2.ToolTip.visible: hovered
                    onClicked: ctx.copyToClipboard((ctx.status && ctx.status.selfIp ? ctx.status.selfIp : "")
                          + "  ·  " + ctx.onlinePeers.length
                          + " of " + ctx.peers.length + " online")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                spacing: Kirigami.Units.smallSpacing
                visible: ctx.selfIp6 !== ""
                PC3.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    text: "ipv6"
                    color: Kirigami.Theme.textColor
                    opacity: 0.62
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                QQC2.TextField {
                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignRight
                    text: ctx.selfIp6
                    readOnly: true
                    selectByMouse: true
                    background: null
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PC3.ToolButton {
                    flat: true
                    icon.name: "edit-copy-symbolic"
                    display: PC3.AbstractButton.IconOnly
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                    opacity: 0.55
                    QQC2.ToolTip.text: qsTr("Copy")
                    QQC2.ToolTip.visible: hovered
                    onClicked: ctx.copyToClipboard(ctx.selfIp6)
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // ---- HEALTH (daemon-level warnings) ---------------------
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: "HEALTH"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            Repeater {
                model: tab.health
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing * 0.5
                    Text {
                        text: "⚠"
                        color: Kirigami.Theme.neutralTextColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    }
                    PC3.Label {
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
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: tab.health.length === 0
                text: "no health warnings"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // ---- PREFERENCES (§V8-2: WRITABLE toggles) --------------
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: "PREFERENCES"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }

            ToggleRow {
                visible: tab.prefs.ok
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                label: "Accept routed addresses"
                description: "--accept-routes: use subnet routes advertised by peers"
                checked: tab.prefChecked("accept-routes", tab.prefs.routeAll === true)
                busy: ctx.ctlBusy
                enabled: ctx.controlsEnabled && !ctx.ctlBusy
                onFlipped: function (on) {
                    tab.prefToggled("accept-routes", on)
                }
            }
            ToggleRow {
                visible: tab.prefs.ok
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                label: "Accept DNS"
                description: "--accept-dns: use the tailnet DNS configuration"
                checked: tab.prefChecked("accept-dns", tab.prefs.corpDns === true)
                busy: ctx.ctlBusy
                enabled: ctx.controlsEnabled && !ctx.ctlBusy
                onFlipped: function (on) {
                    tab.prefToggled("accept-dns", on)
                }
            }
            ToggleRow {
                visible: tab.prefs.ok
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                label: "Shields up"
                description: "Block incoming connections from the tailnet"
                checked: tab.prefChecked("shields-up", tab.prefs.shieldsUp === true)
                busy: ctx.ctlBusy
                enabled: ctx.controlsEnabled && !ctx.ctlBusy
                onFlipped: function (on) {
                    tab.prefToggled("shields-up", on)
                }
            }
            ToggleRow {
                // Omarchy allowLanRelevant — visible when an exit node
                // is active or the pref is already on.
                visible: tab.prefs.ok
                          && (tab.exitActive()
                              || tab.prefs.allowLanAccess === true)
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                label: "Allow LAN access"
                description: "While using an exit node, reach local devices directly"
                checked: tab.prefChecked("exit-node-allow-lan-access",
                                         tab.prefs.allowLanAccess === true)
                busy: ctx.ctlBusy
                enabled: ctx.controlsEnabled && !ctx.ctlBusy
                onFlipped: function (on) {
                    tab.prefToggled("exit-node-allow-lan-access", on)
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: !tab.prefs.ok
                text: "preferences unavailable — " + ctx.gateHint
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }
    }
}
