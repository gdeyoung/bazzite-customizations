import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V6-7 ExitStrip (replaces RoutingBand.qml): confirmation-only,
// active-only. The ROW owns the exit state and its controls (§V6-6);
// this strip is one tinted sentence that confirms what is happening to
// ALL traffic — no controls, no counts, no × (audit B2: the band's ×
// read as "close popup" and sat 30px from the search ✕ in the same
// column). Renders ONLY while running AND an exit node is active; the
// no-exit fact lives in the header identity line (§V6-14).
Item {
    id: strip

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    readonly property string activeName: ctx.exitBannerText()

    visible: ctx.running && activeName !== ""
    implicitHeight: Kirigami.Units.gridUnit * 1.55
    Layout.fillWidth: true

    // Hairline above only — the section label's rule below separates
    // the strip from the lane (§V6-7).
    Kirigami.Separator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.bottom: parent.bottom
        color: Kirigami.Theme.highlightColor
        opacity: 0.10
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.gridUnit * 0.8
        anchors.topMargin: 1
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.9
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.9
            source: "network-vpn"
            isMask: true
            color: Kirigami.Theme.highlightColor
        }

        PC3.Label {
            text: "all traffic routing through"
            color: Kirigami.Theme.textColor
            opacity: 0.62
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            elide: Text.ElideRight
        }

        PC3.Label {
            Layout.fillWidth: true
            text: strip.activeName
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.72
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }

        // §T-4 in-flight transient (exit-set): the strip persists until
        // the poll tick confirms (exit-clear), then disappears.
        PC3.Label {
            visible: strip.ctx.ctlBusy && strip.ctx.currentOp === "exit-set"
            text: "switching…"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }
}
