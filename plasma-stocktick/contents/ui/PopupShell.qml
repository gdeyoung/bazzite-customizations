/*
 * PopupShell — tab bar + content + footer (spec B).
 * Fixed frame set by fullRepresentation root in main.qml (960×640 preferred,
 * 720×520 min). Tabs: MARKETS / WATCHLIST / PORTFOLIO, text-only with 2px
 * animated underline; last-used tab persists (config lastTab). Detail view
 * pushes over the whole shell when api.detailSymbol !== "".
 * Footer: session pill + as-of + manual refresh + SETTINGS GEAR.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: shell

    property var api
    readonly property var tabNames: ["MARKETS", "WATCHLIST", "PORTFOLIO"]
    property int currentTab: {
        var t = api.cfg.lastTab
        for (var i = 0; i < tabNames.length; i++)
            if (tabNames[i].toLowerCase() === t) return i
        return 0
    }

    onCurrentTabChanged: api.cfg.lastTab = tabNames[currentTab].toLowerCase()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- tab bar
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            Row {
                id: tabBar
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 24

                Repeater {
                    model: shell.tabNames

                    delegate: Item {
                        id: tabBtn
                        readonly property bool active: index === shell.currentTab
                        implicitWidth: tabText.implicitWidth
                        implicitHeight: 36

                        Text {
                            id: tabText
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            text: modelData
                            color: active ? Kirigami.Theme.textColor
                                          : Kirigami.Theme.disabledTextColor
                            font.pixelSize: 12
                            font.bold: active
                            font.letterSpacing: 0.6
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.currentTab = index
                        }
                    }
                }
            }

            // animated underline
            Rectangle {
                readonly property var btn: tabBar.children[shell.currentTab]
                // children[0..2] = delegates; index offset safe via Repeater order
                x: shell.currentTab < tabBar.children.length - 1
                   ? tabBar.children[shell.currentTab + 1] !== undefined
                     ? tabBar.children[shell.currentTab].x : 0
                   : 0
                y: parent.height - 2
                width: shell.currentTab < tabBar.children.length
                        && tabBar.children[shell.currentTab]
                        && tabBar.children[shell.currentTab].implicitWidth
                          ? tabBar.children[shell.currentTab].implicitWidth : 0
                height: 2
                color: Kirigami.Theme.textColor
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(1, 1, 1, 0.10)
            }
        }

        // ---- tab content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MarketsTab {
                id: marketsTab
                anchors.fill: parent
                api: shell.api
                cardModel: shell.api.marketModel
                visible: shell.currentTab === 0
            }
            WatchlistTab {
                anchors.fill: parent
                api: shell.api
                visible: shell.currentTab === 1
            }
            PortfolioTab {
                anchors.fill: parent
                api: shell.api
                visible: shell.currentTab === 2
            }
        }

        // ---- footer
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: Qt.rgba(1, 1, 1, 0.04)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    width: 8; height: 8; radius: 4
                    readonly property bool live: shell.api.freshData
                    color: live ? shell.api.cPos : Kirigami.Theme.disabledTextColor
                }
                Text {
                    text: (shell.api.freshData ? "LIVE" : "CLOSED")
                          + " · as of " + shell.api.asOfTime
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
                Item { Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    QQC2.ToolTip.text: "Refresh now"
                    QQC2.ToolTip.visible: hovered
                    onClicked: shell.api.refreshAll()
                }
                QQC2.ToolButton {
                    icon.name: "configure"
                    QQC2.ToolTip.text: "Settings — watchlist, rotation, refresh"
                    QQC2.ToolTip.visible: hovered
                    onClicked: shell.api.openConfigure()
                }
            }
        }
    }

    // ---- detail overlay (sibling of the layout, covers tabs + footer;
    // anchors to the shell root — never to a layout-managed item)
    Rectangle {
        anchors.fill: parent
        visible: shell.api.detailSymbol !== ""
        color: "#1d1f23"

        DetailView {
            anchors.fill: parent
            api: shell.api
            symbol: shell.api.detailSymbol
        }

        Behavior on opacity { NumberAnimation { duration: 180 } }
        opacity: shell.api.detailSymbol !== "" ? 1 : 0
    }
}
