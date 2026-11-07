import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import "Control.js" as Control
import QtQuick.Controls as QQC2

// com.gdeyoung.plasma.tailfin — Plasma 6 port of gdeyoung.tailfin (Omarchy).
// Model.js is ported VERBATIM from the Omarchy plugin (MIT); only this
// container changed: the Quickshell Service's `tailscale status --json`
// watch becomes the plasma5support "executable" dataengine polled on an
// interval, and the Panel.qml popup layout is re-expressed with Plasma
// components + Kirigami theme tokens.
//
// Scope of the port: v0.1 was deliberately read-only; v0.2 adds the
// §T-2 control allowlist (up/down, exit-node set/clear) behind the §T-1
// operator gate — see UX-SPEC-CONTROL.md. Mullvad picking, Taildrop,
// SSH, and account ops stay OUT (Trayscale/CLI territory).
PlasmoidItem {
    id: root

    // ---- Config (KConfig XT) ----------------------------------------------
    // interval: seconds between `tailscale status --json` polls (5..3600, default 10)
    // showOffline: offline devices inline instead of behind a count row
    readonly property int pollSeconds: {
        const n = parseInt(String(Plasmoid.configuration.interval), 10)
        if (!isFinite(n)) return 10
        return Math.max(5, Math.min(3600, n))
    }
    readonly property bool showOffline: Plasmoid.configuration.showOffline === true

    // ---- Parsed state (single source of truth for both representations) ---
    // Set by applyStatus() from Model.parseStatusPlus output; null = no tick yet.
    property var status: null
    // Raw Peer map from the same payload, keyed by node key. Model.js ports
    // verbatim and its normalized peers (peerFromStatus) do not carry
    // AllowedIPs, so subnet routes are read from here, joined on peer.id.
    property var rawPeers: ({})
    property string unavailableMessage: ""
    property string lastError: ""

    // ---- v0.3 (§R) state ------------------------------------------------
    // edgeState discriminates failure modes the old popup collapsed into
    // one "Disconnected" (§R-8): ok | backdown | binmissing | parseerror.
    property string edgeState: "ok"
    // Provenance: local time of the last successful status tick (§R-5 —
    // UI state, not model data; the payload carries no timestamp).
    property real statusStampMs: 0
    // Clock for freshness verdicts; nudged 150 ms after popup open and
    // once per second while open (PopupShell owns the timers).
    property real clockNow: 0
    // §T-1 operator identity carried out of parseOperatorPrefs (v0.2
    // stored only state+hint and dropped the operator name).
    property string gateOperator: ""

    // ---- v0.4 (§V) state -------------------------------------------------
    // §V-2: lastTab retired with the tabs. Search query is the single
    // source of truth for search mode (typing, Esc, ✕, popup-close all
    // funnel through this property).
    property string peerQuery: ""
    // §W-9: search reveal state (runtime, not config) — the checkable
    // header button and Ctrl+F set it; popup close collapses it. The
    // field itself lives in SearchRow; this is the single source of truth
    // for revealed/collapsed.
    property bool searchOpen: false
    // §V-8: results computed over ALL peers (offline included, rendered
    // muted by the row); empty query = sections mode.
    readonly property var searchResults: peerQuery !== ""
        ? Model.searchPeers(peers, peerQuery) : []

    // ---- v0.7 (§V7) state -----------------------------------------------
    // §V7-2 selected tab: 0 PEERS · 1 EXIT NODES · 2 DEVICE. Reset on
    // every popup open (fresh-open law): PEERS when running, DEVICE
    // when not. Never persisted.
    property int selectedTab: 0
    // §V7-5 detail page state: the peer being inspected (null = list).
    // PeersTab pushes/pops its StackView in sympathy.
    property var detailPeer: null
    // §V7-5 TRAFFIC rates: prevSample keyed by peer id; rateMap holds
    // FORMATTED per-peer rates after ≥2 samples (main.qml owns the
    // derivation — Model.js stays untouched).
    property var prevSamples: ({})
    property var rateMap: ({})
    function updateRates() {
        const now = Date.now()
        const prev = prevSamples
        const next = {}
        const rates = {}
        for (let i = 0; i < peers.length; i++) {
            const p = peers[i]
            const id = String(p.id)
            const rx = Number(p.RxBytes || 0)
            const tx = Number(p.TxBytes || 0)
            const old = prev[id]
            if (old) {
                const ds = (now - old.ms) / 1000
                if (ds > 0.5) {
                    const rxRate = (rx - old.rx) / ds
                    const txRate = (tx - old.tx) / ds
                    rates[id] = {
                        ready: true,
                        idle: rxRate <= 0 && txRate <= 0,
                        rx: Model.fmtBytes(Math.max(0, rxRate)),
                        tx: Model.fmtBytes(Math.max(0, txRate))
                    }
                    next[id] = { rx: rx, tx: tx, ms: now }
                    continue
                }
                next[id] = old          // sample too close: keep the older
                if (prevRates[id]) rates[id] = prevRates[id]
                continue
            }
            rates[id] = { ready: false, idle: false, rx: "", tx: "" }
            next[id] = { rx: rx, tx: tx, ms: now }
        }
        prevSamples = next
        prevRates = rates
        rateMap = rates
    }
    property var prevRates: ({})
    // §V7-7 raw self IPv6 (plumbed from the raw payload; empty = hide).
    property string selfIp6: ""

    function activeExitPeer() {
        const ps = peers || []
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].ExitNode === true) return ps[i]
        }
        return null
    }

    // Popup height budget (§V-5): PopupShell clamps to 0.9·this.
    readonly property real availPopupHeight: Plasmoid.availableHeight || 0

    // §V-4 sections, recomputed on every good tick (cheap; ≤40 peers):
    // exitNodes  = online, exit-capable, NOT the currently-active one
    //              (the banner owns that) — Trayscale: own section,
    //              excluded from the census, never duplicated.
    // censusPeers = online, not exit-capable — alphabetical.
    property var exitNodes: []
    property var censusPeers: []

    function recomputeSections() {
        const cands = []
        const census = []
        for (let i = 0; i < onlinePeers.length; i++) {
            const p = onlinePeers[i]
            if (p.ExitNode === true) continue
            const raw = rawPeers[String(p && p.id)] || {}
            if (Control.isExitCandidate(p, raw)) cands.push(p)
            else census.push(p)
        }
        const byName = function (a, b) {
            return peerName(a).localeCompare(peerName(b))
        }
        exitNodes = cands.sort(byName)
        censusPeers = census.sort(byName)
    }

    // §R-3: computed exit-node candidate count for the Status hint.
    function exitCandidateCount() {
        let n = 0
        for (let i = 0; i < onlinePeers.length; i++) {
            const peer = onlinePeers[i]
            if (peer.ExitNode === true) continue
            if (Control.isExitCandidate(
                    peer, rawPeers[String(peer && peer.id)] || {})) n++
        }
        return n
    }

    // §R-8 edge overlay copy — centered on Status/Peers when set.
    function edgeOverlayText() {
        if (needsLogin) return "NEEDS LOGIN · RUN: tailscale login"
        if (edgeState === "backdown")
            return "TAILSCALED NOT RESPONDING · RETRY EVERY " + pollSeconds + " S"
        if (edgeState === "binmissing")
            return "TAILSCALE BINARY MISSING · INSTALL TAILSCALE"
        if (edgeState === "parseerror") return "STATUS ERROR · RETRYING"
        return ""
    }

    readonly property bool running: status ? status.running : false
    readonly property bool needsLogin: status ? status.needsLogin : false
    readonly property var peers: status && running ? status.peers : []
    readonly property var onlinePeers: Model.filterOnline(peers, true)
    readonly property var offlinePeers: Model.filterOnline(peers, false)
    readonly property var health: status && running ? Model.healthList(status.health) : []

    // State of the tailnet, as displayed: Running = up, NeedsLogin/Stopped =
    // down (crossed), anything else (Starting, Loading, WantsLogin variants
    // on older clients) = warning badge. Mirrors the TailscaleIcon logic.
    readonly property bool iconCrossed: running === false && needsLogin === false
    readonly property bool iconWarning: needsLogin || (running && health.length > 0)

    function iconColor() {
        if (!running && !needsLogin) return Kirigami.Theme.disabledTextColor
        return Kirigami.Theme.textColor
    }

    // ---- Control layer (v0.2, UX-SPEC-CONTROL.md r2) ------------------------
    // Mirror properties carry Control.js state into change-notified QML
    // bindings (plain JS objects don't notify); mutation happens only in the
    // handlers below, which update the mirrors in the same step.
    property bool ctlBusy: false
    property string ctlError: ""
    property string ctlSwitching: ""   // exit-set target while in flight
    property bool ctlArmed: false
    property string gateState: "unavailable"  // enabled | disabled | unavailable
    property string gateHint: ""
    readonly property bool controlsEnabled: gateState === "enabled"
    readonly property var confirm: new Control.Confirm()
    readonly property var ops: new Control.Ops()
    property string currentOp: ""      // op in flight, "" when idle
    property string currentOpCmd: ""   // engine source string for it
    property string gateUser: ""
    property bool gateUserDone: false
    property string gatePrefs: ""
    property int gatePrefsCode: 1
    property bool gatePrefsDone: false

    function pollNow() {
        execSource.connectSource(statusCommand())
    }

    // §T-2/§T-5: the ONLY place control argv reach the engine. Never driven
    // by automation — harness/test runs point PATH at a stub binary.
    function runControlOp(op, target) {
        if (ctlBusy || !controlsEnabled) return
        disarmConfirm()
        if (ops.begin(op, target) !== "accepted") return
        currentOp = op
        currentOpCmd = Control.argv(op, target).join(" ")
        ctlBusy = true
        ctlError = ""
        ctlSwitching = ops.target
        watchdog.interval = ops.timeoutFor(op)
        watchdog.restart()
        execSource.connectSource(currentOpCmd)
    }

    function disarmConfirm() {
        confirm.disarm()
        ctlArmed = false
        armTimer.stop()
    }

    function endControlOp() {
        currentOp = ""
        currentOpCmd = ""
        ctlBusy = false
        ctlSwitching = ""
        watchdog.stop()
        pollNow()  // §T-5: feedback is the refreshed status, not a toast
        // §V7-7: option facts + exitNodeIp refresh exactly when they
        // change — re-run the allowlisted read-only probe (no new exec
        // source; argv("probe") is already in §T-2's allowlist).
        execSource.connectSource(Control.argv("probe").join(" "))
    }

    // §T-3 click handling for the header toggle (confirm + dead-zone).
    function powerClicked() {
        if (ctlBusy) return
        if (running) {
            const r = confirm.click(Date.now())
            ctlArmed = confirm.armed()
            if (r === "arm") {
                armTimer.restart()
            } else if (r === "fire") {
                runControlOp("down")
            }
            // "ignored" (dead-zone): stays armed, window keeps running.
        } else {
            runControlOp("up")
        }
    }

    // §T-1 operator gate — computed once both read-only probes answered.
    function gateUpdate() {
        if (!gateUserDone || !gatePrefsDone) return
        const g = Control.parseOperatorPrefs(gatePrefs, gatePrefsCode, gateUser)
        gateState = g.state
        gateHint = g.hint
        gateOperator = g.operator || ""
    }

    // ---- Data plumbing ------------------------------------------------------
    // The executable dataengine keys sources by command string. We use the
    // connect/disconnect pattern from the shipped plasma-sysmon port: interval
    // 0 (run once per connect), a Timer reconnects on the configured interval
    // so a config change takes effect immediately without re-installing.
    function statusCommand() {
        return "tailscale status --json"
    }

    function applyStatus(raw) {
        const parsed = Model.parseStatusPlus(raw)
        if (!parsed.ok) {
            edgeState = "parseerror"
            unavailableMessage = parsed.message || "Status error"
            lastError = parsed.error || ""
            status = null
            rawPeers = ({})
            return
        }
        if (parsed.unavailable) {
            edgeState = "backdown"
            unavailableMessage = parsed.message || "Disconnected"
            status = null
            rawPeers = ({})
            return
        }
        edgeState = "ok"
        unavailableMessage = ""
        lastError = ""
        statusStampMs = Date.now()
        status = parsed
        // Keep the raw Peer map for fields the normalizer drops (AllowedIPs).
        // parseStatusPlus succeeded => the text is valid JSON; parse is safe.
        try {
            const rawObj = JSON.parse(String(raw))
            rawPeers = rawObj.Peer || ({})
            // §V7-7: self IPv6 straight from the raw payload (empty = hide).
            const selfIps = (rawObj.Self && rawObj.Self.TailscaleIPs) || []
            let v6 = ""
            for (let i = 0; i < selfIps.length; i++) {
                if (String(selfIps[i]).indexOf(":") >= 0) {
                    v6 = String(selfIps[i])
                    break
                }
            }
            selfIp6 = v6
        } catch (e) {
            rawPeers = ({})
            selfIp6 = ""
        }
        recomputeSections()
        updateRates()
    }

    DataSource {
        id: execSource
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            const code = data["exit code"]
            if (cmd.indexOf("tailscale status") >= 0) {
                const out = data["stdout"] || ""
                if (code === 0) {
                    root.applyStatus(out)
                } else {
                    // §R-8: discriminate the failure BEFORE collapsing.
                    // exit 127 / "not found" = binary missing; anything
                    // else non-zero with empty stdout = tailscaled down.
                    const err = String(data["stderr"] || "").trim()
                    if (code === 127 || /not found/i.test(err)) {
                        root.edgeState = "binmissing"
                    } else {
                        root.edgeState = "backdown"
                        root.lastError = err
                    }
                    root.unavailableMessage = "Disconnected"
                    root.status = null
                    root.rawPeers = ({})
                }
            } else if (cmd === "id -un") {
                // §T-1 probes (read-only, once per plasmoid load).
                root.gateUser = String(data["stdout"] || "").split("\n")[0] || ""
                root.gateUserDone = true
                root.gateUpdate()
            } else if (cmd.indexOf("debug prefs") >= 0) {
                root.gatePrefs = String(data["stdout"] || "")
                root.gatePrefsCode = (code === undefined || code === null) ? 1 : code
                root.gatePrefsDone = true
                root.gateUpdate()
            } else if (cmd !== "" && cmd === root.currentOpCmd) {
                // §T-5: control op ended (process exit). Kill the watchdog
                // first so a late tick can't race the finish.
                watchdog.stop()
                root.ops.finish(root.currentOp,
                                (code === undefined || code === null) ? 1 : code,
                                String(data["stdout"] || ""),
                                String(data["stderr"] || ""))
                root.ctlError = root.ops.lastError
                root.endControlOp()
            }
            execSource.disconnectSource(sourceName)
        }
    }

    // §T-1: run the two read-only gate probes once at load.
    Component.onCompleted: {
        execSource.connectSource("id -un")
        execSource.connectSource(Control.argv("probe").join(" "))
    }

    Timer {
        id: pollTimer
        interval: root.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: execSource.connectSource(root.statusCommand())
    }

    // §T-5 op watchdog: up 30 s, down/exit ops 15 s (set per op).
    Timer {
        id: watchdog
        interval: 15000
        onTriggered: {
            if (root.currentOpCmd !== "") {
                execSource.disconnectSource(root.currentOpCmd)
            }
            root.ops.timeout(root.currentOp)
            root.ctlError = root.ops.lastError
            root.endControlOp()
        }
    }

    // §T-3: 4 s auto-disarm window.
    Timer {
        id: armTimer
        interval: 4000
        onTriggered: {
            if (root.confirm.expired(Date.now())) root.disarmConfirm()
        }
    }

    // ---- Presentation helpers (mirror Panel.qml/PeerRow semantics) ---------
    function peerName(peer) {
        return String((peer && (peer.DisplayName || peer.HostName)) || "Unknown")
    }

    // Subnet routes a peer advertises, in the spirit of Panel.qml's InfoRow
    // route display: AllowedIPs (from the raw Peer map — the normalized peer
    // does not carry them) minus the peer's own /32 and /128 entries — what's
    // left is 0.0.0.0/0-style exit-node or 192.168.x.0/24 subnet ads.
    function subnetRoutes(peer) {
        const raw = rawPeers[String(peer && peer.id)] || {}
        const allowed = raw.AllowedIPs || []
        const out = []
        for (let i = 0; i < allowed.length; i++) {
            const entry = String(allowed[i] || "")
            if (entry === "") continue
            if (entry.endsWith("/32") || entry.endsWith("/128")) continue
            out.push(entry)
        }
        return out
    }

    // v0.5 (§W) data derivations — direct path vs DERP relay, from the raw
    // Peer map (CurAddr non-empty ⇒ direct connection; Relay = DERP region
    // code, e.g. "dfw", present even when idle). Mirrors the admin console
    // Connection column; see vault research note 2026-11-07 §4.
    function peerIsDirect(peer) {
        const raw = rawPeers[String(peer && peer.id)] || {}
        return String(raw.CurAddr || "") !== ""
    }

    function peerRelay(peer) {
        const raw = rawPeers[String(peer && peer.id)] || {}
        return String(raw.Relay || "")
    }

    function exitBannerText() {
        if (!running) return ""
        for (let i = 0; i < peers.length; i++) {
            if (peers[i].ExitNode === true) return String(peers[i].HostName || "")
        }
        return status && status.activeMullvadExit ? String(status.activeMullvadExit) : ""
    }

    // ==========================================================================
    // COMPACT representation (panel chip), mirroring the BarWidget-style chip:
    // Tailscale 3x3 dot glyph (TailscaleIcon.qml logic, drawn natively) +
    // online/total count. Click toggles the popup.
    // ==========================================================================
    compactRepresentation: MouseArea {
        id: chip

        hoverEnabled: true

        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3 + 10
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        // Panel-squeeze floor: without this, a full panel allocates the
        // applet less than its implicit width and the centered chipRow
        // paints OUTSIDE the item — observed 2026-11-07 as the 19/40
        // count rendering ~10px into the sysmon widget's slot. The panel
        // must take squeeze-px from expanding spacers instead.
        Layout.minimumWidth: implicitWidth

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            // Tailscale mark: 3x3 dot grid, inactive dots faded — the same
            // rendering TailscaleIcon.qml does, minus its SVG dependencies.
            Item {
                id: glyph
                property real markSize: Kirigami.Units.iconSizes.small
                width: markSize
                height: markSize
                opacity: root.running ? 1.0 : 0.55

                readonly property real dotSize: Math.max(2, markSize * 0.24)
                readonly property real mid: (markSize - dotSize) / 2
                readonly property real endPos: markSize - dotSize

                Repeater {
                    model: [
                        { x: 0,       y: 0,       o: 0.24 },
                        { x: glyph.mid, y: 0,     o: 0.24 },
                        { x: glyph.endPos, y: 0,  o: 0.24 },
                        { x: 0,       y: glyph.mid, o: 1.0 },
                        { x: glyph.mid, y: glyph.mid, o: 1.0 },
                        { x: glyph.endPos, y: glyph.mid, o: 1.0 },
                        { x: 0,       y: glyph.endPos, o: 0.24 },
                        { x: glyph.mid, y: glyph.endPos, o: 1.0 },
                        { x: glyph.endPos, y: glyph.endPos, o: 0.24 }
                    ]

                    Rectangle {
                        required property var modelData
                        x: modelData.x
                        y: modelData.y
                        width: glyph.dotSize
                        height: glyph.dotSize
                        radius: width / 2
                        color: root.iconColor()
                        opacity: modelData.o
                    }
                }

                // Crossed bar: disconnected and not just needing a login.
                Rectangle {
                    visible: root.iconCrossed
                    anchors.centerIn: parent
                    width: parent.width * 1.22
                    height: Math.max(2, parent.height * 0.14)
                    radius: height / 2
                    color: root.iconColor()
                    rotation: -45
                }

                // Warning badge (needs login / health warnings while running).
                Rectangle {
                    visible: root.iconWarning
                    width: Math.max(7, parent.width * 0.42)
                    height: width
                    radius: width / 2
                    color: Kirigami.Theme.negativeTextColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    border.color: Kirigami.Theme.backgroundColor
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: Kirigami.Theme.backgroundColor
                        font.pixelSize: Math.max(6, parent.height * 0.72)
                        font.bold: true
                    }
                }
            }

            PC3.Label {
                text: root.running
                      ? root.onlinePeers.length + "/" + root.peers.length
                      : (root.needsLogin ? "!" : "–")
                font: Kirigami.Theme.smallFont
                color: chip.containsMouse ? Kirigami.Theme.textColor
                                          : Kirigami.Theme.disabledTextColor
            }
        }

        onClicked: root.expanded = !root.expanded
    }

    // ==========================================================================
    // FULL representation (popup): §V single sectioned view — header →
    // identity → message strip → search → EXIT NODES / ONLINE / OFFLINE
    // stack → footer. No tabs (§V-2). All sizing lives in PopupShell.qml
    // (single-site rule).
    // ==========================================================================
    fullRepresentation: PopupShell {
        ctx: root
    }
}