import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "Model.js" as Model

// §V-4 candidate row — the §T-9 action row, two lines (the §V-4 deviation
// ledger drops the tautological `routes:` line and `exit` tag):
//   line 1  ● name  [ACTIVE tag]                [use]
//   line 2  <ip> · <dns>   (smallFont, elide-middle)
//   line 3  switching…  (transient, in-flight target only, §T-4)
// Also used as the search result row (full width); pass result=true for
// the muted offline variant with `last seen` appended on line 2.
Item {
    id: row

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    required property var peer
    // Qt6 Repeater over a JS array of OBJECTS exposes no `modelData`
    // unless the delegate declares it required (v0.3 PeerCell law).
    required property var modelData
    required property bool result      // search-result variant
    readonly property bool online: peer.Online === true
    readonly property bool isActive: peer.Active === true
    readonly property bool isSwitchTarget:
        ctx.ctlSwitching !== "" && ctx.ctlSwitching === String(peer.DNSName || "")
    readonly property string name: ctx.peerName(peer)
    readonly property string line2: {
        const parts = [String((peer.TailscaleIPs || [])[0] || ""), String(peer.DNSName || "")]
        if (result && !online) parts.push("last seen " + Model.fmtLastSeen(peer.LastSeen))
        return parts.filter(function (p) { return p !== "" }).join(" · ")
    }

    implicitHeight: Kirigami.Units.gridUnit * (isSwitchTarget ? 2.6 : 1.5)

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.35
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.35
                radius: width / 2
                color: row.online ? Kirigami.Theme.positiveTextColor
                                  : Kirigami.Theme.disabledTextColor
            }

            PC3.Label {
                Layout.fillWidth: true
                text: row.name
                color: row.online ? Kirigami.Theme.textColor
                                  : Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.62
                elide: Text.ElideRight
            }

            // §V-4: ACTIVE tag — neutral, peer.Active.
            PC3.Label {
                visible: row.isActive
                text: "ACTIVE"
                color: Kirigami.Theme.neutralTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
            }

            // §T-4 verbatim: flat `use`, neutralTextColor, hover bg,
            // single click, tooltip teaches. Hidden on the active row and
            // when the gate is disabled. Hit ≥ 1.4·gu.
            PC3.ToolButton {
                visible: !row.isActive && row.ctx.controlsEnabled
                enabled: !row.ctx.ctlBusy
                flat: true
                text: i18n("use")
                QQC2.ToolTip.text: "use " + row.name + " as exit node"
                QQC2.ToolTip.visible: hovered
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onClicked: row.ctx.runControlOp("exit-set",
                                                String(row.peer.DNSName || ""))
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 0.35 + Kirigami.Units.smallSpacing
            text: row.line2
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideMiddle
            visible: text !== ""
        }

        // §T-4 transient: renders only on the in-flight target.
        PC3.Label {
            Layout.fillWidth: true
            visible: row.isSwitchTarget
            text: "switching…"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
    }
}
