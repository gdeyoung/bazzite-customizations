import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// DrivewayPopup — fullRepresentation for com.gdeyoung.plasma.driveway.
// Ported from the Omarchy plugin's Panel.qml three-tab layout: Drives
// (USB/local disks + System row), Shares (config-defined SMB/NFS/sshfs),
// Cloud (rclone remotes). Popup self-sizes to the visible tab (house
// rule). Row files each own their single action handler; this file holds
// only the refresh button's (port law: one handler name per file).
Item {
    id: popup
    required property var driveway

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color urgentC: Kirigami.Theme.negativeTextColor
    readonly property string glyphFont: driveway ? driveway.glyphFont : ""
    readonly property int fullWarnPct: driveway ? driveway.fullWarnPct : 90
    property int currentTab: 0

    // Self-sizing popup: height tracks the visible tab only (StackLayout
    // default is max-of-all-children — the sysmon lesson).
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredHeight: headerRow.implicitHeight + tabs.implicitHeight
        + pages.children[currentTab].implicitHeight + Kirigami.Units.smallSpacing * 4
    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: headerRow
            Layout.margins: Kirigami.Units.smallSpacing * 2
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2

            Text {
                text: "Driveway"
                color: popup.fg
                font.bold: true
                font.pixelSize: Kirigami.Units.gridUnit * 0.8
            }
            Item { Layout.fillWidth: true }
            PC3.ToolButton {
                icon.name: "view-refresh"
                display: PC3.ToolButton.IconOnly
                onClicked: popup.driveway.refresh()
                PC3.ToolTip.text: qsTr("Refresh now")
                PC3.ToolTip.visible: hovered
            }
        }

        PC3.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: popup.currentTab
            onCurrentIndexChanged: popup.currentTab = tabs.currentIndex
            PC3.TabButton { text: qsTr("Drives") }
            PC3.TabButton { text: qsTr("Shares") }
            PC3.TabButton { text: qsTr("Cloud") }
        }

        PC3.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: pages
                width: scroll.availableWidth
                // Track ONLY the visible page (self-sizing popup rule).
                height: children[currentTab].implicitHeight
                currentIndex: popup.currentTab

                // ============ DRIVES: USB/local disks, System row =========
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: popup.driveway ? popup.driveway.drives : []
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            DriveRow {
                                Layout.fillWidth: true
                                drive: parent.modelData
                                busyResult: popup.driveway.busyFor(parent.modelData)
                                fullWarnPct: popup.fullWarnPct
                                glyphFont: popup.glyphFont
                                driveway: popup.driveway
                            }
                            BusyNotice {
                                Layout.fillWidth: true
                                visible: !!popup.driveway.busyFor(parent.modelData)
                                busyResult: popup.driveway.busyFor(parent.modelData)
                                drive: parent.modelData
                                driveway: popup.driveway
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: popup.driveway && popup.driveway.drives.length === 0
                        text: qsTr("No drives. Plug one in — it shows up here.")
                        color: popup.muted
                        font: Kirigami.Theme.smallFont
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // ============ SHARES: config-defined SMB/NFS/sshfs =========
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        Layout.fillWidth: true
                        visible: popup.driveway && popup.driveway.shareRows.length > 0
                        text: qsTr("Shares are configured in the widget settings")
                        color: popup.muted
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: popup.driveway ? popup.driveway.shareRows : []
                        ShareRow {
                            required property var modelData
                            Layout.fillWidth: true
                            share: modelData
                            driveway: popup.driveway
                            glyphFont: popup.glyphFont
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: popup.driveway && popup.driveway.shareRows.length === 0
                        text: qsTr("No shares configured. Add SMB/NFS/sshfs entries in the widget settings (gear → Shares).")
                        color: popup.muted
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }
                }

                // ============ CLOUD: rclone remotes ========================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        Layout.fillWidth: true
                        visible: popup.driveway && popup.driveway.cloud
                                 && !popup.driveway.cloud.rclone
                        text: qsTr("rclone is not installed — the Cloud tab needs it. Install it with your package manager, then refresh.")
                        color: popup.muted
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: popup.driveway ? popup.driveway.cloudDrives : []
                        CloudRow {
                            required property var modelData
                            Layout.fillWidth: true
                            remote: modelData
                            driveway: popup.driveway
                            glyphFont: popup.glyphFont
                            fullWarnPct: popup.fullWarnPct
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: popup.driveway && popup.driveway.cloud
                                 && popup.driveway.cloud.rclone
                                 && popup.driveway.cloudDrives.length === 0
                        text: qsTr("No rclone remotes yet. Add one with `rclone config` in a terminal, then refresh.")
                        color: popup.muted
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Text {
            Layout.margins: Kirigami.Units.smallSpacing * 2
            Layout.fillWidth: true
            visible: popup.driveway && popup.driveway.lastError !== ""
            text: popup.driveway ? popup.driveway.lastError : ""
            color: popup.urgentC
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }
    }
}
