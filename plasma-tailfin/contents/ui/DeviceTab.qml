import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import QtQuick.Controls as QQC2

// §V7-7 DeviceTab — deep self facts [TS self page + MAC/Win "This
// device" zone]. Groups: THIS DEVICE (dns, ipv6) · OPTIONS · READ-ONLY
// (facts from the §T-1 debug-prefs probe — no new exec source) ·
// HEALTH (the Trayscale TODO, filled). Glance facts stay in the
// header; nothing here duplicates them.
Item {
    id: tab

    required property var ctx

    readonly property var prefs: Model.parsePrefs(ctx.gatePrefs)
    readonly property var health: ctx.health || []

    PC3.ScrollView {
        id: devScroll
        anchors.fill: parent
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: devScroll.width - Kirigami.Units.gridUnit * 0.8
            spacing: Kirigami.Units.smallSpacing * 0.5

            // ---- THIS DEVICE
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
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
                PC3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: ctx.status ? ctx.status.selfDnsName : ""
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideMiddle
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }
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
                PC3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: ctx.selfIp6
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.features: ({ "tnum": 1 })
                    elide: Text.ElideMiddle
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // ---- OPTIONS · READ-ONLY (§T-8: the allowlist stays closed)
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: "OPTIONS · READ-ONLY"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                font.letterSpacing: 0.4
            }
            Repeater {
                model: tab.prefs.ok ? [
                    { label: "route all traffic", on: tab.prefs.routeAll,
                      tip: "route all traffic through an exit node when one is active",
                      vOn: "on", vOff: "off" },
                    { label: "lan access", on: tab.prefs.allowLanAccess,
                      tip: "allow LAN access while an exit node is active",
                      vOn: "allowed", vOff: "blocked" },
                    { label: "shields up", on: tab.prefs.shieldsUp,
                      tip: "reject incoming connections from other peers",
                      vOn: "on", vOff: "off" },
                    { label: "override dns", on: tab.prefs.corpDns,
                      tip: "use the tailnet's DNS settings on this device",
                      vOn: "on", vOff: "off" }
                ] : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.85
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        text: modelData.label
                        color: Kirigami.Theme.textColor
                        opacity: 0.62
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.on ? modelData.vOn : modelData.vOff
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    HoverHandler { id: optHover }
                    QQC2.ToolTip.text: modelData.tip
                                       + " · read-only — change it with the tailscale CLI"
                    QQC2.ToolTip.visible: optHover.hovered
                }
            }
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: !tab.prefs.ok
                text: "unavailable"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // ---- HEALTH (scope: THIS DEVICE — daemon-level warnings)
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
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                visible: tab.health.length === 0
                text: "no health warnings"
                color: Kirigami.Theme.textColor
                opacity: 0.62
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }
    }
}
