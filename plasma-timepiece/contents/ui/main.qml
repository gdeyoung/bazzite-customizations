import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// com.gdeyoung.plasma.timepiece — Plasma 6 port of gdeyoung.timepiece
// (Omarchy). Port of github.com/gdeyoung/omarchy-timepiece @ 7e20cc9.
//
// Model.js is ported VERBATIM from the Omarchy plugin (pure JS, unit-tested
// under node — see test/). This file replaces the Quickshell BarWidget
// container: the panel chip shows date + time (plus a live timer/pomodoro
// suffix) and hosts the state engine that in Omarchy lived in the bar widget:
//
//  - the countdown/pomodoro fires HERE (the plasmoid is mounted all session,
//    exactly like the Omarchy bar widget was — a fire that depends on the
//    popup being open silently never happens);
//  - run state persists through Plasmoid.configuration, so a plasmashell
//    restart resumes the run (endsAt is absolute epoch-ms, so a restart
//    mid-run loses nothing);
//  - pomodoro phase flips fire a desktop notification via notify-send
//    (present on KDE), through the plasma5support executable engine,
//    fire-and-forget.
PlasmoidItem {
    id: root

    // ======================================================================
    // Clock
    // ======================================================================
    property date now: new Date()

    readonly property string configuredFormat: String(Plasmoid.configuration.clockFormat)
    // Tolerant reader kept from the Omarchy plugin (values can land as the
    // string "false" through config-file edits) — Model.applyShowDate accepts
    // both forms on the other side of this property.
    readonly property bool showDate: {
        const v = Plasmoid.configuration.showDate
        return !(v === false || v === "false")
    }
    readonly property string activeFormat: Model.applyShowDate(configuredFormat, showDate)
    readonly property string displayText: formatted(now)

    function formatted(d) {
        // Custom tokens Qt can't express: [UM] = UPPERCASE short month
        // ("OCT"), [OD] = ordinal day ("27th"). Swapped for non-letter
        // placeholders ('@@'/'##' are literal to Qt) and re-inserted after
        // formatting — letter placeholders would be parsed as Qt tokens.
        const fmt = activeFormat
        const hasUM = fmt.indexOf("[UM]") >= 0
        const hasOD = fmt.indexOf("[OD]") >= 0
        let base = fmt.split("[UM]").join("@@").split("[OD]").join("##")
        let out = Qt.formatDateTime(d, base.replace(/ww/g,
            Model.isoWeekLiteral(d.getFullYear(), d.getMonth(), d.getDate())))
        if (hasUM)
            out = out.split("@@").join(Qt.formatDate(d, "MMM").toUpperCase())
        if (hasOD)
            out = out.split("##").join(Model.ordinalDay(d.getDate()))
        return out
    }

    // ======================================================================
    // Timer + pomodoro state (persisted; transient keys in main.xml)
    // ======================================================================
    readonly property real timerEndsAt: Number(Plasmoid.configuration.timerEndsAt) || 0
    readonly property real timerRemainingMs: Number(Plasmoid.configuration.timerRemainingMs) || 0
    readonly property real timerDoneAt: Number(Plasmoid.configuration.timerDoneAt) || 0
    readonly property bool timerRunning: {
        const v = Plasmoid.configuration.timerRunning
        return v === true || v === "true"
    }
    readonly property int timerMinutes: {
        const v = Number(Plasmoid.configuration.timerMinutes)
        return (v >= 1 && v <= 600) ? Math.round(v) : 10
    }

    readonly property string pomodoroMode: {
        const v = Plasmoid.configuration.pomodoroMode
        return (v === "focus" || v === "break" || v === "longbreak") ? v : "off"
    }
    readonly property real pomodoroEndsAt: Number(Plasmoid.configuration.pomodoroEndsAt) || 0
    readonly property int pomodoroCyclesDone: Number(Plasmoid.configuration.pomodoroCyclesDone) || 0
    readonly property int pomodoroFocusMin: Model.clampPomodoroMinutes(Plasmoid.configuration.pomodoroFocusMin, 25, 1, 120)
    readonly property int pomodoroBreakMin: Model.clampPomodoroMinutes(Plasmoid.configuration.pomodoroBreakMin, 5, 1, 60)
    readonly property bool pomodoroActive: pomodoroMode !== "off"

    readonly property string timerSuffix: pomodoroMode !== "off" && pomodoroEndsAt > 0
        ? " · " + Model.pomodoroBarSuffix(pomodoroMode, Math.max(0, pomodoroEndsAt - now.getTime()))
        : (timerRunning
            ? " · " + Model.formatCountdown(Math.max(0, timerEndsAt - now.getTime()))
            : ((timerDoneAt > 0 && now.getTime() - timerDoneAt < 120000) ? " · done" : ""))

    // ======================================================================
    // World clocks — setting shape and validation live in
    // Model.parseWorldClocks; zones.js (ported verbatim) drives the picker
    // list in the settings dialog. Zone times are read by ZoneClocks.qml,
    // instantiated from the popup.
    // ======================================================================
    readonly property var worldClocks: Model.parseWorldClocks(String(Plasmoid.configuration.worldClocks || ""))

    function zonesRemove(zone) {
        const current = Model.parseWorldClocks(String(Plasmoid.configuration.worldClocks || ""))
        const kept = []
        for (let i = 0; i < current.length; i++)
            if (current[i].zone !== zone) kept.push(current[i])
        save({ worldClocks: Model.zonesToString(kept) })
    }

    // ======================================================================
    // Calendar
    // ======================================================================
    readonly property string todayKey: Model.keyForDate(now)
    readonly property int weekStart: Model.normalizedWeekStart(
        Plasmoid.configuration.weekStartDay, Qt.locale().firstDayOfWeek)

    function toggleWeekStart() {
        save({ weekStartDay: Model.weekStartSettingName(Model.toggledWeekStart(weekStart)) })
    }

    // ======================================================================
    // State writes — everything the popup's controls do funnels through here
    // ======================================================================
    function save(patch) {
        for (const k in patch) Plasmoid.configuration[k] = patch[k]
    }

    function timerStep(delta) {
        if (timerRunning || timerDoneAt > 0) return
        save({ timerMinutes: Model.stepTimerMinutes(timerMinutes, delta), timerRemainingMs: 0 })
    }

    function timerToggle() {
        if (timerRunning) {
            save({
                timerRunning: false,
                timerRemainingMs: Math.max(0, timerEndsAt - Date.now()),
                timerDoneAt: 0
            })
        } else {
            if (timerDoneAt > 0) { timerReset(); return }
            if (pomodoroActive) pomodoroStop() // modes are exclusive
            const remaining = timerRemainingMs > 0 ? timerRemainingMs : timerMinutes * 60000
            if (remaining <= 0) return
            save({ timerRunning: true, timerEndsAt: Date.now() + remaining, timerDoneAt: 0 })
        }
    }

    function timerReset() {
        save({ timerRunning: false, timerRemainingMs: 0, timerDoneAt: 0 })
    }

    function pomodoroStart() {
        save({
            timerRunning: false, timerRemainingMs: 0, timerDoneAt: 0,
            pomodoroMode: "focus",
            pomodoroEndsAt: Date.now() + pomodoroFocusMin * 60000,
            pomodoroCyclesDone: 0
        })
    }

    // SKIP while the popup is open; the natural fire path is checkFires().
    function pomodoroAdvance() {
        const next = Model.nextPomodoroPhase(pomodoroMode, pomodoroCyclesDone, pomodoroFocusMin, pomodoroBreakMin)
        if (!next) { pomodoroStop(); return }
        save({
            pomodoroMode: next.mode,
            pomodoroEndsAt: Date.now() + next.minutes * 60000,
            pomodoroCyclesDone: next.cyclesDone
        })
    }

    function pomodoroStop() {
        save({ pomodoroMode: "off", pomodoroEndsAt: 0 })
    }

    // The fire itself, ported from BarWidget.checkFires: pomodoro phases
    // advance on their own, the manual timer flips to its done ping, and the
    // ping ages out two minutes later.
    function checkFires(nowMs) {
        if (pomodoroMode !== "off" && pomodoroEndsAt > 0 && nowMs >= pomodoroEndsAt) {
            const next = Model.nextPomodoroPhase(pomodoroMode, pomodoroCyclesDone, pomodoroFocusMin, pomodoroBreakMin)
            if (!next) { save({ pomodoroMode: "off", pomodoroEndsAt: 0 }); return }
            save({ pomodoroMode: next.mode, pomodoroEndsAt: nowMs + next.minutes * 60000, pomodoroCyclesDone: next.cyclesDone })
            notifyPhase(next.mode)
        } else if (timerRunning && timerEndsAt > 0 && nowMs >= timerEndsAt) {
            save({ timerRunning: false, timerRemainingMs: 0, timerDoneAt: nowMs })
        } else if (!timerRunning && timerDoneAt > 0 && nowMs - timerDoneAt >= 120000) {
            save({ timerDoneAt: 0 })
        }
    }

    function notifySend(title, body) {
        fire.connectSource("notify-send -a 'Time Piece' -- '" + title + "' '" + body + "'")
    }

    function notifyPhase(mode) {
        const title = mode === "focus" ? "Focus time" : (mode === "longbreak" ? "Long break" : "Break time")
        const body = mode === "focus"
            ? pomodoroFocusMin + " min focus block — go."
            : ((mode === "longbreak" ? Model.POMODORO_LONG_BREAK_MIN : pomodoroBreakMin) + " min break.")
        notifySend(title, body)
    }

    // ======================================================================
    // Data plumbing — the notification DataSource: connect a command, run
    // once, disconnect in onNewData (fire-and-forget). Zone-time polling
    // lives in ZoneClocks.qml (one handler per signal per file).
    // ======================================================================
    DataSource {
        id: fire
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => fire.disconnectSource(String(sourceName))
    }

    // 1 s tick, always on (Quickshell's SystemClock has no Plasma
    // equivalent here): keeps `now` fresh for the chip's minute display and
    // the midnight rollover, and drives checkFires (phase flips, done ping,
    // ping aging — each branch is guarded, so it no-ops while idle).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const t = new Date()
            root.now = t
            root.checkFires(t.getTime())
            Plasmoid.toolTipMainText = root.displayText + root.timerSuffix
            Plasmoid.toolTipSubText = Qt.formatDateTime(t, "dddd, d MMMM yyyy")
                + (root.pomodoroActive ? "\nPomodoro " + Model.pomodoroPhaseLabel(root.pomodoroMode) : "")
        }
    }

    Component.onCompleted: {
        Plasmoid.toolTipMainText = "Time Piece"
        Plasmoid.toolTipSubText = Qt.formatDateTime(root.now, "dddd, d MMMM yyyy")
        Plasmoid.toolTipTextFormat = 0
    }

    // ======================================================================
    // Panel chip: date + time (the stock KDE clock shows no date by default —
    // date-in-chip is the point of the fork) + the timer/pomodoro suffix.
    // ======================================================================
    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true

        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.displayText
                color: chip.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                font: Kirigami.Theme.defaultFont
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.timerSuffix !== ""
                text: root.timerSuffix
                color: root.timerDoneAt > 0 && !root.pomodoroActive
                    ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
                opacity: 0.75
                font: Kirigami.Theme.smallFont
            }
        }

        onClicked: root.expanded = !root.expanded
    }

    // Popup: calendar + world clocks + timer section (design/timer-ux-spec).
    fullRepresentation: PanelPopup {
        applet: root
    }
}
