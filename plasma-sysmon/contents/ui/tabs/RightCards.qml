import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import ".." as U

// RightCards — Performance right column (344px): GPU (conditional) / Network
// / Disk cards. When the GPU card hides, NET and DISK grow equally
// (fillHeight). Every card = hero + graph + detail row — no bare numbers.
ColumnLayout {
    id: col
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color cBlue: "#7aa2f7"
    readonly property color cCyan: "#7dcfff"
    readonly property color cViolet: "#bb9af7"
    readonly property color cRed: "#f4405c"
    readonly property color cAmber: "#e5c07b"

    spacing: 12

    U.SectionCard {
        visible: sysmon.gpuBusyPct >= 0 || sysmon.gpuTempC >= 0
        Layout.fillWidth: true
        Layout.preferredHeight: 168
        title: "GPU"
        rightText: sysmon.gpuPowerMw >= 0 ? (sysmon.gpuPowerMw / 1000).toFixed(1) + " W" : ""

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: sysmon.gpuBusyPct >= 0 ? Math.round(sysmon.gpuBusyPct) + "%" : "\u2014"
                    color: col.fg
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Item { Layout.fillWidth: true }
                U.MicroLabel {
                    text: sysmon.vramUsedB >= 0
                        ? ("vram " + sysmon.fmtRate(sysmon.vramUsedB) + "/" + sysmon.fmtRate(sysmon.vramTotalB))
                        : ""
                }
            }
            Sparkline {
                Layout.fillWidth: true
                Layout.fillHeight: true
                series: sysmon.histGpuBusy
                stroke: col.cAmber
                fill: col.cAmber
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Gauge {
                    Layout.fillWidth: true
                    label: "VRAM"
                    pct: sysmon.vramTotalB > 0 ? 100 * sysmon.vramUsedB / sysmon.vramTotalB : 0
                    color: col.cBlue
                }
                Gauge {
                    Layout.fillWidth: true
                    label: "GTT"
                    pct: sysmon.gttTotalB > 0 ? 100 * sysmon.gttUsedB / sysmon.gttTotalB : 0
                    color: col.cViolet
                }
            }
        }
    }

    U.SectionCard {
        Layout.fillWidth: true
        Layout.preferredHeight: 172
        Layout.fillHeight: true
        title: "Network"
        rightText: sysmon.netDownBps < 0 ? "" : sysmon.fmtRate(sysmon.netDownBps)

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            function topIfs() {
                const arr = []
                for (const k in sysmon.ifRates) arr.push([k, sysmon.ifRates[k][0] + sysmon.ifRates[k][1]])
                arr.sort((a, b) => b[1] - a[1])
                return arr.slice(0, 2).map(e => e[0])
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "\u2193 " + (sysmon.netDownBps < 0 ? "\u2014" : sysmon.fmtRateLong(sysmon.netDownBps))
                    color: col.cBlue
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    Layout.leftMargin: 8
                    Layout.alignment: Qt.AlignBaseline
                    text: "\u2191 " + (sysmon.netUpBps < 0 ? "\u2014" : sysmon.fmtRateLong(sysmon.netUpBps))
                    color: col.cCyan
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Item { Layout.fillWidth: true }
            }
            Repeater {
                model: parent.topIfs()
                RowLayout {
                    id: ifRow
                    required property string modelData
                    Layout.fillWidth: true
                    U.MicroLabel { text: ifRow.modelData }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: {
                            const r = col.sysmon.ifRates[ifRow.modelData]
                            return "\u2193" + col.sysmon.fmtRate(r ? r[0] : 0) + "  \u2191" + col.sysmon.fmtRate(r ? r[1] : 0)
                        }
                        color: col.fg
                        font.pixelSize: 10
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
            Sparkline {
                Layout.fillWidth: true
                Layout.fillHeight: true
                autoScale: true
                series: sysmon.histNetDown
                seriesB: sysmon.histNetUp
                stroke: col.cBlue
                strokeB: col.cCyan
            }
            U.MicroLabel { text: "down \u00B7 up" }
        }
    }

    U.SectionCard {
        Layout.fillWidth: true
        Layout.preferredHeight: 172
        Layout.fillHeight: true
        title: sysmon.diskDev !== "" ? "Disk \u00B7 " + sysmon.diskDev : "Disk"
        rightText: Math.round(sysmon.diskPct) + "%"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Math.round(sysmon.diskPct) + "%"
                    color: sysmon.levelColor(sysmon.diskPct)
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: sysmon.fmtDisk(sysmon.diskUsedB) + " / " + sysmon.fmtDisk(sysmon.diskTotalB)
                    color: col.muted
                    font.pixelSize: 12
                    font.features: ({ "tnum": 1 })
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: Qt.alpha(col.fg, 0.08)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.min(1, sysmon.diskPct / 100)
                    radius: 4
                    color: sysmon.levelColor(sysmon.diskPct)
                }
            }
            U.MicroLabel {
                text: "R " + sysmon.fmtRateLong(Math.max(0, sysmon.diskReadBps))
                    + " \u00B7 W " + sysmon.fmtRateLong(Math.max(0, sysmon.diskWriteBps))
                    + " \u00B7 " + Math.round(Math.max(0, sysmon.diskReadIops)) + "/" + Math.round(Math.max(0, sysmon.diskWriteIops)) + " iops"
            }
            Sparkline {
                Layout.fillWidth: true
                Layout.fillHeight: true
                autoScale: true
                series: sysmon.histDiskR
                seriesB: sysmon.histDiskW
                stroke: col.cBlue
                strokeB: col.cRed
            }
            U.MicroLabel { text: "read \u00B7 write" }
        }
    }
}
