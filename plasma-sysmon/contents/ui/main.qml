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
    property real upS: 0            // host uptime seconds (ticks every probe)
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
    property string diskDev: ""      // v0.7: named disk for the Disk card header
    property var diskRates: ({})     // v0.7: name -> [rBps, wBps, riops, wiops]
    property var diskHist: ({})      // v0.7: name -> {r:[], w:[]} ring (90)
    property var prevDiskMap: ({})

    // ---- Processes (popup only) --------------------------------------------
    property var procs: []
    property var hwinfo: null
    property string procSort: "cpu"
    property int killTarget: 0
    property bool killTermed: false
    property int killExit: 0          // exit code of last kill attempt (EPERM etc)
    property real procStampMs: 0
    property real probeStampMs: 0     // last sysmon.sh apply (drives provenance stamp)
    property real clockNow: Date.now()  // 1s wall clock (stale detection, uptime tick)
    property bool procTabActive: false  // set by Details when Processes tab is shown
    property string procFilter: ""
    property int procSelectedPid: 0    // selected process (ProcsTab rows); routed for harness/tests      // processes search text (routed here for harness access)
    property var pidHist: ({})        // pid -> comma-packed CPU% series (30 samples)
    readonly property int lastTab: Math.max(0, Math.min(3, Number(Plasmoid.configuration.lastTab) || 0))
    onKillTargetChanged: killExit = 0

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

    function doKill(pid, sig) {
        // No "; true" suffix — the real exit code is surfaced in the
        // confirm bar (v0.6 swallowed it, so EPERM on root procs failed
        // silently). Exit code is read in execSource.onNewData.
        execSource.connectSource("kill -" + sig + " " + pid)
        if (sig === 15) {
            killTermed = true
        } else {
            killTarget = 0
            killTermed = false
        }
        refreshProcsTimer.start()
    }

    function saveTab(i) { Plasmoid.configuration.lastTab = i }

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
        // v0.7 semantic palette (spec §color): ok/warn/crit — same hues the
        // plasma-systemmonitor siblings use; thresholds unchanged.
        if (pct >= 90) return "#f4405c"
        if (pct >= 70) return "#e5c07b"
        return "#3fd18b"
    }

    // ---- v0.7 unit helpers (single site, all tabs reuse) ---------------------
    // rates: "4.3 MB/s" (space, /s, 1 decimal <10, int above)
    function fmtRateLong(bps) {
        if (!(bps >= 0)) return "\u2014"
        const tiers = [[1e9, "GB/s"], [1e6, "MB/s"], [1e3, "KB/s"]]
        for (let i = 0; i < tiers.length; i++) {
            if (bps >= tiers[i][0]) {
                const v = bps / tiers[i][0]
                return (v < 10 ? v.toFixed(1) : String(Math.round(v))) + " " + tiers[i][1]
            }
        }
        return Math.round(bps) + " B/s"
    }
    // sizes (prose): "18.4 GB"
    function fmtSizeP(b) {
        const gb = b / 1073741824
        if (gb >= 1) return (gb < 10 ? gb.toFixed(1) : String(Math.round(gb))) + " GB"
        const mb = b / 1048576
        if (mb >= 1) return (mb < 10 ? mb.toFixed(1) : String(Math.round(mb))) + " MB"
        return Math.round(b / 1024) + " KB"
    }
    // RSS (dense rows): "1.2G" / "340M"
    function fmtRss(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + "G"
        if (kb >= 1024) return Math.round(kb / 1024) + "M"
        return Math.round(kb) + "K"
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
            } else if (cmd.indexOf("kill ") === 0) {
                // Surface the kill exit code (EPERM on root procs etc).
                const ec = data["exit code"]
                root.killExit = (ec === undefined || ec === "") ? 0 : Number(ec)
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

    // v0.7: process list refreshes every 2s ONLY while the popup is open and
    // the Processes tab is visible (v0.6 fetched one stale snapshot).
    Timer {
        id: procTick
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.expanded && root.procTabActive
        onTriggered: root.refreshProcs()
    }

    // 1s wall clock: drives provenance/stale stamp + uptime ticking.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.clockNow = Date.now()
    }

    Timer {
        id: refreshProcsTimer
        interval: 400
        onTriggered: root.refreshProcs()
    }

    function refreshProcs() {
        // The probe keeps top-1500-by-CPU UNION rows matching the filter, so
        // search finds idle processes even on hosts with more rows than the
        // cap. procFilter is sanitized to a shell-safe charset before it is
        // ever placed in a command string (executable engine runs a shell).
        const f = procFilter.replace(/[^a-zA-Z0-9 .:_\/-]/g, "").trim()
        execSource.connectSource(scriptPath("procprobe.sh") + (f === "" ? "" : " '" + f + "'"))
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
        const t0 = Date.now()
        let data
        try { data = JSON.parse(String(line).trim()) } catch (e) {
            console.error("HARNESS-PROC parse-fail")
            return
        }
        if (!data || !data.procs) return
        const t1 = Date.now()
        procs = data.procs
        procStampMs = Date.now()
        // Per-PID CPU history for the 1m column: comma-packed strings
        // (array roles in ListModel are a dead transport — string it is).
        const nh = {}
        for (let i = 0; i < data.procs.length; i++) {
            const r = data.procs[i]
            const k = String(r[0])
            const parts = pidHist[k] ? String(pidHist[k]).split(",") : []
            parts.push(Number(r[3]).toFixed(1))
            if (parts.length > 30) parts.shift()
            nh[k] = parts.join(",")
        }
        pidHist = nh
        console.error("HARNESS-PROC n=" + data.procs.length + " parseMs=" + (t1 - t0) + " histMs=" + (Date.now() - t1))
    }

    function applyVols(data) {
        const v = data.vols || []
        const out = []
        for (let i = 0; i < v.length; i++) {
            const used = Number(v[i][1]) || 0
            const size = Number(v[i][2]) || 1
            out.push({ mnt: v[i][0], usedB: used, sizeB: size, pct: size > 0 ? (used / size) * 100 : 0, fs: v[i][3] || "" })
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
        upS = Number(data.up_s) || upS
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
        probeStampMs = now

        // Per-disk rates + history from the v0.7 disks[] counters
        diskDev = String(data.disk_dev || "")
        const dks = data.disks || []
        const dRates = {}
        const dHist = {}
        for (let i = 0; i < dks.length; i++) {
            const nm = String(dks[i].n)
            const rs = Number(dks[i].rs) || 0
            const ws = Number(dks[i].ws) || 0
            const ri = Number(dks[i].ri) || 0
            const wi = Number(dks[i].wi) || 0
            const p = prevDiskMap[nm]
            if (p && dt > 0.4) {
                dRates[nm] = [Math.max(0, ((rs - p[0]) * 512) / dt), Math.max(0, ((ws - p[1]) * 512) / dt),
                              Math.max(0, (ri - p[2]) / dt), Math.max(0, (wi - p[3]) / dt)]
            } else {
                dRates[nm] = [0, 0, 0, 0]
            }
            dHist[nm] = {
                r: (diskHist[nm] ? diskHist[nm].r : []).concat([dRates[nm][0]]).slice(-90),
                w: (diskHist[nm] ? diskHist[nm].w : []).concat([dRates[nm][1]]).slice(-90)
            }
            prevDiskMap[nm] = [rs, ws, ri, wi]
        }
        diskRates = dRates
        diskHist = dHist

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
                        font.pixelSize: 11
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

    // Sizing lives ONLY in Details.qml (Layout.minimumWidth/Height 960x640,
    // the harness-proven single-site rule). No hints here — attached props
    // at this site fought the popup's own sizing in v0.6.
    fullRepresentation: Details { sysmon: root }
}
