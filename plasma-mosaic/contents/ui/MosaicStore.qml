pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support 2.0
import "lib/ViewModel.js" as ViewModel

// plasma-mosaic shared state (spec §G): snapshot cache, scan lifecycle
// (single-flight), deep-scan merge, view stack, formatters. Both the chip
// and the popup read this singleton, so their scan state is always in sync.
Item {
    id: store

    // ---- state -------------------------------------------------------------
    property var snapshot: null            // CLI envelope or {empty:true}
    readonly property bool hasSnapshot: snapshot !== null && snapshot.empty !== true
    property string scanState: "idle"      // idle | running | error
    property string lastError: ""
    property string searchQuery: ""
    property string expandedPath: ""           // one-open path-card accordion
    property var deepBusy: ({})            // appId -> true
    property string copiedPath: ""
    property real copiedAt: 0
    property string openError: ""
    property real openErrorAt: 0

    // view stack: ["overview"] | +"app:<id>" | +"cat:<config|data|cache|state>"
    property var viewStack: ["overview"]
    readonly property string currentView: viewStack.length > 0
        ? viewStack[viewStack.length - 1] : "overview"
    readonly property string currentArg: currentView.indexOf(":") >= 0
        ? currentView.slice(currentView.indexOf(":") + 1) : ""

    // ---- category system (display order fixed everywhere: spec §B) ---------
    readonly property var categories: ["config", "data", "cache", "state"]
    readonly property var categoryColors: ({
        "config": "#58a6ff", "data": "#2dd4bf", "cache": "#f2a03d", "state": "#c792ea"
    })
    function categoryColor(key) {
        return categoryColors[key] !== undefined ? categoryColors[key] : "#58a6ff"
    }
    function categoryLabel(key) {
        var names = { config: "Config", data: "Data", cache: "Cache", state: "State" }
        return names[key] !== undefined ? names[key] : key
    }

    // ---- formatters --------------------------------------------------------
    function formatBytes(n, lowerBound) {
        if (n === null || n === undefined || !isFinite(Number(n))) return "unknown"
        var v = Number(n)
        var units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var i = 0
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
        var s = (i === 0) ? (String(Math.round(v)) + " B") : (v.toFixed(1) + " " + units[i])
        return lowerBound ? "\u2265 " + s : s
    }
    function appSizeText(app) {
        if (!app) return ""
        if (app.status === "unmapped") return "not mapped"
        if (app.mappedBytes === null || app.mappedBytes === undefined) return "unknown"
        return formatBytes(app.mappedBytes, app.status === "partial")
    }
    function statusColor(status) {
        if (status === "complete") return "#3fd18b"
        if (status === "partial") return "#ffd23f"
        if (status === "failed") return "#f4405c"
        return "#9aa4b2"                    // unmapped / pending / unknown
    }
    function statusLabel(status) {
        var names = { complete: "complete", partial: "partial", failed: "failed",
                      unmapped: "not mapped", pending: "measuring", possible: "possible",
                      shared: "shared" }
        return names[status] !== undefined ? names[status] : status
    }
    // x-proportional stacked segments for AppRow's 120px track
    function barSegments(app, maxBytes) {
        var out = []
        if (!app || !app.categories) return out
        var scale = maxBytes > 0 ? 120 / maxBytes : 0
        var x = 0
        for (var i = 0; i < categories.length; i++) {
            var key = categories[i]
            var b = Number(app.categories[key] || 0)
            var w = Math.max(0, b * scale)
            if (w > 0.5) {
                out.push({ x: x, w: Math.min(w, 120 - x), color: categoryColor(key) })
                x += w
                if (x > 120) break
            }
        }
        return out
    }
    readonly property var apps: hasSnapshot ? snapshot.apps : []
    readonly property real maxAppBytes: {
        var list = apps
        return list.length > 0 ? Math.max(Number(list[0].mappedBytes || 0), 0) : 0
    }
    function findApp(id) {
        return ViewModel.findApp(apps, id)
    }
    // mirror of mosaic_cli.summarize() for the UI-side deep-scan merge
    function summarize(apps) {
        var totals = { config: 0, data: 0, cache: 0, state: 0 }
        var total = 0, completed = 0, partial = false
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i]
            total += Number(app.mappedBytes || 0)
            for (var j = 0; j < categories.length; j++)
                totals[categories[j]] += Number((app.categories || {})[categories[j]] || 0)
            if (app.status !== "pending") completed++
            if (app.status === "partial" || app.status === "pending") partial = true
        }
        return { bytes: total, categories: totals, completed: completed, partial: partial }
    }
    readonly property string asOfText: hasSnapshot && snapshot.meta && snapshot.meta.scannedAt
        ? Qt.formatTime(new Date(snapshot.meta.scannedAt), "HH:mm") : ""
    readonly property int mappedCount: {
        var list = apps, n = 0
        for (var i = 0; i < list.length; i++)
            if (Number(list[i].mappedBytes || 0) > 0) n++
        return n
    }

    // ---- view stack --------------------------------------------------------
    function pushView(view) { viewStack = viewStack.concat([view]) }
    function popView() { if (viewStack.length > 1) viewStack = viewStack.slice(0, viewStack.length - 1) }
    function replaceTop(view) {
        if (viewStack.length === 0) { viewStack = [view]; return }
        viewStack = viewStack.slice(0, viewStack.length - 1).concat([view])
    }
    function showOverview() { viewStack = ["overview"] }

    // ---- CLI plumbing (driveway-proven executable dataengine pattern) ------
    function scriptPath() {
        return Qt.resolvedUrl("../scripts/mosaic").toString().replace("file://", "")
    }
    function q(s) {  // shell-quote; no regex literal (house static checker)
        return "'" + String(s).split("'").join("'\\''") + "'"
    }

    property var inflight: ({})         // command string -> start ms
    property bool scanOwned: false      // true when WE launched the running scan
    readonly property int quickTimeoutMs: 20000
    readonly property int scanTimeoutMs: 160000

    DataSource {
        id: execSource
        engine: "executable"
        interval: 0   // fire once per connect; timers re-connect to re-run
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            const out = (data["stdout"] || "").trim()
            if (cmd.indexOf(" snapshot") >= 0 && cmd.indexOf(" deep") < 0) {
                store.applySnapshot(out)
            } else if (cmd.slice(-5) === " scan") {
                store.applyScan(out)
            } else if (cmd.indexOf(" deep ") >= 0) {
                store.applyDeep(cmd, out)
            } else if (cmd.slice(-8) === " status") {
                store.applyStatus(out)
            } else if (cmd.slice(-9) === " progress") {
                store.applyProgress(out)
            } else if (cmd.indexOf(" open ") >= 0) {
                store.applyOpen(out)
            } else if (cmd.indexOf(" copy ") >= 0) {
                store.applyCopy(cmd, out)
            }
            store.clearInflight(cmd)
            execSource.disconnectSource(sourceName)
        }
    }

    function run(cmd, timeoutMs) {
        const started = inflight[cmd]
        if (started !== undefined) {
            if (Date.now() - started < (timeoutMs || quickTimeoutMs)) return
            delete inflight[cmd]
        }
        inflight[cmd] = Date.now()
        execSource.connectSource(cmd)
    }
    function clearInflight(cmd) {
        delete inflight[cmd]
        const copy = {}
        for (const k in inflight) copy[k] = inflight[k]
        inflight = copy
    }
    function scanCmd() { return scriptPath() + " scan" }

    function loadSnapshot() { run(scriptPath() + " snapshot") }
    function checkStatus() { run(scriptPath() + " status") }

    // Single-flight rescan (spec §G): second call is a no-op for the engine.
    function rescan() {
        if (scanState === "running") return { busy: true }
        scanState = "running"
        scanOwned = true
        lastError = ""
        run(scanCmd(), scanTimeoutMs)
        pollTimer.restart()
        scanWatchdog.restart()
        return { busy: false }
    }
    function cancelScan() {
        if (scanState !== "running") return
        execSource.disconnectSource(scanCmd())
        clearInflight(scanCmd())
        scanState = "idle"
        scanOwned = false
        pollTimer.stop()
        scanWatchdog.stop()
    }
    // adopt a scan another instance started (CLI returns {busy:true})
    function adoptRunning() {
        scanState = "running"
        scanOwned = false
        pollTimer.restart()
        scanWatchdog.restart()
    }

    function deepScan(appId) {
        if (deepBusy[appId]) return { busy: true }
        const next = {}
        for (const k in deepBusy) next[k] = deepBusy[k]
        next[appId] = true
        deepBusy = next
        run(scriptPath() + " deep " + q(appId), scanTimeoutMs)
        return { busy: false }
    }
    function openFolder(path) { run(scriptPath() + " open " + q(path), 15000) }
    function copyToClipboard(path) { run(scriptPath() + " copy " + q(path), 10000) }

    Timer {   // liveness poll while running; also resolves adopted scans
        id: pollTimer
        interval: 1200
        repeat: true
        running: false
        onTriggered: store.run(store.scriptPath() + " progress")
    }
    Timer {   // hard abandon: no result within the scan budget
        id: scanWatchdog
        interval: 160000
        repeat: false
        running: false
        onTriggered: {
            store.cancelScan()
            store.scanState = "error"
            store.lastError = "scan timed out"
        }
    }

    function parse(out) {
        try { return JSON.parse(String(out).trim().split("\n").pop() || "null") }
        catch (e) { return null }
    }

    // ---- data apply --------------------------------------------------------
    property real lastHb: 0
    function heartbeat() {
        const now = Date.now()
        if (now - lastHb < 15000) return
        lastHb = now
        // heartbeat file is written engine-side (mosaic_cli.py _heartbeat);
        // QML sync-XHR file writes are unreliable on Qt 6. This is a no-op
        // marker kept so call sites stay meaningful.
    }

    function applySnapshot(out) {
        const data = parse(out)
        if (!data) return
        snapshot = data
        heartbeat()
    }
    function applyScan(out) {
        const data = parse(out)
        pollTimer.stop()
        scanWatchdog.stop()
        if (!data) {
            if (scanState === "running") { scanState = "error"; lastError = "scan produced no result" }
            return
        }
        if (data.busy === true) { adoptRunning(); return }
        scanOwned = false
        if (data.error !== undefined) {
            scanState = "error"
            lastError = String(data.error)
            if (hasSnapshot) return          // keep last-good data
            return
        }
        snapshot = data
        scanState = "idle"
        lastError = ""
        showOverview()
        heartbeat()
    }
    function applyDeep(cmd, out) {
        const data = parse(out)
        const idTag = " deep "
        const at = cmd.lastIndexOf(idTag)
        const appId = at >= 0 ? cmd.slice(at + idTag.length).split("'").join("") : ""
        const next = {}
        for (const k in deepBusy) if (k !== appId) next[k] = deepBusy[k]
        deepBusy = next
        if (!data || data.error !== undefined || !data.apps || data.apps.length === 0) return
        if (!hasSnapshot) return
        // merge the deep app into the UI snapshot (cache on disk is untouched)
        const merged = snapshot.apps.slice()
        let index = -1
        for (let i = 0; i < merged.length; i++)
            if (merged[i].id === data.apps[0].id) { index = i; break }
        if (index < 0) return
        merged[index] = data.apps[0]
        merged.sort(function(a, b) {
            const d = Number(b.mappedBytes || 0) - Number(a.mappedBytes || 0)
            if (d !== 0) return d
            return String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1
        })
        snapshot = Object.assign({}, snapshot, { apps: merged, summary: summarize(merged) })
        heartbeat()
    }
    function applyStatus(out) {
        const data = parse(out)
        if (!data) return
        if (data.busy === true && scanState === "idle") adoptRunning()
        if (data.busy !== true && scanState === "running" && !scanOwned) {
            // adopted scan finished elsewhere: refresh and stand down
            pollTimer.stop()
            scanWatchdog.stop()
            scanState = "idle"
            loadSnapshot()
        }
    }
    function applyProgress(out) {
        const data = parse(out)
        if (!data) return
        if (data.busy !== true && scanState === "running" && !scanOwned) {
            pollTimer.stop()
            scanWatchdog.stop()
            scanState = "idle"
            loadSnapshot()
        }
    }
    function applyOpen(out) {
        const data = parse(out)
        if (!data) return
        if (data.opened) return
        openError = String(data.error || "could not open folder")
        openErrorAt = Date.now()
    }
    function applyCopy(cmd, out) {
        const data = parse(out)
        if (!data) return
        if (data.copied) {
            const idTag = " copy "
            const at = cmd.lastIndexOf(idTag)
            copiedPath = at >= 0 ? cmd.slice(at + idTag.length).split("'").join("") : ""
            copiedAt = Date.now()
        } else {
            lastError = String(data.error || "copy failed")
        }
    }

    Component.onCompleted: {
        loadSnapshot()
        checkStatus()
    }
}
