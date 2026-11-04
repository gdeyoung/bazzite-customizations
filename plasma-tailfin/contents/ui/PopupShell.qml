import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "tabs"

// §R-2 fixed frame + §R-6 shared chrome. ALL popup sizing lives in this
// file and nowhere else (sysmon single-site rule): 34×27·gu for every
// tab; children inherit, nothing feeds back into the frame.
Item {
    id: shell

    // The PlasmoidItem root (never named "root" here — shadowing trap).
    required property var ctx

    // §R-1: last tab persists via KConfig (default 0 = Status).
    property int currentTab: ctx.lastTabCfg
    onCurrentTabChanged: ctx.saveTab(currentTab)

    // §T-3/§T-5 popup open/close behavior: reopen dismisses the last op
    // error; close disarms the confirm.
    onVisibleChanged: {
        if (visible) {
            ctx.ctlError = ctx.ops.lastError = ""
        } else {
            ctx.disarmConfirm()
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

    Layout.minimumWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: Kirigami.Units.gridUnit * 27
    Layout.preferredHeight: Kirigami.Units.gridUnit * 27

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 1.5
        spacing: Kirigami.Units.smallSpacing

        // ---- Header (§R-6): identity + §T-3 power toggle --------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: shell.ctx.status && shell.ctx.status.selfName
                      ? shell.ctx.status.selfName
                      : "Tailscale"
                color: Kirigami.Theme.textColor
                font.bold: true
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            // §T-3: enabled styling is honest — normal textColor at
            // rest, negative only while armed; disabled palette only
            // when actually disabled (busy).
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

        // ---- Message strip (§R-6): BETWEEN header and TabBar, items 1–3
        // only (health warnings moved to the Health tab per §R-5 note).
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
        // 3. operator-gate hint (§T-1)
        PC3.Label {
            Layout.fillWidth: true
            visible: !shell.ctx.controlsEnabled && shell.ctx.gateHint !== ""
            text: shell.ctx.gateHint
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }

        // ---- Tabs (§R-1, sysmon house pattern) ------------------------
        PC3.TabBar {
            Layout.fillWidth: true
            currentIndex: shell.currentTab
            onCurrentIndexChanged: shell.currentTab = currentIndex

            PC3.TabButton { text: i18n("Status") }
            PC3.TabButton { text: i18n("Peers") }
            PC3.TabButton { text: i18n("Health") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: shell.currentTab

            StatusTab { ctx: shell.ctx }
            PeersTab { ctx: shell.ctx }
            HealthTab { ctx: shell.ctx }
        }
    }
}
