import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".."

// §R-3 Status tab — this-device identity, backend pill, exit node.
// Edge states (§R-8) replace the content with centered copy; the shell
// keeps header and tabs mounted.
Item {
    id: tab

    required property var ctx

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ---- Edge state: centered copy, content replaced (§R-8) ------
        PC3.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: text !== ""
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAnywhere
            text: tab.ctx.edgeOverlayText()
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }

        // ---- Normal content -------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: tab.ctx.edgeOverlayText() === ""
            spacing: Kirigami.Units.smallSpacing

            SectionLabel { rawText: "THIS DEVICE" }

            Text {
                Layout.fillWidth: true
                text: tab.ctx.status && tab.ctx.status.selfName
                      ? tab.ctx.status.selfName
                      : "—"
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.8
                font.bold: true
                elide: Text.ElideRight
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: tab.ctx.status
                      ? [tab.ctx.status.selfIp, tab.ctx.status.selfDnsName]
                          .filter(function (p) { return p !== "" })
                          .join(" · ")
                      : ""
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideMiddle
            }

            // Backend pill: honest polled state, computed CAPS (§R-7).
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Kirigami.Units.gridUnit * 0.35
                    implicitHeight: Kirigami.Units.gridUnit * 0.35
                    radius: width / 2
                    color: tab.ctx.running
                           ? Kirigami.Theme.positiveTextColor
                           : Kirigami.Theme.negativeTextColor
                }

                Text {
                    text: tab.ctx.status && tab.ctx.status.backendState
                          ? tab.ctx.status.backendState.toUpperCase()
                          : "STOPPED"
                    color: tab.ctx.running
                           ? Kirigami.Theme.textColor
                           : Kirigami.Theme.negativeTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.62
                    font.bold: true
                }

                Item { Layout.fillWidth: true }
            }

            SectionLabel { rawText: "EXIT NODE" }

            // Active exit banner + §T-4 clear — byte-identical copy.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: tab.ctx.exitBannerText() !== ""

                PC3.Label {
                    Layout.fillWidth: true
                    text: "▸ exit node: " + tab.ctx.exitBannerText()
                    color: Kirigami.Theme.neutralTextColor
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                }

                PC3.ToolButton {
                    visible: tab.ctx.controlsEnabled
                    enabled: !tab.ctx.ctlBusy
                    flat: true
                    text: "×"
                    QQC2.ToolTip.text: "stop using exit node"
                    QQC2.ToolTip.visible: hovered
                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                    onClicked: tab.ctx.runControlOp("exit-clear")
                }
            }

            // Inactive + candidates exist: muted computed hint (§R-3).
            PC3.Label {
                Layout.fillWidth: true
                visible: tab.ctx.exitBannerText() === ""
                         && tab.ctx.exitCandidateCount() > 0
                text: "NO EXIT NODE · " + tab.ctx.exitCandidateCount()
                      + " CANDIDATES ON PEERS TAB"
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }   // keeps content top-anchored
    }
}
