import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami

// com.gdeyoung.plasma.sysmon — Plasma 6 port of gdeyoung.sysmon (Omarchy).
// Probe (contents/scripts/sysmon.sh) emits one JSON line per tick; this
// applet computes CPU% and net rates from cumulative-counter deltas and
// keeps 180-sample ring buffers so the popup opens with warm history.
PlasmoidItem {
    id: root

    // ---- Config (KConfig XT) ----------------------------------------------
    readonly property int refreshSeconds: Math.max(1, Math.min(10, Number(Plasmoid.configuration.refreshSeconds) || 2))
    readonly property bool compactMode: String(Plasmoid.configuration.barMode) !== "values"

    // ---- History ring buffers ({t, v} arrays, appended every probe tick) --
    readonly property int histMax: 180
    property var histCpu: []
    property var histRam: []
    property var histNetDown: []
    property var histNetUp: []
    property var histGpuBusy: []
    property var histVram: []
    property var histGtt: []
    property var histDiskR: []
    property var histDiskW: []
    property var histCoreAvg: []
    property var histCoreMax: []

    function pushHist(arr, t, v) {
        // New array each tick: property change notification only fires on
        // reassignment — in-place mutation leaves bound charts frozen.
        const out = arr.length >= histMax ? arr.slice(1) : arr.slice()
        out.push({ t: t, v: v })
        return out
    }

    // ---- Latest probe values ----------------------------------------------
    property real ramUsedMb: 0
    property real ramTotalMb: 1
    property real cpuPct: -1
    property real netDownBps: -1
    property real netUpBps: -1
    property real diskUsedB: 0
    property real diskTotalB: 1

    // Detail values (popup-facing; the panel shows none of these)
    property real buffersKb: 0
    property real cachedKb: 0
    property real swapTotalKb: 0
    property real swapUsedKb: 0
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property real cpuTempC: -1
    property real gpuTempC: -1
    property real nvmeTempC: -1
    property real gpuBusyPct: -1
    property real vramUsedB: -1
    property real vramTotalB: -1
    property real gttUsedB: -1
    property real gttTotalB: -1
    property real gpuPowerMw: -1
    property real diskReadBps: -1
    property real diskWriteBps: -1
    property real diskReadIops: -1
    property real diskWriteIops: -1
    property var corePcts: []
    property var ifRates: ({})
    property var vols: []

    // ---- Processes (popup only) --------------------------------------------
    property var procs: []
    property var hwinfo: null
    property string procSort: "cpu"
    property int killTarget: 0
    property bool killTermed: false
    readonly property var killRow: {
        for (let i = 0; i < procs.length; i++)
            if (procs[i][0] === killTarget) return procs[i]
        return null
    }
    onKillRowChanged: if (killRow === null && killTarget > 0) {
        killTarget = 0
        killTermed = false
    }
    readonly property string killName: killRow ? killRow[2] : ""
    readonly property var sortedProcs: {
        const col = procSort === "mem" ? 4 : 3
        const arr = procs.slice()
        arr.sort((a, b) => Number(b[col]) - Number(a[col]))
        return arr
    }

    function doKill(pid, sig) {
        execSource.connectSource("kill -" + sig + " " + pid + "; true")
        if (sig === 15) {
            killTermed = true
        } else {
            killTarget = 0
            killTermed = false
        }
        refreshProcsTimer.start()
    }

    // ---- Delta math state ----------------------------------------------------
    property real prevCpuTotal: -1
    property real prevCpuIdle: -1
    property real prevNetRx: -1
    property real prevNetTx: -1
    property real prevStampMs: 0
    property var prevCores: []
    property var prevIf: ({})
    property real prevDiskRsec: -1
    property real prevDiskWsec: -1
    property real prevDiskReads: -1
    property real prevDiskWrites: -1

    readonly property real ramPct: ramTotalMb > 0 ? (ramUsedMb / ramTotalMb) * 100 : 0
    readonly property real diskPct: diskTotalB > 0 ? (diskUsedB / diskTotalB) * 100 : 0
    readonly property real netActPct: netDownBps < 0 ? 0 :
        100 * Math.log(1 + netDownBps + netUpBps) / Math.log(1 + 125000000)

    function fmtGb(mb) { return (mb / 1024).toFixed(1) + "G" }
    function fmtGbB(kb) { return (kb / 1048576).toFixed(1) + "G" }
    function fmtDisk(b) { return Math.round(b / 1073741824) + "G" }
    function fmtRate(bps) {
        if (bps < 0) return "0K"
        if (bps < 1000000) return Math.round(bps / 1000) + "K"
        if (bps < 1000000000) return (bps / 1000000).toFixed(1) + "M"
        return (bps / 1000000000).toFixed(1) + "G"
    }

    readonly property string ramText: fmtGb(ramUsedMb) + "/" + fmtGb(ramTotalMb)
    readonly property string cpuText: cpuPct < 0 ? "--%" : Math.round(cpuPct) + "%"
    readonly property string netText: netDownBps < 0 ? "↓--↑--" : "↓" + fmtRate(netDownBps) + "↑" + fmtRate(netUpBps)
    readonly property string diskText: fmtDisk(diskUsedB) + "/" + fmtDisk(diskTotalB)

    readonly property string tooltip:
        "RAM  " + ramText + " (" + Math.round(ramPct) + "%)"
      + "\nCPU  " + (cpuPct < 0 ? "--" : Math.round(cpuPct)) + "%"
      + "\nNet  ↓" + (netDownBps < 0 ? "--" : fmtRate(netDownBps)) + "  ↑" + (netUpBps < 0 ? "--" : fmtRate(netUpBps))
      + "\nDisk " + diskText + " (" + Math.round(diskPct) + "%)"

    function levelColor(pct) {
        if (pct >= 90) return "#f7768e"
        if (pct >= 70) return "#e5c07b"
        return "#3fb950"
    }

    // ---- Data plumbing: executable dataengine + probe scripts ---------------
    // The engine keys sources by the command string, so each distinct command
    // is its own source. interval 0 = run once per connect; we poll from a
    // Timer and disconnect after every read so reconnects re-run.
    function scriptPath(name) {
        return Qt.resolvedUrl("../scripts/" + name).toString().replace(/^file:\/\//, "")
    }

    DataSource {
        id: execSource
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            const out = (data["stdout"] || "").trim()
            if (cmd.indexOf("sysmon.sh") >= 0) {
                root.apply(out)
            } else if (cmd.indexOf("procprobe.sh") >= 0) {
                root.applyProcs(out)
            } else if (cmd.indexOf("sysinfo-probe.sh") >= 0) {
                root.applyHw(out)
            }
            execSource.disconnectSource(sourceName)
        }
    }

    Timer {
        id: probeTimer
        interval: Math.max(1000, root.refreshSeconds * 1000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: execSource.connectSource(root.scriptPath("sysmon.sh"))
    }

    Timer {
        id: refreshProcsTimer
        interval: 400
        onTriggered: root.refreshProcs()
    }

    function refreshProcs() {
        execSource.connectSource(scriptPath("procprobe.sh"))
    }

    Component.onCompleted: {
        execSource.connectSource(scriptPath("sysinfo-probe.sh"))
        Plasmoid.toolTipMainText = "SysMon"
        Plasmoid.toolTipSubText = tooltip
        Plasmoid.toolTipTextFormat = 0   // plain text
    }

    onTooltipChanged: {
        Plasmoid.toolTipSubText = tooltip
    }

    function applyHw(line) {
        let data
        try { data = JSON.parse(String(line).trim()) } catch (e) { return }
        if (data) hwinfo = data
    }

    function applyProcs(line) {
        let data
        try { data = JSON.parse(String(line).trim()) } catch (e) { return }
        if (data && data.procs) procs = data.procs
    }

    function applyVols(data) {
        const v = data.vols || []
        const out = []
        for (let i = 0; i < v.length; i++) {
            const used = Number(v[i][1]) || 0
            const size = Number(v[i][2]) || 1
            out.push({ mnt: v[i][0], usedB: used, sizeB: size, pct: size > 0 ? (used / size) * 100 : 0 })
        }
        vols = out
    }

    function apply(line) {
        let data
        try { data = JSON.parse(String(line).trim()) } catch (e) { return }
        if (!data) return


        ramUsedMb = Number(data.ram_used_mb) || 0
        ramTotalMb = Number(data.ram_total_mb) || 1
        diskUsedB = Number(data.disk_used_b) || 0
        diskTotalB = Number(data.disk_total_b) || 1
        applyVols(data)
        buffersKb = Number(data.mem_buffers_kb) || 0
        cachedKb = Number(data.mem_cached_kb) || 0
        swapTotalKb = Number(data.swap_total_kb) || 0
        swapUsedKb = Number(data.swap_used_kb) || 0
        load1 = Number(data.load1) || 0
        load5 = Number(data.load5) || 0
        load15 = Number(data.load15) || 0
        cpuTempC = data.cpu_temp_mc >= 0 ? data.cpu_temp_mc / 1000 : -1
        gpuTempC = data.gpu_temp_mc >= 0 ? data.gpu_temp_mc / 1000 : -1
        nvmeTempC = data.nvme_temp_mc >= 0 ? data.nvme_temp_mc / 1000 : -1
        gpuBusyPct = Number(data.gpu_busy_pct)
        vramUsedB = Number(data.vram_used_b)
        vramTotalB = Number(data.vram_total_b)
        gttUsedB = Number(data.gtt_used_b)
        gttTotalB = Number(data.gtt_total_b)
        gpuPowerMw = Number(data.gpu_power_mw)

        const now = Date.now()
        const dt = (now - prevStampMs) / 1000

        const cTotal = Number(data.cpu_total)
        const cIdle = Number(data.cpu_idle)
        if (prevCpuTotal >= 0 && dt > 0.4) {
            const dTotal = cTotal - prevCpuTotal
            const dIdle = cIdle - prevCpuIdle
            if (dTotal > 0 && dIdle >= 0)
                cpuPct = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
        }
        prevCpuTotal = cTotal
        prevCpuIdle = cIdle

        const cores = data.cpu_cores || []
        if (prevCores.length === cores.length && cores.length > 0 && dt > 0.4) {
            const pcts = []
            for (let i = 0; i < cores.length; i++) {
                const dT = cores[i][0] - prevCores[i][0]
                const dI = cores[i][1] - prevCores[i][1]
                pcts.push(dT > 0 ? Math.max(0, Math.min(100, 100 * (1 - dI / dT))) : 0)
            }
            corePcts = pcts
        } else if (cores.length > 0) {
            corePcts = new Array(cores.length).fill(0)
        }
        prevCores = cores

        const rx = Number(data.net_rx)
        const tx = Number(data.net_tx)
        if (prevNetRx >= 0 && dt > 0.4) {
            const dRx = rx - prevNetRx
            const dTx = tx - prevNetTx
            if (dRx >= 0 && dTx >= 0) {
                netDownBps = dRx / dt
                netUpBps = dTx / dt
            }
        } else if (prevNetRx < 0) {
            netDownBps = 0
            netUpBps = 0
        }
        prevNetRx = rx
        prevNetTx = tx

        const ifc = data.net_if || {}
        const rates = {}
        for (const name in ifc) {
            const cur = ifc[name]
            const prev = prevIf[name]
            if (prev && dt > 0.4) {
                const d0 = cur[0] - prev[0]
                const d1 = cur[1] - prev[1]
                rates[name] = [d0 >= 0 ? d0 / dt : 0, d1 >= 0 ? d1 / dt : 0]
            } else {
                rates[name] = [0, 0]
            }
        }
        ifRates = rates
        prevIf = ifc

        const rsec = Number(data.disk_rsec) || 0
        const wsec = Number(data.disk_wsec) || 0
        const reads = Number(data.disk_reads) || 0
        const writes = Number(data.disk_writes) || 0
        if (prevDiskRsec >= 0 && dt > 0.4) {
            const dR = rsec - prevDiskRsec
            const dW = wsec - prevDiskWsec
            diskReadBps = dR >= 0 ? (dR * 512) / dt : 0
            diskWriteBps = dW >= 0 ? (dW * 512) / dt : 0
            diskReadIops = Math.max(0, (reads - prevDiskReads) / dt)
            diskWriteIops = Math.max(0, (writes - prevDiskWrites) / dt)
        }
        prevDiskRsec = rsec
        prevDiskWsec = wsec
        prevDiskReads = reads
        prevDiskWrites = writes
        prevStampMs = now

        // History append (always, so the popup opens warm)
        if (cpuPct >= 0) histCpu = pushHist(histCpu, now, cpuPct)
        if (corePcts.length > 0) {
            let sum = 0, mx = 0
            for (let i = 0; i < corePcts.length; i++) {
                sum += corePcts[i]
                if (corePcts[i] > mx) mx = corePcts[i]
            }
            histCoreAvg = pushHist(histCoreAvg, now, sum / corePcts.length)
            histCoreMax = pushHist(histCoreMax, now, mx)
        }
        histRam = pushHist(histRam, now, ramPct)
        if (netDownBps >= 0) {
            histNetDown = pushHist(histNetDown, now, netDownBps)
            histNetUp = pushHist(histNetUp, now, netUpBps)
        }
        if (gpuBusyPct >= 0) histGpuBusy = pushHist(histGpuBusy, now, gpuBusyPct)
        if (vramUsedB >= 0 && vramTotalB > 0)
            histVram = pushHist(histVram, now, (vramUsedB / vramTotalB) * 100)
        if (gttUsedB >= 0 && gttTotalB > 0)
            histGtt = pushHist(histGtt, now, (gttUsedB / gttTotalB) * 100)
        if (diskReadBps >= 0) {
            histDiskR = pushHist(histDiskR, now, diskReadBps)
            histDiskW = pushHist(histDiskW, now, diskWriteBps)
        }
    }

    // ==========================================================================
    // COMPACT representation (panel): M C N D letters over 5px level bars,
    // or full readouts in "values" mode. Click toggles the popup.
    // ==========================================================================
    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true

        implicitWidth: (root.compactMode ? compactRow.implicitWidth : valuesRow.implicitWidth) + Kirigami.Units.smallSpacing * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            visible: root.compactMode

            Repeater {
                model: [
                    { letter: "M", pct: root.ramPct },
                    { letter: "C", pct: root.cpuPct < 0 ? 0 : root.cpuPct },
                    { letter: "N", pct: root.netActPct },
                    { letter: "D", pct: root.diskPct }
                ]

                ColumnLayout {
                    id: grp
                    required property var modelData
                    spacing: 1

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: grp.modelData.letter
                        color: compactRoot.containsMouse ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.45
                        font.bold: true
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.7
                        radius: 1
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: parent.width
                            height: parent.height * Math.min(1, Math.max(0, grp.modelData.pct / 100))
                            radius: 1
                            color: root.levelColor(grp.modelData.pct)
                        }
                    }
                }
            }
        }

        RowLayout {
            id: valuesRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing * 2
            visible: !root.compactMode

            Text { text: root.ramText; color: Kirigami.Theme.textColor; font: Kirigami.Theme.smallFont }
            Text { text: root.cpuText; color: Kirigami.Theme.textColor; font: Kirigami.Theme.smallFont }
            Text { text: root.netText; color: Kirigami.Theme.textColor; font: Kirigami.Theme.smallFont }
            Text { text: root.diskText; color: Kirigami.Theme.textColor; font: Kirigami.Theme.smallFont }
        }

        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: Details {
        sysmon: root
        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
    }
}
