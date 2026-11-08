import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V8-1.5 hero card — Omarchy PanelHero grammar: status dot + self
// name + state phrase, with the connect ToggleSwitch sitting right
// after the text block (NOT pinned to the far edge — preview.png
// rule). The toggle is §T-3: off→on fires `up`; on→off arms, second
// click fires `down` (confirm state shown by the strip in the shell).
// Thumb never lies: `checked` binds ctx.running until the op lands.
Rectangle {
    id: card

    required property var ctx

    readonly property bool busy: ctx.ctlBusy
    readonly property bool armed: ctx.ctlArmed

    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.gridUnit * 3.4
    radius: Kirigami.Units.smallSpacing * 1.25
    color: Qt.alpha(Kirigami.Theme.textColor, armed ? 0.10 : 0.05)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
        anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
        spacing: Kirigami.Units.smallSpacing * 1.5

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.45
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.45
            radius: width / 2
            color: card.ctx.needsLogin ? Kirigami.Theme.negativeTextColor
                   : card.ctx.running ? Kirigami.Theme.positiveTextColor
                   : Kirigami.Theme.disabledTextColor
        }

        ColumnLayout {
            spacing: 0

            PC3.Label {
                text: card.ctx.status && card.ctx.status.selfName
                      ? card.ctx.status.selfName : "Tailscale"
                color: Kirigami.Theme.textColor
                font.bold: true
                font.pixelSize: Kirigami.Units.gridUnit * 0.95
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            }
            PC3.Label {
                text: {
                    if (card.ctx.needsLogin) return "needs login"
                    if (!card.ctx.running) return "disconnected"
                    if (card.armed) return "confirm disconnect?"
                    if (card.busy) return "working…"
                    return card.ctx.status && card.ctx.status.activeMullvadExit
                            && card.ctx.status.activeMullvadExit !== ""
                          ? "exit node active"
                          : "connected"
                }
                color: card.armed ? Kirigami.Theme.negativeTextColor
                       : Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            }
        }

        Item {
            id: track
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.1
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.75
            Layout.alignment: Qt.AlignVCenter
            opacity: card.busy ? 0.4 : 1.0

            readonly property bool on: card.ctx.running

            PC3.AbstractButton {
                anchors.fill: parent
                hoverEnabled: true
                enabled: card.ctx.controlsEnabled && !card.busy
                onClicked: card.ctx.powerClicked()
                Accessible.role: Accessible.Button
                Accessible.name: card.ctx.running ? "Disconnect" : "Connect"

                background: Rectangle {
                    radius: height / 2
                    color: track.on ? Kirigami.Theme.highlightColor
                           : Kirigami.Theme.backgroundColor
                    opacity: track.on ? 0.85 : 1.0
                    border.width: 1
                    border.color: track.on ? Kirigami.Theme.highlightColor
                                  : Qt.alpha(Kirigami.Theme.textColor, 0.25)
                }
                contentItem: Item {
                    Rectangle {
                        width: parent.height - Kirigami.Units.smallSpacing * 0.7
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: track.on
                           ? parent.width - width
                             - Kirigami.Units.smallSpacing * 0.35
                           : Kirigami.Units.smallSpacing * 0.35
                        color: track.on ? Kirigami.Theme.highlightedTextColor
                               : Kirigami.Theme.textColor
                        opacity: track.on ? 1.0 : 0.7
                        Behavior on x {
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }
    }
}
