import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §W-6 RoutingBand — glance #2, BOTH modes, never ambiguous.
// Fixed 38px hairline-bounded band between the message strip and the
// lane; present whenever running; SAME height whether an exit node is
// active or not (the frame never jumps when an exit engages).
//
//   active:  [network-vpn 16px positive] ▸ exit node: <name>    [×]
//   none:    [network-vpn 16px muted]    no exit node · direct[ · N available]
//
// The band is routing STATE (verb); the PeerRow badge is the peer RECORD
// (noun) — no duplication (§W-15.1). Switching happens on rows (`use`);
// the band's "N available" count points into them. Gate off: band still
// renders (read-only fact); only buttons vanish (§T-1).
ColumnLayout {
    id: band

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    readonly property string activeName: ctx.exitBannerText()
    readonly property bool active: activeName !== ""

    spacing: 0
    Layout.fillWidth: true

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.9
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: "network-vpn"
            isMask: true
            color: band.active ? Kirigami.Theme.positiveTextColor
                               : Kirigami.Theme.textColor
            opacity: band.active ? 1 : 0.62
        }

        // ▸ exit node: <name> — §T-4 copy verbatim; <name> T2 DemiBold
        // (the one element that must stand out, Von Restorff).
        RowLayout {
            visible: band.active
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            PC3.Label {
                text: "▸ exit node:"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font: Kirigami.Theme.smallFont
            }
            PC3.Label {
                Layout.fillWidth: true
                text: band.activeName
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // §T-4 in-flight: switching… renders in the band (the band
            // is the clear target); × disabled while any op flies.
            PC3.Label {
                visible: band.ctx.ctlBusy && band.ctx.currentOp === "exit-clear"
                text: "switching…"
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }

            // §W-15.4: × becomes iconic (window-close-symbolic) with its
            // §T-4 tooltip — fixes "unexplained × 550px from its
            // content". Hit ≥ 1.4·gu, ≥ smallSpacing from band text.
            PC3.ToolButton {
                visible: band.ctx.controlsEnabled
                enabled: !band.ctx.ctlBusy
                flat: true
                icon.name: "window-close-symbolic"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: "stop using exit node"
                QQC2.ToolTip.visible: hovered
                Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                onClicked: band.ctx.runControlOp("exit-clear", "")
            }
        }

        // None active — sentence-case status fact, not a STATUS word
        // (§R-7); count clause omitted when 0 (§W-14).
        PC3.Label {
            visible: !band.active
            Layout.fillWidth: true
            text: {
                const n = band.ctx.exitCandidateCount()
                return n > 0
                    ? "no exit node · direct · " + n + " available"
                    : "no exit node · direct"
            }
            color: Kirigami.Theme.textColor
            opacity: 0.62
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }
}
