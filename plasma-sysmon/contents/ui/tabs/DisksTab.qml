import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".."
import ".." as U

// DisksTab — v0.7. Two columns inside the fixed 960x640 frame:
//   LEFT  (fill): volumes table — 32px rows in a ListView (scrolls when the
//          host has more mounts than fit; swap appended as a final row when
//          in use). A plain ColumnLayout here overflowed the fixed frame on
//          this host (13 mounts + swap + 11 disks >> 640px) — lists scroll,
//          columns clip.
//   RIGHT (320): per-disk IO stack — name/rates line + dual spark (R blue,
//          W red) per whole disk, fed by the v0.7 disks[] /proc/diskstats
//          counters. 11 disks x ~48px fits the column height.
Item {
    id: tab
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color cBlue: "#7aa2f7"
    readonly property color cRed: "#f4405c"
    readonly property var diskNames: {
        const a = []
        for (const k in sysmon.diskRates) a.push(k)
        a.sort()
        return a
    }
    // volumes + optional swap row as one model for the ListView
    readonly property var volModel: {
        const m = sysmon.vols.map(v => ({ kind: "vol", v: v }))
        if (sysmon.swapUsedKb > 1024) m.push({ kind: "swap" })
        return m
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ================= LEFT: volumes =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                U.MicroLabel { text: "volumes \u00B7 " + sysmon.vols.length + " mounted" }
                Item { Layout.fillWidth: true }
                Text {
                    visible: sysmon.diskDev !== ""
                    text: sysmon.diskDev
                        + " \u00B7 R " + sysmon.fmtRateLong(Math.max(0, sysmon.diskReadBps))
                        + " \u00B7 W " + sysmon.fmtRateLong(Math.max(0, sysmon.diskWriteBps))
                    color: tab.muted
                    font.pixelSize: 11
                    font.features: ({ "tnum": 1 })
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                spacing: 8
                U.MicroLabel { Layout.preferredWidth: 236; text: "usage" }
                U.MicroLabel { Layout.preferredWidth: 112; horizontalAlignment: Text.AlignRight; text: "used / size" }
                U.MicroLabel { Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; text: "pct" }
                U.MicroLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: "mount \u00B7 fs" }
            }

            ListView {
                id: volList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                boundsMovement: Flickable.StopAtBounds
                PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }
                spacing: 0
                model: tab.volModel

                delegate: Item {
                    width: volList.width
                    height: 32
                    required property var modelData

                    function rowPct() {
                        return modelData.kind === "swap"
                            ? 100 * sysmon.swapUsedKb / Math.max(1, sysmon.swapTotalKb)
                            : modelData.v.pct
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 0
                        spacing: 8

                        Item {
                            Layout.preferredWidth: 236
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 224
                                height: 10
                                radius: 5
                                color: Qt.alpha(tab.fg, 0.10)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * Math.min(1, rowPct() / 100)
                                    radius: 5
                                    color: modelData.kind === "swap" ? "#bb9af7" : sysmon.levelColor(modelData.v.pct)
                                }
                            }
                        }
                        Text {
                            Layout.preferredWidth: 112
                            horizontalAlignment: Text.AlignRight
                            text: modelData.kind === "swap"
                                ? sysmon.fmtGbB(sysmon.swapUsedKb) + " / " + sysmon.fmtGbB(sysmon.swapTotalKb)
                                : sysmon.fmtDisk(modelData.v.usedB) + " / " + sysmon.fmtDisk(modelData.v.sizeB)
                            color: tab.fg
                            font.pixelSize: 12
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            Layout.preferredWidth: 40
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(rowPct()) + "%"
                            color: modelData.kind === "swap" ? tab.muted : sysmon.levelColor(modelData.v.pct)
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            // elide-LEFT: the tail of a long path is what varies
                            text: modelData.kind === "swap"
                                ? "swap"
                                : modelData.v.mnt + "  \u00B7  " + modelData.v.fs
                            elide: Text.ElideLeft
                            color: tab.fg
                            font.pixelSize: 12
                        }
                    }
                    U.Hair {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }

        // ================= RIGHT: per-disk IO =================
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.fillHeight: true
            spacing: 4

            U.MicroLabel { text: "disk io \u00B7 per device" }
            ListView {
                id: ioList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                boundsMovement: Flickable.StopAtBounds
                PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }
                spacing: 0
                model: tab.diskNames

                delegate: Item {
                    width: ioList.width
                    height: 44
                    required property string modelData
                    readonly property var rates: sysmon.diskRates[modelData] || [0, 0, 0, 0]

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: modelData
                                color: tab.fg
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                text: "R " + sysmon.fmtRateLong(rates[0])
                                    + " \u00B7 W " + sysmon.fmtRateLong(rates[1])
                                    + " \u00B7 " + Math.round(rates[2]) + "/" + Math.round(rates[3])
                                color: tab.muted
                                font.pixelSize: 11
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        // dual spark: read blue, write red — logical coords only
                        Canvas {
                            id: diskSpark
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            property var hist: sysmon.diskHist[modelData] || { r: [], w: [] }
                            onHistChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const r = hist.r, w = hist.w
                                if (r.length < 2) return
                                let mx = 0
                                for (let i = 0; i < r.length; i++) if (r[i] > mx) mx = r[i]
                                for (let i = 0; i < w.length; i++) if (w[i] > mx) mx = w[i]
                                if (mx <= 0) mx = 1
                                const draw = (arr, color) => {
                                    ctx.strokeStyle = color
                                    ctx.lineWidth = 1
                                    ctx.beginPath()
                                    for (let i = 0; i < arr.length; i++) {
                                        const x = 1 + (i / (arr.length - 1)) * (width - 2)
                                        const y = height - 2 - (arr[i] / mx) * (height - 4)
                                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                    }
                                    ctx.stroke()
                                }
                                draw(r, tab.cBlue)
                                draw(w, tab.cRed)
                            }
                        }
                    }
                    U.Hair {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        color: Qt.alpha(tab.fg, 0.05)
                    }
                }
            }
        }
    }
}
