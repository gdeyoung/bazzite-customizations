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
            unavailableMessage = parsed.message || "Status error"
            lastError = parsed.error || ""
            status = null
            rawPeers = ({})
            return
        }
        if (parsed.unavailable) {
            unavailableMessage = parsed.message || "Disconnected"
            status = null
            rawPeers = ({})
            return
        }
        unavailableMessage = ""
        lastError = ""
        status = parsed
        // Keep the raw Peer map for fields the normalizer drops (AllowedIPs).
        // parseStatusPlus succeeded => the text is valid JSON; parse is safe.
        try {
            rawPeers = JSON.parse(String(raw)).Peer || ({})
        } catch (e) {
            rawPeers = ({})
        }
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
                    // Non-zero: tailscaled down or CLI missing. Empty output makes
                    // Model.parseStatusPlus report {ok, unavailable} -> chip shows
                    // the disconnected glyph, exactly like the Omarchy service.
                    root.applyStatus("")
                    root.lastError = String(data["stderr"] || "").trim()
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

    // One string: "100.x.y.z · dns.name" — the PeerRow sub-line, trimmed to
    // the fields the Plasma popup shows (no traffic counters: those need
    // cumulative-to-rate math that is meaningless on a slow poll).
    function peerSubLine(peer) {
        const parts = []
        const ips = (peer && peer.TailscaleIPs) || []
        if (ips.length > 0) parts.push(String(ips[0]))
        const dns = String((peer && peer.DNSName) || "")
        if (dns !== "") parts.push(dns)
        if (!peer.Online) {
            const lastSeen = Model.fmtLastSeen(peer.LastSeen)
            parts.push(lastSeen === "never" ? "never seen" : "last seen " + lastSeen)
        }
        return parts.join("  ·  ")
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

        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

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
    // FULL representation (popup): device list exactly as Panel.qml lays it
    // out — self identity, health warnings, exit-node banner, machine list
    // with name / connection state / subnet routes / self-IPs, offline
    // collapsed behind a count (configurable). Self-sizing.
    // ==========================================================================
    fullRepresentation: Item {
        id: popup

        // §T-3/§T-5: popup close disarms the confirm; popup reopen
        // dismisses the last op error.
        onVisibleChanged: {
            if (visible) {
                root.ctlError = root.ops.lastError = ""
            } else {
                root.disarmConfirm()
            }
        }

        Layout.preferredWidth: Kirigami.Units.gridUnit * 32
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        // Self-size to content: the scroll view grows with the machine list,
        // floored at minimumHeight, capped at gridUnit * 30 so a 40-peer
        // tailnet doesn't tower over the panel.
        Layout.preferredHeight: Math.min(
            Kirigami.Units.gridUnit * 30,
            Math.max(popup.Layout.minimumHeight, listColumn.implicitHeight + 3 * Kirigami.Units.largeSpacing))

        // ---- Header: device identity ------------------------------------
        ColumnLayout {
            id: listColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 1.5
            spacing: Kirigami.Units.smallSpacing

            // ---- Header: device identity + §T-3 power toggle ---------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    Layout.fillWidth: true
                    text: root.status && root.status.selfName
                          ? root.status.selfName
                          : "Tailscale"
                    color: Kirigami.Theme.textColor
                    font.bold: true
                    elide: Text.ElideRight
                }

                // §T-3: enabled styling is honest — normal textColor at
                // rest, negative only while armed; disabled palette only
                // when actually disabled (busy).
                PC3.ToolButton {
                    id: powerBtn
                    visible: root.controlsEnabled
                    enabled: !root.ctlBusy
                    flat: true
                    text: root.ctlBusy ? "working…"
                          : root.ctlArmed ? "Confirm disconnect"
                          : root.running ? "Disconnect" : "Connect"
                    palette.windowText: root.ctlArmed
                                        ? Kirigami.Theme.negativeTextColor
                                        : Kirigami.Theme.textColor
                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                    onClicked: root.powerClicked()
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.running && root.status
                      ? (root.status.selfIp
                         + (root.status.selfDnsName !== "" ? "  ·  " + root.status.selfDnsName : ""))
                      : ""
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideMiddle
            }

            // ---- §T-5 header message stack (fixed order) -------------------
            // 1. armed warning (§T-3)
            PC3.Label {
                Layout.fillWidth: true
                visible: root.ctlArmed
                text: "tailnet goes down here — remote access via ts.net drops until reconnect"
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
            // 2. op error (§T-5)
            PC3.Label {
                Layout.fillWidth: true
                visible: root.ctlError !== ""
                text: root.ctlError
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
            // 3. operator-gate hint (§T-1)
            PC3.Label {
                Layout.fillWidth: true
                visible: !root.controlsEnabled && root.gateHint !== ""
                text: root.gateHint
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }

            // ---- Exit-node banner (ActiveExitBanner) + §T-4 clear ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.exitBannerText() !== ""

                PC3.Label {
                    Layout.fillWidth: true
                    text: "▸ exit node: " + root.exitBannerText()
                    color: Kirigami.Theme.neutralTextColor
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                }

                PC3.ToolButton {
                    visible: root.controlsEnabled
                    enabled: !root.ctlBusy
                    flat: true
                    text: "×"
                    QQC2.ToolTip.text: "stop using exit node"
                    QQC2.ToolTip.visible: hovered
                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                    onClicked: root.runControlOp("exit-clear")
                }
            }

            // ---- Health warnings (ack-free port of the warnings section) -
            Repeater {
                model: root.health

                PC3.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: "⚠ " + modelData
                    color: Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WrapAnywhere
                }
            }

            // ---- Machine list (Machines tab) ------------------------------
            // Always scrollable: a 40-peer tailnet cannot fit a popup.
            PC3.ScrollView {
                id: machinesView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 6

                ListView {
                    id: machineList
                    // Direct Flickable child of ScrollView = its contentItem;
                    // the ScrollView sizes it — no anchors here.
                    model: root.showOffline || root.offlinePeers.length === 0
                           ? root.peers
                           : root.onlinePeers
                    boundsBehavior: Flickable.StopAtBounds

                    // Self is the implicit first machine, as in Panel.qml.
                    delegate: Item {
                        id: peerRow
                        required property var modelData
                        width: machineList.width
                        // name + sub-line + routes line (routes shown for
                        // advertisers only); height = 2 or 3 text rows.
                        readonly property var routes: root.subnetRoutes(peerRow.modelData)
                        readonly property bool showRoutes: routes.length > 0
                        height: peerCol.implicitHeight + Kirigami.Units.smallSpacing

                        ColumnLayout {
                            id: peerCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "●"
                                    color: peerRow.modelData.Online
                                           ? Kirigami.Theme.positiveTextColor
                                           : Kirigami.Theme.disabledTextColor
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.5
                                    opacity: peerRow.modelData.Online ? 1 : 0.5
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.peerName(peerRow.modelData)
                                    color: peerRow.modelData.Online
                                           ? Kirigami.Theme.textColor
                                           : Kirigami.Theme.disabledTextColor
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.62
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: peerRow.modelData.ExitNode
                                    text: "exit"
                                    color: Kirigami.Theme.neutralTextColor
                                    font: Kirigami.Theme.smallFont
                                }

                                // §T-4: use as exit node — candidates only,
                                // hidden on the active exit node itself.
                                // ≥gridUnit·1.4 hit target, spaced from the
                                // name so text clicks can't land here.
                                PC3.ToolButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: root.controlsEnabled
                                           && !peerRow.modelData.ExitNode
                                           && Control.isExitCandidate(
                                                  peerRow.modelData,
                                                  root.rawPeers[String(peerRow.modelData && peerRow.modelData.id)] || {})
                                    enabled: !root.ctlBusy
                                    flat: true
                                    text: "use"
                                    QQC2.ToolTip.text: "use " + root.peerName(peerRow.modelData) + " as exit node"
                                    QQC2.ToolTip.visible: hovered
                                    leftPadding: Kirigami.Units.smallSpacing * 1.5
                                    rightPadding: Kirigami.Units.smallSpacing * 1.5
                                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                                    onClicked: root.runControlOp(
                                        "exit-set", Control.exitTarget(peerRow.modelData))
                                }
                            }

                            PC3.Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: root.peerSubLine(peerRow.modelData)
                                color: Kirigami.Theme.disabledTextColor
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideMiddle
                            }

                            // §T-4: transient "switching…" on the target row,
                            // cleared on completion/failure/timeout.
                            PC3.Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: root.ctlSwitching !== ""
                                      && Control.exitTarget(peerRow.modelData) === root.ctlSwitching
                                      ? "switching…" : ""
                                color: Kirigami.Theme.neutralTextColor
                                font: Kirigami.Theme.smallFont
                            }

                            PC3.Label {
                                Layout.fillWidth: true
                                visible: peerRow.showRoutes
                                text: "routes: " + peerRow.routes.join(", ")
                                color: Kirigami.Theme.disabledTextColor
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    // ---- Offline collapsed count (fork's "N offline — hidden")
                    footer: Component {
                        Item {
                            width: machineList.width
                            visible: !root.showOffline && root.offlinePeers.length > 0
                            height: visible ? offlineLabel.implicitHeight + Kirigami.Units.smallSpacing : 0

                            PC3.Label {
                                id: offlineLabel
                                anchors.centerIn: parent
                                text: root.offlinePeers.length + " offline — hidden"
                                color: Kirigami.Theme.disabledTextColor
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }

                    PC3.Label {
                        anchors.centerIn: parent
                        visible: machineList.count === 0
                        text: root.running
                              ? "No machines."
                              : (root.unavailableMessage !== "" ? root.unavailableMessage : "Disconnected")
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }
    }
}
