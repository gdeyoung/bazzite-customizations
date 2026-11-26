import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import ".." as U

// PerfTab — v0.7 Performance: 568|16|344 two-column card layout.
// LEFT: CPU (hero + numbered core grid + avg/busiest spark) and Memory
// (stacked bar + legend + spark + swap micro-bar). RIGHT: RightCards
// (GPU/NET/DISK). No collapsing, no footer — the fixed frame fits all.
Item {
    id: tab
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color cBlue: "#7aa2f7"
    readonly property color cViolet: "#bb9af7"
    readonly property color cGreen: "#3fd18b"

    readonly property real busiestCore: {
        let m = 0
        const p = sysmon.corePcts
        for (let i = 0; i < p.length; i++) if (p[i] > m) m = p[i]
        return m
    }
    // memory breakdown fractions [used, buff, cache, rest]
    readonly property var memFracs: {
        const t = sysmon.ramTotalMb
        if (t <= 0) return [0, 0, 0, 1]
        const u = sysmon.ramUsedMb / t
        const b = (sysmon.buffersKb / 1024) / t
        const c = (sysmon.cachedKb / 1024) / t
        return [u, b, c, Math.max(0, 1 - u - b - c)]
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ---- LEFT 568: CPU + MEMORY ------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: 568
            Layout.fillHeight: true
            spacing: 12

            U.SectionCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                title: "CPU"
                rightText: sysmon.load1.toFixed(2) + " \u00B7 " + sysmon.load5.toFixed(2) + " \u00B7 " + sysmon.load15.toFixed(2)

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: sysmon.cpuPct < 0 ? "\u2014" : Math.round(sysmon.cpuPct) + "%"
                            color: tab.fg
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                        Item { Layout.fillWidth: true }
                        ColumnLayout {
                            spacing: 0
                            U.MicroLabel { text: "busiest core" }
                            Text {
                                text: Math.round(tab.busiestCore) + "%"
                                color: tab.fg
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }

                    CoreGrid {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        corePcts: tab.sysmon.corePcts
                        perRow: 16
                        cellH: 56
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        U.MicroLabel { text: "avg \u00B7 busiest" }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: tab.sysmon.corePcts.length > 0 ? tab.sysmon.corePcts.length + " logical" : ""
                            color: tab.muted
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    Sparkline {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72
                        series: sysmon.histCoreAvg
                        seriesB: sysmon.histCoreMax
                        stroke: tab.cGreen
                        strokeB: tab.cViolet
                        fill: tab.cGreen
                    }
                }
            }

            U.SectionCard {
                id: memCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Memory"
                rightText: sysmon.swapUsedKb > 1024
                    ? ("swap " + sysmon.fmtGbB(sysmon.swapUsedKb) + " \u00B7 " + Math.round(100 * sysmon.swapUsedKb / Math.max(1, sysmon.swapTotalKb)) + "%")
                    : ""

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: sysmon.fmtSizeP(sysmon.ramUsedMb * 1048576)
                            color: tab.fg
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            Layout.leftMargin: 8
                            Layout.alignment: Qt.AlignBaseline
                            text: "/ " + sysmon.fmtSizeP(sysmon.ramTotalMb * 1048576)
                            color: tab.muted
                            font.pixelSize: 14
                            font.features: ({ "tnum": 1 })
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(sysmon.ramPct) + "%"
                            color: sysmon.levelColor(sysmon.ramPct)
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                    }

                    // stacked used/buff/cache/avail bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14
                        radius: 7
                        color: Qt.alpha(tab.fg, 0.08)
                        Row {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width
                            Item {
                                width: parent.width * tab.memFracs[0]; height: parent.height
                                Rectangle { anchors.fill: parent; color: tab.cBlue }
                            }
                            Item {
                                width: parent.width * tab.memFracs[1]; height: parent.height
                                Rectangle { anchors.fill: parent; color: Qt.alpha(tab.cViolet, 0.55) }
                            }
                            Item {
                                width: parent.width * tab.memFracs[2]; height: parent.height
                                Rectangle { anchors.fill: parent; color: Qt.alpha(tab.cViolet, 0.3) }
                            }
                        }
                    }

                    U.MicroLabel {
                        Layout.fillWidth: true
                        text: "used " + sysmon.fmtGb(sysmon.ramUsedMb)
                            + " \u00B7 buff " + sysmon.fmtGbB(sysmon.buffersKb)
                            + " \u00B7 cache " + sysmon.fmtGbB(sysmon.cachedKb)
                            + " \u00B7 avail " + sysmon.fmtGb(Math.max(0, sysmon.ramTotalMb - sysmon.ramUsedMb - sysmon.buffersKb / 1024 - sysmon.cachedKb / 1024))
                    }

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        series: sysmon.histRam
                        stroke: tab.cBlue
                        fill: tab.cBlue
                    }

                    // swap micro-bar (only when swap is in use)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        visible: sysmon.swapUsedKb > 1024
                        color: Qt.alpha(tab.fg, 0.08)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.min(1, sysmon.swapUsedKb / Math.max(1, sysmon.swapTotalKb))
                            radius: 3
                            color: tab.cViolet
                        }
                    }
                }
            }
        }

        // ---- RIGHT 344: GPU / NET / DISK --------------------------------------
        RightCards {
            Layout.preferredWidth: 344
            Layout.fillHeight: true
            sysmon: tab.sysmon
        }
    }
}
