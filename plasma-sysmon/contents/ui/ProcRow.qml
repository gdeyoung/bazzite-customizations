import QtQuick
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// ProcRow — one 24px process row: NAME(fill)/USER/S/PID/CPU%/MEM%/RSS/1m/kill.
// Column widths mirror ProcsTab.procCols (fixed sum 472; NAME gets the rest).
// `owner` is the owning ProcsTab (colors, selection pid, sysmon, pidHist).
Rectangle {
    id: row
    required property var owner
    required property var modelData   // view-injected: [pid, user, name, pcpu, pmem, rss_kb, state, args]
    readonly property var m: modelData

    width: ListView.view ? ListView.view.width : 0
    height: 24
    color: row.m[0] === owner.selectedPid
             ? Qt.alpha(owner.cGreen, 0.10)
             : (rowMa.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.05) : "transparent")

    Rectangle {  // selection left rail
        width: 2
        height: parent.height
        color: owner.cGreen
        visible: row.m[0] === owner.selectedPid
    }
    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: owner.selectedPid = row.m[0]
    }

    Row {
        anchors.fill: parent

        // NAME (fill) — tooltip carries the full command line
        Item {
            width: row.width - owner.fixedW
            height: parent.height
            Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                verticalAlignment: Text.AlignVCenter
                text: row.m[2]
                color: Kirigami.Theme.textColor
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            PC3.ToolTip.visible: nameMa.containsMouse
            PC3.ToolTip.text: row.m[7] !== "" ? row.m[7] : row.m[2]
            PC3.ToolTip.delay: 500
            MouseArea { id: nameMa; anchors.fill: parent; hoverEnabled: true }
        }
        // USER (in the probe since v0.1, displayed since v0.7)
        Item {
            width: 84; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                text: row.m[1]
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        // S(tate)
        Item {
            width: 24; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: row.m[6]
                color: owner.stateColor(row.m[6])
                font.pixelSize: 11
                font.bold: row.m[6] === "D" || row.m[6] === "Z"
            }
            PC3.ToolTip.visible: stateMa.containsMouse
            PC3.ToolTip.text: {
                const mm = { R: "running", S: "sleeping", D: "uninterruptible disk sleep",
                             Z: "zombie", T: "stopped", I: "idle (kernel thread)" }
                return mm[row.m[6]] || row.m[6]
            }
            MouseArea { id: stateMa; anchors.fill: parent; hoverEnabled: true }
        }
        // PID
        Item {
            width: 60; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: String(row.m[0])
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }
        }
        // CPU%
        Item {
            width: 60; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: Number(row.m[3]).toFixed(1)
                color: owner.cpuColor(Number(row.m[3]))
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }
        }
        // MEM%
        Item {
            width: 60; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: Number(row.m[4]).toFixed(1)
                color: Kirigami.Theme.textColor
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }
        }
        // RSS
        Item {
            width: 68; height: parent.height
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: owner.sysmon.fmtRss(Number(row.m[5]))
                color: Kirigami.Theme.textColor
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }
        }
        // 1m spark — logical coords only, no dpr in the paint path
        Item {
            width: 88; height: parent.height
            Canvas {
                id: miniSpark
                anchors.centerIn: parent
                width: 80
                height: 16
                property string series: owner.sysmon.pidHist[String(row.m[0])] || ""
                onSeriesChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const parts = series === "" ? [] : series.split(",")
                    if (parts.length < 2) return
                    ctx.strokeStyle = owner.cBlue
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    for (let i = 0; i < parts.length; i++) {
                        const x = 1 + (i / (parts.length - 1)) * (width - 2)
                        const y = height - 2 - (Math.min(100, Number(parts[i])) / 100) * (height - 4)
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
            }
        }
        // kill pill (existing mechanic, restyled)
        Item {
            width: 28; height: parent.height
            Rectangle {
                anchors.centerIn: parent
                width: 28; height: 18
                radius: 3
                color: Qt.alpha(owner.cRed, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: "kill"
                    color: owner.cRed
                    font.pixelSize: 10
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        owner.sysmon.killTermed = false
                        owner.sysmon.killTarget = row.m[0]
                    }
                }
            }
        }
    }
}
