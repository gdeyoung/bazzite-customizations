import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami

// com.gdeyoung.plasma.readyroom — Plasma 6 port of gdeyoung.readyroom
// (Omarchy). The panel owns view state; bin/gc-* helpers do the work verbatim
// (ported byte-identical — see contents/scripts/README-PORTS.md). All
// subprocess dispatch funnels through ONE DataSource with interval 0
// (connect → read → disconnect), routed by command marker in one onNewData.
PlasmoidItem {
    id: root

    // ---- Config (KConfig XT) --------------------------------------------
    readonly property string startTabCfg: String(Plasmoid.configuration.startTab) || "session"
    readonly property int panelWidthPx: Math.max(300, Math.min(640,
        Number(Plasmoid.configuration.panelWidth) || 380))
    readonly property string bootModeConfPath: String(Plasmoid.configuration.bootModeConfPath)
    readonly property string gameModeSession: String(Plasmoid.configuration.gameModeSession)
    readonly property string desktopSession: String(Plasmoid.configuration.desktopSession)

    property int replaySeconds: Math.max(60, Math.min(900,
        Number(Plasmoid.configuration.replaySeconds) || 300))
    property string replayStorage: String(Plasmoid.configuration.replayStorage) || "disk"
    property string replayQuality: String(Plasmoid.configuration.replayQuality) || "balanced"
    property string replayAudio: String(Plasmoid.configuration.replayAudio) || "desktop"
    property string replayDir: String(Plasmoid.configuration.replayDir)
    property string replayMonitor: String(Plasmoid.configuration.replayMonitor)

    property var mh: ({
        position: String(Plasmoid.configuration.mangohudPosition) || "top-left",
        cpu: Plasmoid.configuration.mhCpu === true,
        gpu: Plasmoid.configuration.mhGpu === true,
        ram: Plasmoid.configuration.mhRam === true,
        vram: Plasmoid.configuration.mhVram === true,
        temps: Plasmoid.configuration.mhTemps === true,
        power: Plasmoid.configuration.mhPower === true
    })

    // Replay-tab write-back sink (called by ReplayTab pills).
    function setReplay(prop, value) {
        if (prop === "seconds") replaySeconds = value
        else if (prop === "storage") replayStorage = value
        else if (prop === "quality") replayQuality = value
        else if (prop === "audio") replayAudio = value
        saveConfig()
        // Changing length while armed shows as active config only; the buffer
        // restarts on next arm (upstream behavior, stated in the tab).
        if (replayStatus && replayStatus.armed) replaySettle.restart()
    }

    function saveConfig() {
        Plasmoid.configuration.replaySeconds = replaySeconds
        Plasmoid.configuration.replayStorage = replayStorage
        Plasmoid.configuration.replayQuality = replayQuality
        Plasmoid.configuration.replayAudio = replayAudio
        Plasmoid.configuration.replayDir = replayDir
        Plasmoid.configuration.mangohudPosition = mh.position
        Plasmoid.configuration.mhCpu = mh.cpu
        Plasmoid.configuration.mhGpu = mh.gpu
        Plasmoid.configuration.mhRam = mh.ram
        Plasmoid.configuration.mhVram = mh.vram
        Plasmoid.configuration.mhTemps = mh.temps
        Plasmoid.configuration.mhPower = mh.power
    }

    function want(key) { return Plasmoid.configuration[key] === true }

    // ---- View state ------------------------------------------------------
    readonly property var tabs: [
        { value: "session", label: "Session" },
        { value: "pads", label: "Pads" },
        { value: "replay", label: "Replay" },
        { value: "gear", label: "Gear" }
    ]
    property string tab: {
        var want = startTabCfg
        for (var i = 0; i < tabs.length; i++) if (tabs[i].value === want) return want
        return "session"
    }

    property var sessionStatus: null
    property var bootModeStatus: null
    property var padsStatus: null
    property var replayStatus: null
    property var clipsList: []
    property var gearList: null
    property var gearStats: null
    property string padsStreamNode: ""
    property bool sessionBusy: false
    property bool mhBusy: false
    property bool bootBusy: false

    // Fallback session model before the first gc-session tick — mirrors the
    // upstream SessionController defaults and the config keys.
    readonly property var sessionFallback: ({
        engaged: false,
        wantIdle: Plasmoid.configuration.sessionKeepAwake === true,
        wantDnd: Plasmoid.configuration.sessionDnd === true,
        wantNightlight: Plasmoid.configuration.sessionNightlight === true,
        wantPower: Plasmoid.configuration.sessionPower === true,
        stayAwakeState: "free",
        stayAwakeNote: "off now — turned on for the session",
        dndState: "unknown",
        nightlightOn: false,
        powerCurrent: "",
        powerAvailable: [],
        rival: "",
        ownedIdle: false, ownedDnd: false, ownedNightlight: false, ownedPower: false,
        powerProfileAvailable: false,
        lastError: ""
    })

    // Apply gc-session status JSON into sessionStatus (want* kept in sync with
    // the model so the tab's toggles round-trip within a session).
    function applySessionStatus(text) {
        var base = sessionStatus ? sessionStatus : JSON.parse(JSON.stringify(sessionFallback))
        try {
            var s = JSON.parse(String(text))
            var p = s.probe || {}
            var items = s.snapshot && s.snapshot.items ? s.snapshot.items : {}
            base.engaged = !!s.engaged
            base.stayAwakeState = String(p.stayAwake ? p.stayAwake.state : "free")
            base.stayAwakeNote = stayAwakeNoteFor(base.stayAwakeState, !!s.engaged)
            base.dndState = String(p.dnd ? p.dnd.state : "unknown")
            base.nightlightOn = !!(p.nightlight && p.nightlight.enabled)
            base.powerCurrent = String(p.power ? p.power.current : "")
            base.powerAvailable = p.power ? (p.power.available || []) : []
            base.rival = String(p.rival || "")
            base.ownedIdle = !!(items.idle && items.idle.owned)
            base.ownedDnd = !!(items.dnd && items.dnd.owned)
            base.ownedNightlight = !!(items.nightlight && items.nightlight.owned)
            base.ownedPower = !!(items.power && items.power.owned)
            base.powerProfileAvailable = base.powerAvailable.indexOf("performance") >= 0
            base.wantIdle = sessionStatus ? sessionStatus.wantIdle : want("sessionKeepAwake")
            base.wantDnd = sessionStatus ? sessionStatus.wantDnd : want("sessionDnd")
            base.wantNightlight = sessionStatus ? sessionStatus.wantNightlight : want("sessionNightlight")
            base.wantPower = sessionStatus ? sessionStatus.wantPower : want("sessionPower")
            base.lastError = ""
        } catch (e) {
            base.lastError = "could not read session state"
        }
        sessionStatus = base
    }

    function stayAwakeNoteFor(state, engaged) {
        switch (state) {
            case "ours": return "on for this session — released when it ends"
            case "manual": return "already on — you set this, Ready Room won't change it"
            case "foreign": return "held by another tool — Ready Room won't change it"
            default: return engaged ? "left off" : "off now — turned on for the session"
        }
    }

    function applyReplayStatus(text) {
        try {
            var s = JSON.parse(String(text))
            if (s.config && !replayTouched) {
                // Show the live buffer's truth once, then leave user prefs alone.
                replaySeconds = Number(s.config.seconds) || replaySeconds
                replayStorage = String(s.config.storage || replayStorage)
                replayQuality = String(s.config.quality || replayQuality)
                replayTouched = true
            }
            replayStatus = s
        } catch (e) {
            replayStatus = { error: "could not read replay state" }
        }
    }
    property bool replayTouched: false

    function applyPads(text) {
        try { padsStatus = JSON.parse(String(text)) }
        catch (e) { padsStatus = { pads: [], claimed: [], dongles: [], drivers: [] } }
    }

    function applyGear(text) {
        try { gearList = (JSON.parse(String(text)).gear) || [] }
        catch (e) { gearList = [] }
    }

    function applyGearStats(out) {
        var lines = String(out).trim().split("\n").filter(function(l) { return l !== "" })
        var obj = {}
        try { obj.hello = JSON.parse(lines[0]) } catch (e) { obj.hello = {} }
        try { obj.first = JSON.parse(lines[1]) } catch (e) { obj.first = {} }
        gearStats = obj
    }

    // Read the SDDM autologin drop-in to decide Game Mode vs Desktop.
    function applyBootMode(stdout) {
        var m = ""
        var readable = false
        var lines = String(stdout || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var match = /^Session\s*=\s*(\S+)/.exec(lines[i])
            if (match) { m = match[1]; readable = true }
        }
        bootModeStatus = {
            readable: readable,
            mode: m === gameModeSession ? "gamemode"
                : (m === desktopSession ? "desktop" : (m || "")),
            lastError: readable ? "" : "status only — the file needs root to read; switching still works"
        }
    }

    // Apply one gc-pads NDJSON line (live-input sampling bursts).
    function applyPadLine(line) {
        var t = String(line).trim()
        if (t === "") return
        try {
            var m = JSON.parse(t)
            if (m.v !== 1) return
            if (m.t === "state") padsTabRef.liveSample = m
        } catch (e) { /* not our line */ }
    }
    property var padsTabRef: null

    // ---- Subprocess dispatch: ONE dataengine, one handler -----------------
    DataSource {
        id: exec
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            const out = String(data["stdout"] || "")
            const err = String(data["stderr"] || "")
            if (cmd.indexOf("pads-stream") >= 0) {
                const ls = out.trim().split("\n")
                for (let i = 0; i < ls.length; i++) root.applyPadLine(ls[i])
            } else if (cmd.indexOf("gc-session") >= 0) {
                root.applySessionStatus(out)
            } else if (cmd.indexOf("gc-replay clips") >= 0) {
                try { root.clipsList = JSON.parse(out.trim() || "[]") }
                catch (e) { root.clipsList = [] }
            } else if (cmd.indexOf("gc-replay arm") >= 0
                       || cmd.indexOf("gc-replay disarm") >= 0) {
                var eobj = null
                var et = err.trim() !== "" ? err.trim() : out.trim()
                try { eobj = JSON.parse(et) } catch (e2) {}
                if (eobj && eobj.ok === false) {
                    root.replayStatus = { armed: false, error: String(eobj.error || "could not arm") }
                } else {
                    root.applyReplayStatus(out)
                }
            } else if (cmd.indexOf("gc-replay save") >= 0) {
                // Reply carries the saved path or the refusal; refresh either way.
                root.refreshReplay()
                root.refreshClips()
            } else if (cmd.indexOf("gc-replay status") >= 0) {
                root.applyReplayStatus(out)
            } else if (cmd.indexOf("gc-pad-probe") >= 0) {
                root.applyPads(out)
            } else if (cmd.indexOf("gc-gear-stats") >= 0) {
                root.applyGearStats(out)
            } else if (cmd.indexOf("gc-gear-probe") >= 0) {
                root.applyGear(out)
            } else if (cmd.indexOf("gc-mangohud") >= 0) {
                root.mhBusy = false
            } else if (cmd.indexOf("bootmode-status") >= 0) {
                root.applyBootMode(out)
            } else if (cmd.indexOf("bootmode-set") >= 0) {
                root.refreshBootMode()
            }
            // gc-rumble, gc-udev, xdg-open: fire-and-forget.
            exec.disconnectSource(sourceName)
        }
    }

    function scriptPath(name) {
        // Plain-string replace (not a regex literal): a /\/\// regex reads as
        // a line comment to naive scanners, and this file must lint clean.
        return Qt.resolvedUrl("../scripts/" + name).toString().replace("file://", "")
    }

    function shQuote(s) {
        // split/join rather than a /'/ regex literal: a bare quote inside a
        // regex reads as a string opener to naive scanners.
        return "'" + String(s).split("'").join("'\\''") + "'"
    }

    function refreshSession() { exec.connectSource(scriptPath("gc-session") + " status") }
    function refreshReplay() { exec.connectSource(scriptPath("gc-replay") + " status") }
    function refreshClips() { exec.connectSource(scriptPath("gc-replay") + " clips") }
    function refreshPads() { exec.connectSource(scriptPath("gc-pad-probe")) }
    function refreshGear() { exec.connectSource(scriptPath("gc-gear-probe")) }
    function refreshGearStats() { exec.connectSource(scriptPath("gc-gear-stats")) }
    function refreshBootMode() {
        exec.connectSource("cat " + shQuote(bootModeConfPath) + " 2>/dev/null; true # bootmode-status")
    }

    function engageSession() {
        if (sessionBusy) return
        sessionBusy = true
        var args = "engage"
        var w = sessionStatus ? sessionStatus : sessionFallback
        if (!w.wantIdle) args += " --no-idle"
        if (!w.wantDnd) args += " --no-dnd"
        if (!w.wantNightlight) args += " --no-nightlight"
        if (!w.wantPower || !w.powerProfileAvailable) args += " --no-power"
        else args += " --profile performance"
        exec.connectSource(scriptPath("gc-session") + " " + args)
        sessionSettle.restart()
    }

    function releaseSession() {
        if (sessionBusy) return
        sessionBusy = true
        exec.connectSource(scriptPath("gc-session") + " release")
        sessionSettle.restart()
    }

    // gc-session's engage/release take a second or two; settle then re-read.
    GcAfter {
        id: sessionSettle
        interval: 1500
        action: function() { root.refreshSession(); root.sessionBusy = false }
    }

    function armReplay() {
        var args = "arm --seconds " + replaySeconds
            + " --storage " + shQuote(replayStorage)
            + " --quality " + shQuote(replayQuality)
            + " --audio " + shQuote(replayAudio)
        if (replayDir !== "") args += " --dir " + shQuote(replayDir)
        if (replayMonitor !== "") args += " --monitor " + shQuote(replayMonitor)
        exec.connectSource(scriptPath("gc-replay") + " " + args)
        replaySettle.restart()
    }

    function disarmReplay() {
        exec.connectSource(scriptPath("gc-replay") + " disarm")
        replaySettle.restart()
    }

    function saveClip() {
        exec.connectSource(scriptPath("gc-replay") + " save")
        replaySettle.restart()
    }

    GcAfter {
        id: replaySettle
        interval: 2500
        action: function() { root.refreshReplay(); root.refreshClips() }
    }

    function rumble(node) {
        exec.connectSource(scriptPath("gc-rumble") + " " + shQuote(node) + " 70 40 600")
    }

    // Live input: bounded bursts of gc-pads (the Plasma popup cannot host a
    // long-lived subprocess the way Quickshell's Process can; ~7s of samples,
    // auto-stop, restartable from the pad row).
    property int streamTicks: 0
    function startStream(node) {
        stopStream()
        if (!node) return
        padsStreamNode = node
        streamTicks = 0
        streamTimer.start()
    }
    function stopStream() {
        streamTimer.stop()
        padsStreamNode = ""
        if (padsTabRef) padsTabRef.liveSample = null
    }
    GcAfter {
        id: streamTimer
        interval: 450
        repeat: true
        action: function() {
            root.streamTicks++
            if (root.streamTicks > 15) { root.stopStream(); return }
            exec.connectSource(
                "timeout 1 " + root.scriptPath("gc-pads") + " "
                + root.shQuote(root.padsStreamNode)
                + " --hz 10 2>/dev/null; true # pads-stream")
        }
    }

    function applyMangohud() {
        mhBusy = true
        var metrics = []
        if (mh.cpu) metrics.push("cpu")
        if (mh.gpu) metrics.push("gpu")
        if (mh.ram) metrics.push("ram")
        if (mh.vram) metrics.push("vram")
        if (mh.temps) metrics.push("temps")
        if (mh.power) metrics.push("power")
        saveConfig()
        exec.connectSource(scriptPath("gc-mangohud") + " --position " + shQuote(mh.position)
            + " --metrics " + shQuote(metrics.join(",")) + " </dev/null >/dev/null; true")
    }

    // Mirrors `ujust toggle-gamemode` (verified against
    // /usr/share/ublue-os/just/95-bazzite-dx.just on Bazzite 44): writes the
    // SDDM autologin drop-in via pkexec. Polkit asks once.
    function setBootMode(mode) {
        if (bootBusy) return
        bootBusy = true
        var session = mode === "gamemode" ? gameModeSession : desktopSession
        exec.connectSource(
            "printf '# Autogenerated by plasma-readyroom (see ujust toggle-gamemode)\\n[Autologin]\\nSession="
            + session + "\\n' | pkexec tee " + shQuote(bootModeConfPath)
            + " >/dev/null # bootmode-set")
        bootSettle.restart()
    }

    GcAfter {
        id: bootSettle
        interval: 1500
        action: function() { root.refreshBootMode(); root.bootBusy = false }
    }

    // ---- Popup lifecycle ---------------------------------------------------
    onExpandedChanged: {
        if (expanded) {
            refreshSession(); refreshReplay(); refreshClips(); refreshPads()
            refreshGear(); refreshGearStats(); refreshBootMode()
        } else {
            stopStream()
        }
    }

    onTabChanged: {
        if (!expanded) return
        if (tab === "pads") refreshPads()
        if (tab === "gear") { refreshGear(); refreshGearStats() }
    }

    // Slow polls while open (battery drifts; replay state can change from
    // outside, e.g. a keybind-driven save).
    GcAfter {
        id: openPoll
        interval: 30000
        repeat: true
        running: root.expanded
        action: function() {
            root.refreshPads()
            if (root.tab === "gear") { root.refreshGear(); root.refreshGearStats() }
            if (root.tab === "replay") { root.refreshReplay(); root.refreshClips() }
            if (root.tab === "session") { root.refreshSession(); root.refreshBootMode() }
        }
    }

    Component.onCompleted: {
        // The chip needs pad battery state even before the first open.
        refreshPads()
        Plasmoid.toolTipMainText = "Ready Room"
        Plasmoid.toolTipSubText = toolSentence()
    }

    // ---- Chip summary -----------------------------------------------------
    readonly property var anyLowPad: {
        if (!padsStatus) return false
        var pads = padsStatus.pads || []
        for (var i = 0; i < pads.length; i++) {
            var b = pads[i].battery
            if (!b) continue
            if (b.level === "Low" || (b.percent !== null && b.percent <= 15)) return true
        }
        return false
    }
    readonly property bool sessionOn: sessionStatus ? !!sessionStatus.engaged : false
    readonly property bool replayArmed: replayStatus ? !!replayStatus.armed : false
    readonly property int padCount: padsStatus ? (padsStatus.pads || []).length : 0

    onAnyLowPadChanged: Plasmoid.toolTipSubText = toolSentence()
    onSessionOnChanged: Plasmoid.toolTipSubText = toolSentence()
    onReplayArmedChanged: Plasmoid.toolTipSubText = toolSentence()
    onPadCountChanged: Plasmoid.toolTipSubText = toolSentence()

    function toolSentence() {
        var parts = []
        if (replayArmed) parts.push("replay armed (" + replaySeconds + "s)")
        if (sessionOn) parts.push("session on")
        parts.push(padCount + (padCount === 1 ? " controller" : " controllers"))
        if (anyLowPad) parts.push("battery low")
        return parts.join(" · ")
    }

    // ==========================================================================
    // COMPACT: game-mode state glyph + controller battery glyph (mirror of the
    // Omarchy chip: one glyph, one state, priority ladder — the sentence lives
    // in the tooltip). Glyphs: nf-md-gamepad U+F02B4, nf-md-record U+F1517,
    // nf-md-battery_alert U+F0083, nf-md-microsoft_xbox_controller U+F05BA.
    // ==========================================================================
    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true
        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                // recording > replay armed > session on > idle
                text: root.replayArmed ? "\uF044B" : "\uF02B4"
                font.family: "Symbols Nerd Font"
                font.pixelSize: Kirigami.Units.gridUnit * 0.9
                color: chip.containsMouse || root.replayArmed || root.sessionOn
                    ? Kirigami.Theme.textColor
                    : Kirigami.Theme.disabledTextColor
            }

            Text {
                visible: root.padCount > 0
                text: root.anyLowPad ? "\uF0083" : "\uF05BA"
                font.family: "Symbols Nerd Font"
                font.pixelSize: Kirigami.Units.gridUnit * 0.75
                color: root.anyLowPad ? Kirigami.Theme.negativeTextColor
                                      : (chip.containsMouse ? Kirigami.Theme.textColor
                                                            : Kirigami.Theme.disabledTextColor)
            }

            Text {
                visible: root.padCount > 1
                text: String(root.padCount)
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
        }

        onClicked: root.expanded = !root.expanded
    }

    // ==========================================================================
    // FULL: self-sizing popup. Pages are ColumnLayout children that collapse
    // to height 0 when invisible, so pages.implicitHeight tracks the VISIBLE
    // page only — the StackLayout tallest-child trap does not apply.
    // ==========================================================================
    fullRepresentation: Item {
        id: popup

        readonly property int pad: Kirigami.Units.largeSpacing
        Layout.preferredWidth: root.panelWidthPx
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: headerRow.implicitHeight + tabBarRef.implicitHeight
            + pages.implicitHeight + popup.pad * 2 + Kirigami.Units.largeSpacing * 3
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

        ColumnLayout {
            id: popupCol
            anchors.fill: parent
            anchors.margins: popup.pad
            spacing: Kirigami.Units.largeSpacing
            width: parent.width

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: "\uF02B4"
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: Kirigami.Units.gridUnit
                    color: root.sessionOn ? Kirigami.Theme.highlightColor
                                          : Kirigami.Theme.textColor
                }
                ColumnLayout {
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: "Ready Room"
                        color: Kirigami.Theme.textColor
                        font: Kirigami.Theme.defaultFont
                        font.weight: Font.Bold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.sessionBusy ? "Working…"
                            : (root.sessionOn ? "Session on" : "Session off")
                        color: Kirigami.Theme.textColor
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.replayArmed ? "\uF044B " + root.replaySeconds + "s" : ""
                    visible: root.replayArmed
                    color: Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                    font.weight: Font.Bold
                }
            }

            GcTabBar {
                id: tabBarRef
                Layout.fillWidth: true
                tabs: root.tabs
                value: root.tab
                onPicked: function(v) { root.tab = v }
            }

            GcSeparator { Layout.fillWidth: true }

            ColumnLayout {
                id: pages
                Layout.fillWidth: true
                spacing: 0

                SessionTab {
                    Layout.fillWidth: true
                    visible: root.tab === "session"
                    session: root.sessionStatus ? root.sessionStatus : root.sessionFallback
                    bootMode: root.bootModeStatus
                    busy: root.sessionBusy || root.bootBusy
                    engageTap: function() { root.engageSession() }
                    releaseTap: function() { root.releaseSession() }
                    bootModeTap: function(mode) { root.setBootMode(mode) }
                }

                PadsTab {
                    id: padsTabPage
                    Layout.fillWidth: true
                    visible: root.tab === "pads"
                    pads: root.padsStatus
                    streamNode: root.padsStreamNode
                    error: ""
                    rumbleTap: function(node) { root.rumble(node) }
                    streamTap: function(node) {
                        if (root.padsStreamNode === node) root.stopStream()
                        else root.startStream(node)
                    }
                    udevTap: function() { root.showUdevHelp() }
                    Component.onCompleted: root.padsTabRef = padsTabPage
                }

                ReplayTab {
                    Layout.fillWidth: true
                    visible: root.tab === "replay"
                    replay: root.replayStatus
                    clips: root.clipsList
                    replaySeconds: root.replaySeconds
                    cfg: root
                    armTap: function() { root.armReplay() }
                    disarmTap: function() { root.disarmReplay() }
                    saveTap: function() { root.saveClip() }
                    openTap: function(path) {
                        root.exec.connectSource("xdg-open " + root.shQuote(path) + "; true")
                    }
                }

                GearTab {
                    Layout.fillWidth: true
                    visible: root.tab === "gear"
                    gear: root.gearList
                    stats: root.gearStats
                    busy: root.mhBusy
                    mh: root.mh
                    mangohudTap: function() { root.applyMangohud() }
                }
            }
        }
    }

    // The udev walkthrough is a terminal flow (it needs a password prompt
    // where a password prompt belongs); konsole is the Bazzite default.
    function showUdevHelp() {
        exec.connectSource(
            "(command -v konsole >/dev/null && setsid konsole -e "
            + shQuote(scriptPath("gc-udev")) + " &) >/dev/null 2>&1; true")
    }
}
