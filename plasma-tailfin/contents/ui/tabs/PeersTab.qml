import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".."

// §R-4 Peers tab — two-column grid of PeerCell (alphabetical, Model
// sort), offline collapsed behind a computed count row. Zero scroll at
// 19 online (fit budget §R-2); scroll is the overflow valve past
// capacity or when offline is expanded — the frame never resizes.
Item {
    id: tab

    required property var ctx

    // Session-local expand state; config only seeds the default (§R-4).
    property bool offlineExpanded: ctx.showOffline

    // Offline toggle copy is computed, never literal (§R-7).
    readonly property string offlineToggleText:
        ctx.offlinePeers.length + " OFFLINE · " + (offlineExpanded ? "HIDE" : "SHOW")

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

        // ---- Zero peers: single centered line, nothing else (§R-4) ---
        PC3.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tab.ctx.edgeOverlayText() === ""
                     && tab.ctx.peers.length === 0
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: "NO PEERS · TAILNET EMPTY"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }

        // ---- Normal content -------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tab.ctx.edgeOverlayText() === ""
                     && tab.ctx.peers.length > 0
            spacing: Kirigami.Units.smallSpacing

            SectionLabel {
                rawText: "ONLINE · " + tab.ctx.onlinePeers.length
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: tab.ctx.onlinePeers.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: "NO ONLINE PEERS"
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }

            // Scroll surface: Flickable + explicit scrollbar lane, so the
            // bar never covers a `use` button (§R-2). When content fits,
            // the scrollbar is off — no pixels, zero scroll.
            Flickable {
                id: flick

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: peersContent.implicitHeight

                readonly property real lane: Kirigami.Units.gridUnit * 0.7
                readonly property bool needsScroll:
                    contentHeight > height + 1

                ColumnLayout {
                    id: peersContent
                    width: flick.width - (flick.needsScroll ? flick.lane : 0)
                    spacing: Kirigami.Units.smallSpacing

                    // Online grid — two columns, row-major, Model order.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Kirigami.Units.smallSpacing
                        rowSpacing: 0

                        Repeater {
                            model: tab.ctx.onlinePeers

                            PeerCell {
                                required property var modelData
                                peer: modelData
                                ctx: tab.ctx
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // ---- Offline section (default-collapsed, §R-4) ----
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: !tab.offlineExpanded
                                 && tab.ctx.offlinePeers.length > 0
                        horizontalAlignment: Text.AlignHCenter
                        text: tab.offlineToggleText
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont

                        MouseArea {
                            anchors.fill: parent
                            onClicked: tab.offlineExpanded = true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: tab.offlineExpanded
                                 && tab.ctx.offlinePeers.length > 0
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: tab.offlineToggleText
                            color: Kirigami.Theme.disabledTextColor
                            font: Kirigami.Theme.smallFont

                            MouseArea {
                                anchors.fill: parent
                                onClicked: tab.offlineExpanded = false
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Kirigami.Units.smallSpacing
                            rowSpacing: 0

                            Repeater {
                                model: tab.ctx.offlinePeers

                                PeerCell {
                                    required property var modelData
                                    peer: modelData
                                    ctx: tab.ctx
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                PC3.ScrollBar.vertical: PC3.ScrollBar {
                    policy: flick.needsScroll
                            ? PC3.ScrollBar.AsNeeded
                            : PC3.ScrollBar.AlwaysOff
                }
            }
        }
    }
}
