import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Details — fullRepresentation popup for com.gdeyoung.plasma.sysmon.
// Ported from gdeyoung/omarchy-sysmon DetailPopup.qml (Quickshell).
// Tabs: Performance (M/C/G/N/D sections), Disks, Processes, Hardware.
Item {
    id: details
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color accBlue: "#7aa2f7"
    readonly property color accViolet: "#bb9af7"
    readonly property color accGreen: "#3fb950"
    readonly property color accRed: "#f7768e"
    readonly property color accAmber: "#e5c07b"

    property int currentTab: 0

    // Popup geometry: self-sizing height — tracks the Performance page's
    // implicit content height plus header/tab chrome, so the first tab never
    // scrolls at any font scale. Width stays hand-tuned for the tables.
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredHeight: headerRow.implicitHeight + tabs.implicitHeight
        + pages.children[currentTab].implicitHeight + Kirigami.Units.smallSpacing * 4
    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
    Layout.minimumHeight: Kirigami.Units.gridUnit * 20

    component HwRow: RowLayout {
        id: hwRow
        property string label: ""
        property string value: ""
        spacing: Kirigami.Units.smallSpacing * 2
        Layout.fillWidth: true
        Text {
            text: hwRow.label
            color: details.muted
            font: Kirigami.Theme.smallFont
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
        }
        Text {
            text: hwRow.value
            textFormat: Text.PlainText
            color: details.fg
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    component StatText: Text {
        color: details.fg
        font: Kirigami.Theme.smallFont
    }

    component MutedText: Text {
        color: details.muted
        font: Kirigami.Theme.smallFont
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: headerRow
            Layout.margins: Kirigami.Units.smallSpacing * 2
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2

            Text {
                text: "SysMon"
                color: details.fg
                font.bold: true
                font.pixelSize: Kirigami.Units.gridUnit * 0.8
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [
                    { label: "CPU", temp: sysmon.cpuTempC },
                    { label: "GPU", temp: sysmon.gpuTempC },
                    { label: "NVMe", temp: sysmon.nvmeTempC }
                ]
                Rectangle {
                    required property var modelData
                    visible: modelData.temp >= 0
                    radius: height / 2
                    implicitWidth: chipText.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: chipText.implicitHeight + Kirigami.Units.smallSpacing
                    color: Kirigami.Theme.backgroundColor
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.label + " " + Math.round(modelData.temp) + "\u00B0"
                        color: modelData.temp >= 85 ? details.accRed : (modelData.temp >= 70 ? details.accAmber : details.fg)
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }

        PC3.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: details.currentTab
            onCurrentIndexChanged: details.currentTab = tabs.currentIndex
            PC3.TabButton { text: i18n("Performance") }
            PC3.TabButton { text: i18n("Disks") }
            PC3.TabButton { text: i18n("Processes") }
            PC3.TabButton { text: i18n("Hardware") }
        }

        PC3.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: pages
                width: scroll.availableWidth
                // Track ONLY the visible page. Default StackLayout sizing is
                // max-of-all-children, so the tall Hardware page made every
                // tab show a scrollbar even when its own content fit.
                height: children[currentTab].implicitHeight
                currentIndex: details.currentTab

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    SysSection {
                        Layout.fillWidth: true
                        title: "M \u00B7 Memory"
                        summary: Math.round(sysmon.ramPct) + "%"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing * 2
                            ColumnLayout {
                                spacing: 2
                                StatText { text: "used " + sysmon.fmtGb(sysmon.ramUsedMb) }
                                MutedText { text: "buff " + sysmon.fmtGbB(sysmon.buffersKb) }
                                MutedText { text: "cache " + sysmon.fmtGbB(sysmon.cachedKb) }
                                MutedText { visible: sysmon.swapUsedKb > 1024; text: "swap " + sysmon.fmtGbB(sysmon.swapUsedKb) }
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                                series: sysmon.histRam
                                stroke: details.accBlue
                                fill: details.accBlue
                            }
                        }
                    }

                    SysSection {
                        Layout.fillWidth: true
                        title: "C \u00B7 CPU"
                        summary: sysmon.cpuPct < 0 ? "--" : Math.round(sysmon.cpuPct) + "% \u00B7 load " + sysmon.load1.toFixed(2)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            MutedText {
                                text: "load " + sysmon.load1.toFixed(2) + " / " + sysmon.load5.toFixed(2) + " / " + sysmon.load15.toFixed(2)
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                                series: sysmon.histCoreAvg
                                seriesB: sysmon.histCoreMax
                                stroke: details.accGreen
                                strokeB: details.accViolet
                                fill: details.accGreen
                            }
                            MutedText { text: "avg (green) \u00B7 busiest core (violet)" }
                            CoreGrid {
                                Layout.fillWidth: true
                                corePcts: sysmon.corePcts
                                perRow: 16
                                barH: 22
                            }
                        }
                    }

                    SysSection {
                        Layout.fillWidth: true
                        title: "G \u00B7 GPU"
                        visible: sysmon.gpuBusyPct >= 0 || sysmon.gpuTempC >= 0
                        summary: sysmon.gpuBusyPct >= 0 ? Math.round(sysmon.gpuBusyPct) + "%" : ""
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                StatText {
                                    text: "power " + (sysmon.gpuPowerMw >= 0 ? (sysmon.gpuPowerMw / 1000).toFixed(1) + "W" : "--")
                                }
                                Item { Layout.fillWidth: true }
                                MutedText {
                                    text: "VRAM " + (sysmon.vramUsedB >= 0 ? sysmon.fmtRate(sysmon.vramUsedB).replace("0K", "0") + " / " + sysmon.fmtRate(sysmon.vramTotalB) : "--")
                                }
                                MutedText {
                                    text: "GTT " + (sysmon.gttUsedB >= 0 ? sysmon.fmtRate(sysmon.gttUsedB) + " / " + sysmon.fmtRate(sysmon.gttTotalB) : "--")
                                }
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                                series: sysmon.histGpuBusy
                                stroke: details.accAmber
                                fill: details.accAmber
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing * 2
                                Gauge {
                                    Layout.fillWidth: true
                                    label: "VRAM"
                                    pct: sysmon.vramTotalB > 0 ? 100 * sysmon.vramUsedB / sysmon.vramTotalB : 0
                                    color: details.accBlue
                                }
                                Gauge {
                                    Layout.fillWidth: true
                                    label: "GTT"
                                    pct: sysmon.gttTotalB > 0 ? 100 * sysmon.gttUsedB / sysmon.gttTotalB : 0
                                    color: details.accViolet
                                }
                            }
                        }
                    }

                    SysSection {
                        Layout.fillWidth: true
                        title: "N \u00B7 Network"
                        summary: sysmon.netText
                        expanded: false
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                                autoScale: true
                                series: sysmon.histNetDown
                                seriesB: sysmon.histNetUp
                                stroke: details.accBlue
                                strokeB: "#7dcfff"
                            }
                            HistBars {
                                Layout.fillWidth: true
                                series: sysmon.histNetDown
                                logScale: true
                                activeColor: details.accGreen
                                maxH: 26
                            }
                            Repeater {
                                model: {
                                    const names = []
                                    for (const k in sysmon.ifRates) names.push(k)
                                    return names
                                }
                                StatText {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    text: {
                                        const r = sysmon.ifRates[modelData]
                                        return modelData + "   \u2193" + sysmon.fmtRate(r ? r[0] : 0) + "   \u2191" + sysmon.fmtRate(r ? r[1] : 0)
                                    }
                                }
                            }
                            MutedText { text: "auto-scaled \u00B7 blue \u2193 / cyan \u2191" }
                        }
                    }

                    SysSection {
                        Layout.fillWidth: true
                        title: "D \u00B7 Disk"
                        summary: Math.round(sysmon.diskPct) + "% full"
                        expanded: false
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                StatText { text: "R " + sysmon.fmtRate(Math.max(0, sysmon.diskReadBps)) }
                                StatText { text: "W " + sysmon.fmtRate(Math.max(0, sysmon.diskWriteBps)) }
                                Item { Layout.fillWidth: true }
                                MutedText {
                                    text: Math.round(Math.max(0, sysmon.diskReadIops)) + "/" + Math.round(Math.max(0, sysmon.diskWriteIops)) + " iops"
                                }
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                                autoScale: true
                                series: sysmon.histDiskR
                                seriesB: sysmon.histDiskW
                                stroke: details.accBlue
                                strokeB: details.accRed
                            }
                        }
                    }

                    MutedText {
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: "click a section header to collapse \u2014 " + sysmon.histMax + " sample history"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    SysSection {
                        Layout.fillWidth: true
                        title: "Volumes"
                        summary: sysmon.vols.length + " mounted"
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            // aligned column header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                MutedText { text: "USAGE"; Layout.preferredWidth: Kirigami.Units.gridUnit * 9 }
                                MutedText {
                                    text: "USED / SIZE"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6.5
                                    horizontalAlignment: Text.AlignRight
                                }
                                MutedText {
                                    text: "PCT"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                    horizontalAlignment: Text.AlignRight
                                }
                                MutedText {
                                    text: "MOUNT"
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            Repeater {
                                model: sysmon.vols
                                RowLayout {
                                    id: volRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.55
                                        radius: 2
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: parent.width * Math.min(1, volRow.modelData.pct / 100)
                                            radius: 2
                                            color: sysmon.levelColor(volRow.modelData.pct)
                                        }
                                    }
                                    MutedText {
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6.5
                                        horizontalAlignment: Text.AlignRight
                                        text: sysmon.fmtDisk(volRow.modelData.usedB) + " / " + sysmon.fmtDisk(volRow.modelData.sizeB)
                                    }
                                    StatText {
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                        horizontalAlignment: Text.AlignRight
                                        color: sysmon.levelColor(volRow.modelData.pct)
                                        text: Math.round(volRow.modelData.pct) + "%"
                                    }
                                    StatText {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideLeft
                                        text: volRow.modelData.mnt
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        MutedText {
                            text: "PID"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                            horizontalAlignment: Text.AlignRight
                        }
                        MutedText { text: "COMMAND"; Layout.fillWidth: true }
                        MutedText {
                            text: "CPU%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                            horizontalAlignment: Text.AlignRight
                            color: sysmon.procSort === "cpu" ? details.fg : details.muted
                            font.bold: sysmon.procSort === "cpu"
                            MouseArea { anchors.fill: parent; onClicked: sysmon.procSort = "cpu" }
                        }
                        MutedText {
                            text: "MEM%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                            horizontalAlignment: Text.AlignRight
                            color: sysmon.procSort === "mem" ? details.fg : details.muted
                            font.bold: sysmon.procSort === "mem"
                            MouseArea { anchors.fill: parent; onClicked: sysmon.procSort = "mem" }
                        }
                        Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5 }
                    }

                    Repeater {
                        model: sysmon.sortedProcs
                        RowLayout {
                            id: procRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            MutedText {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                horizontalAlignment: Text.AlignRight
                                text: String(procRow.modelData[0])
                            }
                            StatText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: procRow.modelData[2]
                            }
                            StatText {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                horizontalAlignment: Text.AlignRight
                                text: Number(procRow.modelData[3]).toFixed(1)
                                color: procRow.modelData[3] >= 10 ? details.accAmber : details.fg
                            }
                            StatText {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                horizontalAlignment: Text.AlignRight
                                text: Number(procRow.modelData[4]).toFixed(1)
                            }
                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                visible: procRow.modelData[0] !== sysmon.killTarget
                                implicitHeight: killLabel.implicitHeight + 4
                                radius: 3
                                color: Qt.alpha(details.accRed, 0.18)
                                Text {
                                    id: killLabel
                                    anchors.centerIn: parent
                                    text: "kill"
                                    color: details.accRed
                                    font: Kirigami.Theme.smallFont
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sysmon.killTarget = procRow.modelData[0]
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: sysmon.killTarget > 0
                        implicitHeight: confirmRow.implicitHeight + Kirigami.Units.smallSpacing
                        radius: 4
                        color: Qt.alpha(details.accRed, 0.12)
                        RowLayout {
                            id: confirmRow
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing / 2
                            spacing: Kirigami.Units.smallSpacing
                            StatText {
                                text: "Kill " + sysmon.killName + " (" + sysmon.killTarget + ")?"
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                implicitWidth: b1.implicitWidth + 8
                                implicitHeight: b1.implicitHeight + 4
                                radius: 3
                                color: Qt.alpha(details.accRed, 0.3)
                                Text {
                                    id: b1
                                    anchors.centerIn: parent
                                    text: sysmon.killTermed ? "Force kill (9)" : "Kill (TERM)"
                                    color: details.accRed
                                    font: Kirigami.Theme.smallFont
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sysmon.doKill(sysmon.killTarget, sysmon.killTermed ? 9 : 15)
                                }
                            }
                            Rectangle {
                                implicitWidth: b2.implicitWidth + 8
                                implicitHeight: b2.implicitHeight + 4
                                radius: 3
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
                                Text {
                                    id: b2
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: details.muted
                                    font: Kirigami.Theme.smallFont
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { sysmon.killTarget = 0; sysmon.killTermed = false }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    SysSection {
                        id: hwSection
                        Layout.fillWidth: true
                        title: "H \u00B7 Hardware"
                        summary: sysmon.hwinfo && sysmon.hwinfo.identity ? (sysmon.hwinfo.identity.product || "") : ""

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            HwRow {
                                label: "Board"
                                value: sysmon.hwinfo && sysmon.hwinfo.identity ? (sysmon.hwinfo.identity.board || "\u2014") : "\u2014"
                            }
                            HwRow {
                                label: "BIOS"
                                value: sysmon.hwinfo && sysmon.hwinfo.identity
                                    ? ((sysmon.hwinfo.identity.bios_version || "\u2014") + "  (" + (sysmon.hwinfo.identity.bios_date || "?") + ")")
                                    : "\u2014"
                            }
                            HwRow {
                                label: "CPU"
                                value: sysmon.hwinfo ? sysmon.hwinfo.cpu.model : ""
                            }
                            HwRow {
                                label: "Cores"
                                visible: sysmon.hwinfo && sysmon.hwinfo.cpu.cores !== null
                                value: sysmon.hwinfo
                                    ? (sysmon.hwinfo.cpu.cores + "c / " + sysmon.hwinfo.cpu.threads + "t \u00B7 " + Math.round(sysmon.hwinfo.cpu.max_mhz / 100) / 10 + "GHz \u00B7 L3 " + Math.round(sysmon.hwinfo.cpu.l3_kb / 1024) + "M")
                                    : ""
                            }
                            HwRow {
                                label: "Memory"
                                visible: sysmon.hwinfo && sysmon.hwinfo.mem
                                value: sysmon.hwinfo
                                    ? (sysmon.fmtGb(sysmon.hwinfo.mem.total_mb) + (sysmon.hwinfo.mem.type ? " \u00B7 " + sysmon.hwinfo.mem.type + " " + sysmon.hwinfo.mem.speed : ""))
                                    : ""
                            }
                            HwRow {
                                label: "GPU"
                                value: sysmon.hwinfo ? (sysmon.hwinfo.gpu || "\u2014") : "\u2014"
                            }
                            Repeater {
                                model: sysmon.hwinfo && sysmon.hwinfo.displays ? sysmon.hwinfo.displays : []
                                HwRow {
                                    required property var modelData
                                    required property int index
                                    label: index === 0 ? "Display" : ""
                                    value: modelData.connector + "  \u00B7  " + modelData.mode
                                }
                            }
                            Repeater {
                                model: sysmon.hwinfo && sysmon.hwinfo.disks ? sysmon.hwinfo.disks : []
                                HwRow {
                                    required property var modelData
                                    required property int index
                                    label: index === 0 ? "Storage" : ""
                                    value: modelData.name + "  \u00B7  " + modelData.size
                                }
                            }
                            Repeater {
                                model: sysmon.hwinfo && sysmon.hwinfo.net ? sysmon.hwinfo.net : []
                                HwRow {
                                    required property var modelData
                                    required property int index
                                    label: index === 0 ? "Network" : ""
                                    value: modelData.name + (modelData.driver ? "  \u00B7  " + modelData.driver : "")
                                }
                            }
                            Repeater {
                                model: sysmon.hwinfo && sysmon.hwinfo.audio ? sysmon.hwinfo.audio : []
                                HwRow {
                                    required property string modelData
                                    required property int index
                                    label: index === 0 ? "Audio" : ""
                                    value: modelData
                                }
                            }
                            HwRow {
                                label: "Battery"
                                visible: sysmon.hwinfo && sysmon.hwinfo.battery
                                value: sysmon.hwinfo && sysmon.hwinfo.battery
                                    ? (sysmon.hwinfo.battery.manufacturer + " " + sysmon.hwinfo.battery.model + " \u00B7 " + sysmon.hwinfo.battery.tech + " \u00B7 " + sysmon.hwinfo.battery.health_pct + "% health")
                                    : ""
                            }
                            HwRow {
                                label: "Bluetooth"
                                value: sysmon.hwinfo ? (sysmon.hwinfo.bluetooth ? "yes" : "no") : ""
                            }
                            HwRow {
                                label: "Devices"
                                value: sysmon.hwinfo ? (sysmon.hwinfo.io.usb_devices + " USB  \u00B7  " + sysmon.hwinfo.io.pci_devices + " PCI") : ""
                            }
                            HwRow {
                                label: "OS"
                                value: sysmon.hwinfo ? ((sysmon.hwinfo.os.pretty || "") + "  \u00B7 kernel " + sysmon.hwinfo.os.kernel) : ""
                            }
                            HwRow {
                                label: "Uptime"
                                visible: sysmon.hwinfo && sysmon.hwinfo.os
                                value: {
                                    if (!sysmon.hwinfo) return ""
                                    const up = sysmon.hwinfo.os.uptime_s + Math.floor((Date.now() - hwLoadedAt) / 1000)
                                    const d = Math.floor(up / 86400)
                                    const h = Math.floor((up % 86400) / 3600)
                                    const m = Math.floor((up % 3600) / 60)
                                    return (d > 0 ? d + "d " : "") + h + "h " + m + "m"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property real hwLoadedAt: 0
    Connections {
        target: sysmon
        function onHwinfoChanged() {
            if (sysmon.hwinfo) details.hwLoadedAt = Date.now()
        }
    }

    // Refresh the process list whenever the Processes tab becomes active.
    onCurrentTabChanged: {
        if (currentTab === 2 && sysmon.procs.length === 0) sysmon.refreshProcs()
    }
    Component.onCompleted: sysmon.refreshProcs()
}
