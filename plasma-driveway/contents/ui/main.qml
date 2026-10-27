import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support 2.0
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// com.gdeyoung.plasma.driveway — Plasma 6 port of gdeyoung.driveway
// (Omarchy/Quickshell bar plugin). Engine is the verbatim python CLI
// (contents/lib/driveway, stdlib-only); the plasmoid shells out to it via
// the plasma5support executable dataengine:
//   status : driveway list … ; driveway cloud status        (read-only poll)
//   actions: driveway action mount/eject … ; cloud mount/unmount (on click)
// v0.1 is panel-only on purpose — no resident daemon, no udev monitor;
// re-plug detection is the poll (see README: deliberate scope decision).
PlasmoidItem {
    id: root

    // ---- Config (KConfig XT; defaults mirror the Omarchy plugin) ----------
    readonly property int pollSec: Math.max(2, Number(Plasmoid.configuration.pollIntervalSec) || 10)
    readonly property bool showNetwork: Plasmoid.configuration.showNetwork !== false
                                          && Plasmoid.configuration.showNetwork !== "false"
    readonly property bool showUnmounted: Plasmoid.configuration.showUnmounted !== false
                                             && Plasmoid.configuration.showUnmounted !== "false"
    readonly property int thumbMaxGb: Number(Plasmoid.configuration.thumbMaxGb) || 256
    readonly property int minUnmountedMb: Number(Plasmoid.configuration.minUnmountedMb)
    readonly property int fullWarnPct: Math.min(100, Math.max(50,
                                   Number(Plasmoid.configuration.fullWarnPct) || 90))
    readonly property string glyphFont: Plasmoid.configuration.glyphFontFamily || ""
    readonly property string unlockCommand: Plasmoid.configuration.unlockCommand
                                            || "konsole -e udisksctl unlock -b {dev}"
    readonly property var shareList: parseShares(Plasmoid.configuration.sharesJson || "[]")

    function parseShares(text) {
        try { return JSON.parse(String(text)) } catch (e) { return [] }
    }

    // ---- Model state -------------------------------------------------------
    property var drives: []            // lister rows (System row included)
    property var cloud: ({ rclone: false, unit: false, mountRoot: "", drives: [] })
    property var busy: ({})            // drive.key -> {message, procs, uploads}
    property var inflight: ({})        // command string -> start ms (overlap guard)
    property var shareMountState: ({}) // share id -> "up"/"down"/"busy"/"fail"
    property string lastError: ""

    readonly property var cloudFilter: {
        const want = String(Plasmoid.configuration.cloudRemotes || "").trim()
        if (want === "") return null
        return want.split(/[\s,]+/).filter(s => s.length > 0)
    }
    readonly property var cloudDrives: {
        const all = (cloud && cloud.drives) || []
        if (!cloudFilter) return all
        return all.filter(d => cloudFilter.indexOf(d.name) >= 0)
    }
    // Shares come from CONFIG, not from any LAN scan: public repo, no
    // host specifics hardcoded (house rule). Schema in README.
    // Entry: { id, label, url, mountpoint?, mountCommand?, scheme? }
    readonly property var shareRows: {
        const out = []
        const list = root.shareList
        for (let i = 0; i < list.length; i++) {
            const s = list[i] || {}
            const id = s.id || ("share" + i)
            const url = s.url || ""
            out.push({
                id: id,
                label: s.label || url,
                url: url,
                mountpoint: s.mountpoint || "",
                mountCommand: s.mountCommand || "",
                scheme: s.scheme || guessScheme(url),
                fstype: s.fstype || (s.scheme || guessScheme(url)).toUpperCase(),
                state: root.shareMountState[id] || "unknown"
            })
        }
        return out
    }
    function guessScheme(url) {
        const m = String(url || "").split(":")
        return m.length > 1 ? m[0] : "smb"
    }

    // Panel chip verdict (mirrors the Omarchy chip): badge = mounted count,
    // dim = nothing mounted, urgent = failed cloud remote or drive at fullPct.
    readonly property var barState: Model.barState(drives, cloudDrives,
                                                   cloud ? cloud.rclone : false,
                                                   fullWarnPct)

    // ---- CLI plumbing ------------------------------------------------------
    function scriptPath() {
        return Qt.resolvedUrl("../scripts/driveway").toString().replace("file://", "")
    }
    // shell-quote a value for the executable engine (no regex literal: keeps
    // the house static checker's simple string scanner accurate)
    function q(s) {
        return "'" + String(s).split("'").join("'\\''") + "'"
    }

    DataSource {
        id: execSource
        engine: "executable"
        interval: 0   // fire once per connect; timers re-connect to re-run
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            const out = (data["stdout"] || "").trim()
            const err = (data["stderr"] || "").trim()
            if (cmd.indexOf(" driveway list") >= 0 || cmd.indexOf("driveway list ") === 0) {
                root.applyList(out)
            } else if (cmd.indexOf(" cloud status") >= 0) {
                root.applyCloud(out)
            } else if (cmd.indexOf(" action ") >= 0) {
                root.applyAction(cmd, out)
            } else if (cmd.indexOf(" cloud mount") >= 0 || cmd.indexOf(" cloud unmount") >= 0) {
                root.applyCloudAction(cmd, out)
            } else if (cmd.indexOf(" netmap unmount") >= 0) {
                root.applyNetUnmount(cmd, out)
            }
            root.clearInflight(cmd)
            execSource.disconnectSource(sourceName)
        }
    }

    // Overlap guard (Omarchy Service.qml pattern, 20 s abandon window): the
    // poller keeps firing while a wedged FUSE/NFS lister hangs; never stack.
    readonly property int runTimeoutMs: 20000
    property bool listInflight: false
    property real listStarted: 0

    function run(cmd) {
        const started = inflight[cmd]
        if (started !== undefined) {
            if (Date.now() - started < runTimeoutMs) return
            delete inflight[cmd]
        }
        inflight[cmd] = Date.now()
        execSource.connectSource(cmd)
    }

    function clearInflight(cmd) {
        delete inflight[cmd]
        // force re-notify so bindings on inflight-derived state refresh
        const copy = {}
        for (const k in inflight) copy[k] = inflight[k]
        inflight = copy
    }

    // ---- status commands (read-only) ---------------------------------------
    function statusListCmd() {
        let cmd = scriptPath() + " list --thumb-max-gb " + thumbMaxGb
                + " --min-unmounted-mb " + minUnmountedMb
        if (!showNetwork) cmd += " --no-network"
        if (!showUnmounted) cmd += " --no-unmounted"
        return cmd
    }

    function refreshList() {
        if (listInflight && Date.now() - listStarted < runTimeoutMs) return
        if (listInflight) listInflight = false   // abandoned after 20 s
        listInflight = true
        listStarted = Date.now()
        run(statusListCmd())
    }

    function refreshCloud() {
        if (!showNetwork) { cloud = { rclone: false, unit: false, mountRoot: "", drives: [] }; return }
        run(scriptPath() + " cloud status")
    }

    function refresh() {
        refreshList()
        refreshCloud()
    }

    // ---- data apply --------------------------------------------------------
    function applyList(out) {
        listInflight = false
        let data
        try { data = JSON.parse(String(out).trim().split("\n").pop() || "null") } catch (e) { return }
        if (!data) return
        drives = data.drives || []
        if (data.error) lastError = data.error
        updateShareStates()
    }

    function applyCloud(out) {
        let data
        try { data = JSON.parse(String(out).trim().split("\n").pop() || "null") } catch (e) { return }
        if (data) cloud = data
    }

    // Mounted-state for config shares: matched against kernel/network rows
    // from the lister by mountpoint (exact mount point = up).
    function updateShareStates() {
        const next = {}
        for (let i = 0; i < shareRows.length; i++) {
            const share = shareRows[i]
            let up = false
            if (share.mountpoint !== "") {
                for (let j = 0; j < drives.length; j++) {
                    const d = drives[j]
                    if (d.kind === "network" && String(d.mountpoint || "") === share.mountpoint) {
                        up = true
                        break
                    }
                }
            }
            next[share.id] = up ? "up" : (shareMountState[share.id] === "busy"
                                          ? "busy" : "down")
        }
        shareMountState = next
    }

    // ---- actions (install-day only: never executed during build) -----------
    // Local disks — the engine's udisks machinery handles mount/eject and
    // busy-process reporting (actions.py, vendored verbatim).
    function mountDrive(d) {
        run(scriptPath() + " action mount --dev " + q(d.path) + " --name " + q(displayName(d)))
    }
    function ejectDrive(d, kill, force) {
        if (d.pending > 0 && !force) {
            const next = {}
            for (const k in busy) next[k] = busy[k]
            next[d.key] = { message: d.pending + " upload(s) still pending — unmounting now leaves them in rclone's cache until it is mounted again", procs: [], uploads: d.pending }
            busy = next
            return
        }
        let cmd = scriptPath() + " action eject --mode " + d.eject
                + " --mount " + q(d.mountpoint) + " --name " + q(displayName(d))
        if (d.path && d.eject !== "fuse" && d.eject !== "gio") cmd += " --dev " + q(d.path)
        if (d.disk) cmd += " --disk " + q(d.disk)
        if (d.encrypted && d.luksPath) cmd += " --luks " + q(d.luksPath)
        if (d.removable) cmd += " --removable"
        if (kill) cmd += " --kill"
        run(cmd)
    }
    function unlockDrive(d) {
        // Passphrase is typed into a real terminal prompt (house rule from
        // the Omarchy plugin: secrets never cross the widget). Template is
        // config so KDE/GNOME hosts each use their own terminal.
        run(unlockCommand.replace("{dev}", q(d.path)))
    }
    function openPath(path) {
        run("xdg-open " + q(path || "/"))
    }

    // Cloud remotes — supervised systemd user units (engine, verbatim).
    function cloudMount(name) {
        run(scriptPath() + " cloud mount " + q(name))
    }
    function cloudUnmount(name) {
        run(scriptPath() + " cloud unmount " + q(name))
    }

    // Config shares — unmount via the engine's netmap (gio) lane; mount via
    // the configured command (file managers mount smb:// URLs natively).
    function shareMount(share) {
        const next = {}
        for (const k in shareMountState) next[k] = shareMountState[k]
        next[share.id] = "busy"
        shareMountState = next
        run(share.mountCommand || ("xdg-open " + q(share.url)))
    }
    function shareUnmount(share) {
        const next = {}
        for (const k in shareMountState) next[k] = shareMountState[k]
        next[share.id] = "busy"
        shareMountState = next
        run(scriptPath() + " netmap unmount " + q(share.url))
    }

    function applyAction(cmd, out) {
        let result = null
        try { result = JSON.parse(String(out).trim().split("\n").pop() || "null") } catch (e) {}
        if (!result) return
        const key = busyKeyFor(cmd)
        if (key) {
            const next = {}
            for (const k in busy) next[k] = busy[k]
            if (result.status === "busy")
                next[key] = { message: result.message || "", procs: result.procs || [], uploads: result.uploads || 0 }
            else
                delete next[key]
            busy = next
        }
        refreshList()
        if (showNetwork) refreshCloud()
    }

    // The action command carries --name '<display name>'; map it back to the
    // drive key by re-quoting each drive's display name and locating it.
    function busyKeyFor(cmd) {
        const tag = "--name "
        const at = cmd.lastIndexOf(tag)
        if (at < 0) return ""
        let rest = cmd.substring(at + tag.length)
        let name = ""
        if (rest.charAt(0) === "'") {
            // shell-quoted: take up to the closing quote (q() escapes ' as '\'')
            let i = 1
            while (i < rest.length) {
                if (rest.charAt(i) === "'") {
                    if (i + 3 <= rest.length && rest.substring(i, i + 4) === "'\\''") {
                        name += "'"
                        i += 4
                        continue
                    }
                    break
                }
                name += rest.charAt(i)
                i++
            }
        } else {
            name = rest.split(" ")[0]
        }
        for (let i = 0; i < drives.length; i++)
            if (displayName(drives[i]) === name) return drives[i].key
        return ""
    }

    function applyCloudAction(cmd, out) {
        let result = null
        try { result = JSON.parse(String(out).trim().split("\n").pop() || "null") } catch (e) {}
        if (result && result.ok === false)
            lastError = result.message || result.error || "cloud action failed"
        refreshCloud()
        refreshList()
    }

    function applyNetUnmount(cmd, out) {
        let result = null
        try { result = JSON.parse(String(out).trim().split("\n").pop() || "null") } catch (e) {}
        if (result && result.ok === false)
            lastError = result.error || "unmount failed"
        refreshList()
    }

    function displayName(d) { return d.label || d.name || Model.kindName(d) }
    function busyFor(d) { return busy[d.key] || null }
    function clearBusy(d) {
        const next = {}
        for (const k in busy) if (k !== d.key) next[k] = busy[k]
        busy = next
    }

    // ---- polling -----------------------------------------------------------
    // Popup open: 2 s (live). Closed: configured pollSec. The poll replaces
    // the Omarchy udev monitor (see README scope note).
    Timer {
        id: pollTimer
        interval: root.expanded ? 2000 : Math.max(2000, root.pollSec * 1000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshList()
            if (root.showNetwork) root.refreshCloud()
        }
    }

    onExpandedChanged: if (expanded) root.refresh()

    Component.onCompleted: {
        Plasmoid.toolTipMainText = "Driveway"
        Plasmoid.toolTipSubText = "Click for drives, shares and cloud mounts"
        Plasmoid.toolTipTextFormat = 0
        root.refresh()
    }

    // =========================================================================
    // COMPACT (panel chip): drive glyph + mounted count, mirroring the Omarchy
    // chip (urgent/dim tint via theme colors only).
    // =========================================================================
    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true

        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: "󰇅"
                color: root.barState.urgent ? Kirigami.Theme.negativeTextColor
                    : (root.barState.dim ? Kirigami.Theme.disabledTextColor
                                         : Kirigami.Theme.textColor)
                font.family: root.glyphFont !== "" ? root.glyphFont : Kirigami.Theme.defaultFont.family
                font.pixelSize: Kirigami.Units.gridUnit * 0.9
            }
            Text {
                visible: root.barState.badge > 0
                text: String(root.barState.badge)
                color: Kirigami.Theme.textColor
                font: Kirigami.Theme.smallFont
            }
        }

        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: DrivewayPopup {
        driveway: root
        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16
    }
}
