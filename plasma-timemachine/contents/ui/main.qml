import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "TmHelpers.js" as TH

// com.gdeyoung.plasma.timemachine — Plasma 6 port of gdeyoung.timemachine
// (Omarchy, v0.5.4 @ 519df33). Compact chip: status glyph + last-backup age;
// popup: five tabs (Status / Snapshots / Health / Recovery / Settings).
//
// Data bridge: bundled engine scripts under ../scripts/ emit one JSON line
// each — tm-probe.sh on the bar refresh interval (cheap, local-only state),
// tm-backups.sh + tm-snapper.sh + tm-conf.sh json once per popup open. All
// commands run through the executable dataengine (KProcess runs the string
// via a shell, so TM_CONF_FILE=<path> prefixes work; paths are shq()-quoted).
// The engine is the ported VERBATIM omarchy-timemachine shell pipeline.
PlasmoidItem {
  id: root

  // Expose self for ActionPill dispatch (resolved via dynamic scoping from
  // any child component that sets act: "<fnName>").
  readonly property var tmHost: root

  // ---- config (KConfig XT) ------------------------------------------------
  readonly property int refreshSeconds: Math.max(5, Math.min(60, Number(Plasmoid.configuration.refreshSeconds) || 15))
  readonly property int staleHours: Math.max(1, Math.min(168, Number(Plasmoid.configuration.staleHours) || 26))
  readonly property int failHours: Math.max(staleHours + 1, Math.min(336, Number(Plasmoid.configuration.failHours) || 72))
  readonly property int historyDays: Math.max(3, Math.min(90, Number(Plasmoid.configuration.historyDays) || 14))
  readonly property int snapshotRows: Math.max(5, Math.min(50, Number(Plasmoid.configuration.snapshotRows) || 10))
  // engine conf path parameter (public repo: NO LAN specifics in defaults)
  readonly property string confPath: {
    const p = String(Plasmoid.configuration.confPath || "")
    return p.length > 0 ? p : "~/.config/timemachine.conf"
  }
  readonly property string confPathDisplay: confPath

  // ---- probe state ----------------------------------------------------------
  property var probe: ({})
  property var snap: ({ status: "idle" })       // remote backups fetch (tm-backups.sh)
  property var snapper: ({ status: "idle" })     // local snapshots fetch (tm-snapper.sh)
  property var conf: ({ configured: false, sentinels: [] })   // tm-conf.sh json
  property string busy: ""        // "", "backup", "drill", "list"
  property string output: ""      // engine output tail shown in the popup
  property string recoverSnapshot: ""
  property int currentTab: 0

  readonly property string state: probe.state || "unknown"
  readonly property string label: probe.label || "backup host"
  readonly property color stateColor:
      state === "ok" ? Kirigami.Theme.positiveTextColor :
      state === "running" ? Kirigami.Theme.activeTextColor :
      state === "stale" ? Kirigami.Theme.neutralTextColor :
      state === "fail" ? Kirigami.Theme.negativeTextColor :
      Kirigami.Theme.disabledTextColor
  readonly property string ageText: probe.age_h === undefined || probe.age_h === null
    ? "--" : TH.fmtAge(probe.age_h)

  readonly property string tooltip:
      "Time Machine — " + (state === "ok" ? "protected" : state)
    + (probe.backup ? "\nlast  " + probe.backup + " · " + (probe.size_mb || 0) + " MB"
      + " · " + (probe.dur_s || 0) + "s" : "")
    + (probe.next_run ? "\nnext  " + probe.next_run : "")
    + "\nrepo  " + (probe.label || "not configured") + " (rsync, plaintext)"

  // ---- helper functions exposed to tab files --------------------------------
  function stateWord() {
    if (state === "ok") return "PROTECTED"
    if (state === "running") return "BACKING UP"
    if (state === "stale") return "STALE"
    if (state === "fail") return "FAILED"
    if (state === "never") return "NO BACKUP"
    return "UNKNOWN"
  }
  function verdictLine() {
    const v = probe.verify ? (probe.verify.pass + "/" + probe.verify.files) : null
    const d = probe.drill ? (probe.drill.pass + "/" + (probe.drill.pass + probe.drill.fail)) : null
    if (state === "running")
      return probe.age_h !== null && probe.age_h !== undefined
        ? "backup running — last complete " + ageText + " ago · watch the dot"
        : "first backup running"
    if (state === "never") return "no backups yet — BACK UP NOW starts the first one"
    if (state === "stale")
      return "last backup " + ageText + " ago · threshold "
        + Math.round(probe.thresholds ? probe.thresholds.stale_h : 26) + "h"
        + (probe.next_run ? " · next " + probe.next_run : "")
    if (state === "fail")
      return "last backup " + ageText + " ago · check " + label + " reachability"
        + (probe.next_run ? " · next " + probe.next_run : "")
    if (v && d) return "sentinel verify " + v + " · drill " + d + " · backups current"
    if (d) return "verify Sun · drill " + d + " · backups current"
    if (v) return "sentinel verify " + v + " · backups current"
    return "backups current — drill and verify pending"
  }
  function fmtTs(iso) { return TH.fmtTs(iso) }
  function fmtAgo(t) { return TH.fmtAgo(t) }
  function fmtIdDate(id) { return TH.fmtIdDate(id) }
  function fmtSize(mb) { return TH.fmtSize(mb) }
  function localSnapPath(subvol, id) { return TH.localSnapPath(subvol, id) }
  function bucketLetter(b) { return b === "daily" ? "D" : b === "weekly" ? "W" : "M" }
  function bucketColor(b) {
    return b === "daily" ? Kirigami.Theme.positiveTextColor
      : b === "weekly" ? Kirigami.Theme.activeTextColor : Kirigami.Theme.neutralTextColor
  }
  function dayGroups(rows, isBackup) { return TH.dayGroups(rows, isBackup) }
  function snapFresh() { return TH.snapFresh(snapper) }
  function snapFreshText() {
    const newest = TH.snapNewestT(snapper)
    const fresh = newest && (Date.now() / 1000 - newest) <= 7200
    return fresh
      ? "local snapshots current · " + TH.snapTotal(snapper) + " kept"
      : "local snapshots " + TH.fmtAgo(newest) + " old · " + TH.snapTotal(snapper) + " kept"
  }

  // day-picker state + helpers (in-memory; reset on every popup open)
  property var expandedDays: ({})   // dayKey -> bool; unset = today-only default
  function isExpanded(key) {
    if (expandedDays[key] === true) return true
    if (expandedDays[key] === false) return false
    return key === TH.todayKey()
  }
  function toggleDay(key) {
    // fresh object — same-reference reassignment never emits changed
    const d = {}
    const src = expandedDays
    for (const k in src) d[k] = src[k]
    d[key] = !isExpanded(key)
    expandedDays = d
  }

  // ---- actions (invoked by ActionPill dispatcher) ---------------------------
  function backupNow() {
    busy = "backup"
    appendOutput("starting backup service (runs async)…")
    runCmd("systemctl --user start " + TH.shq((probe.unit || "timemachine-backup") + ".service") + " ; true")
    probeTimer.restart()
  }
  function runDrill() {
    busy = "drill"
    output = ""
    appendOutput("running restore drill…")
    runScript("--drill")
  }
  function runScript(mode) {
    // engine script + one mode argument (tm-restore.sh --drill / --latest).
    // No "; true" here: applyRestore reads the REAL exit code for the verdict.
    runCmd(engEnv() + TH.shq(scriptPath("bin/tm-restore.sh")) + " " + mode)
  }
  function fetchBackups() { runCmd(engEnv() + TH.shq(scriptPath("tm-backups.sh")) + " ; true") }
  function fetchSnapper() { runCmd(TH.shq(scriptPath("tm-snapper.sh")) + " ; true") }
  function fetchConf() { runCmd(engEnv() + TH.shq(scriptPath("bin/tm-conf.sh")) + " json ; true") }
  function refreshAll() { refresh(); fetchBackups(); fetchSnapper(); fetchConf() }
  function clearRecover() { recoverSnapshot = "" }
  function preselect(id) { recoverSnapshot = id }
  function openPath(p) { runCmd("xdg-open " + TH.shq(p) + " ; true") }
  function copyText(s) {
    // text never lands in a process argument: base64 over stdin -> wl-copy
    const t = String(s === undefined || s === null ? "" : s)
    if (t === "") return
    const b64 = Qt.btoa(unescape(encodeURIComponent(t)))
    runCmd("printf %s " + TH.shq(b64) + " | base64 -d | wl-copy ; true")
  }

  function appendOutput(line) {
    const lines = (output + "\n" + line).split("\n").filter(l => l.length > 0)
    output = lines.slice(-14).join("\n")
  }

  // ---- data plumbing: executable dataengine ---------------------------------
  // Each distinct command string is its own source; interval 0 = run once per
  // connect, so onNewData disconnects after every read (reconnect re-runs).
  function scriptPath(name) {
    // single file:// prefix -> plain-string replace (first occurrence)
    return Qt.resolvedUrl("../scripts/" + name).toString().replace("file://", "")
  }
  function engEnv() {
    return "TM_CONF_FILE=" + confFileExpr() + " "
  }
  function confFileExpr() {
    // a leading ~ must expand: emit "$HOME"<single-quoted rest> so the shell
    // expands HOME while every other char stays literal (shq-safe)
    if (confPath.charAt(0) === "~")
      return '"$HOME"' + TH.shq(confPath.substring(1))
    return TH.shq(confPath)
  }
  function runCmd(cmd) { execSource.connectSource(cmd) }
  function refresh() {
    runCmd(engEnv() + TH.shq(scriptPath("tm-probe.sh")) + " "
      + TH.shq(String(staleHours)) + " " + TH.shq(String(failHours)) + " ; true")
  }

  DataSource {
    id: execSource
    engine: "executable"
    interval: 0
    onNewData: (sourceName, data) => {
      const cmd = String(sourceName)
      const out = (data["stdout"] || "").trim()
      const exitCode = Number(data["exit code"])
      if (cmd.indexOf("tm-probe.sh") >= 0) applyProbe(out)
      else if (cmd.indexOf("tm-backups.sh") >= 0) applySnap(out, exitCode)
      else if (cmd.indexOf("tm-snapper.sh") >= 0) applySnapper(out, exitCode)
      else if (cmd.indexOf("tm-conf.sh") >= 0) applyConf(out)
      else if (cmd.indexOf("tm-restore.sh") >= 0) applyRestore(out, exitCode)
      execSource.disconnectSource(sourceName)
    }
  }

  Timer {
    id: probeTimer
    interval: Math.max(5000, refreshSeconds * 1000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    refresh()
    fetchConf()
    Plasmoid.toolTipMainText = "Time Machine"
    Plasmoid.toolTipSubText = tooltip
    Plasmoid.toolTipTextFormat = 0   // plain text
  }

  onTooltipChanged: {
    Plasmoid.toolTipSubText = tooltip
  }

  // Popup-open data fetch (remote + local lists + conf — never on the bar
  // refresh path). MUST live here on the root: the fullRepresentation is
  // created lazily by Plasma, so a Connections inside it would miss the
  // very expanded-flip that creates it. Tab/day state resets on every open.
  onExpandedChanged: {
    if (!expanded) return
    fetchBackups()
    fetchSnapper()
    fetchConf()
    currentTab = 0
    recoverSnapshot = ""
    expandedDays = ({})
  }

  // ---- payload application ----------------------------------------------------
  function parseLine(text) {
    try {
      return JSON.parse(String(text).trim().split("\n").pop())
    } catch (e) {
      return null
    }
  }
  function applyProbe(text) {
    const data = parseLine(text)
    if (data) probe = data
  }
  function applySnap(text, exitCode) {
    const data = parseLine(text)
    if (data && data.status)
      snap = data.status === "ok" ? data
        : { status: data.status, detail: data.detail || "", scp_prefix: data.scp_prefix || "", rows: [] }
    else if (!snap || snap.status === "idle") snap = { status: "error", detail: "unparsable fetch", rows: [] }
  }
  function applySnapper(text, exitCode) {
    const data = parseLine(text)
    if (data && data.status) snapper = data
  }
  function applyConf(text) {
    const data = parseLine(text)
    if (data && data.configured !== undefined) conf = data
  }
  function applyRestore(text, exitCode) {
    // tm-restore.sh prints progress lines then a verdict; capture the tail
    const lines = String(text).trim().split("\n").filter(l => l.length > 0)
    for (let i = 0; i < lines.length; i++) appendOutput(lines[i])
    if (lines.length === 0 && exitCode !== 0) appendOutput("engine exited " + exitCode)
    busy = ""
    refresh()
  }

  // ===========================================================================
  // COMPACT representation (panel chip): status glyph + last-backup age.
  // States: running (pulse) · ok <stale · stale <fail · fail · never.
  // ===========================================================================
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
        // history glyph (clock + counter-clockwise arrow): back in time
        text: "⟲"
        color: root.stateColor
        font.pixelSize: Kirigami.Units.gridUnit * 0.8
        SequentialAnimation on opacity {
          running: root.state === "running"
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.25; duration: 600 }
          NumberAnimation { from: 0.25; to: 1; duration: 600 }
        }
      }
      Text {
        text: root.ageText
        color: compactRoot.containsMouse ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        font.bold: true
      }
    }

    onClicked: root.expanded = !root.expanded
  }

  fullRepresentation: Details {
    tm: root
  }
}
