import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import "Palette.js" as Palette

// PanelPopup — fullRepresentation for com.gdeyoung.plasma.timepiece,
// ported from the Omarchy Panel.qml: calendar + world clocks + the timer
// section redesigned per design/timer-ux-spec.md (24px mm:ss hero readout,
// TIMER|POMODORO mode tabs while idle, remaining-time phase bar, 4-segment
// cycle rail; phase color always co-coded with the phase word, digits stay
// foreground in every state). Fires live in the applet (main.qml), which is
// mounted all session — this popup only reads and issues commands.
Item {
    id: panel

    required property var applet

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color track: Kirigami.Theme.backgroundColor
    readonly property color hairline: Qt.alpha(panel.fg, 0.4)
    readonly property color trackFill: Qt.alpha(panel.fg, 0.12)
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color urgent: Kirigami.Theme.negativeTextColor

    // The interface is English throughout (as in the Omarchy original), so
    // day names come from a fixed locale; where the week starts still follows
    // the system locale and stays overridable in the settings dialog.
    readonly property var labelLocale: Qt.locale("en_US")

    // Month on screen. Stepping moves this and nothing else: the grid is a
    // read-out, not a picker.
    property int viewYear: applet.now.getFullYear()
    property int viewMonth: applet.now.getMonth()
    // In-memory mode tab for the timer section's idle state, NEVER persisted.
    property string timerTab: "manual"

    // Calendar cell metrics (fixed seven-column grid; cells sized from the
    // font so the grid scales with the user's font settings).
    readonly property int cellWidth: Kirigami.Units.gridUnit * 2.4
    readonly property int cellHeight: Kirigami.Units.gridUnit * 1.6
    readonly property int weekColumnWidth: Kirigami.Units.gridUnit * 1.6

    // Idle/active timer display value the section readout binds to.
    readonly property real timerDisplayMs: applet.timerRunning
        ? Math.max(0, applet.timerEndsAt - applet.now.getTime())
        : (applet.timerDoneAt > 0 ? 0 : applet.timerRemainingMs)

    function goToToday() {
        viewYear = applet.now.getFullYear()
        viewMonth = applet.now.getMonth()
    }

    function moveMonth(delta) {
        const next = Model.stepMonth(viewYear, viewMonth, delta)
        viewYear = next.year
        viewMonth = next.month
    }

    function moveYear(delta) { moveMonth(delta * 12) }

    function weekdayLabel(weekday) {
        return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
    }

    // Theme font sizes as plain properties — per-property font assignments
    // only (a whole-group `font:` assignment drops sub-property bindings
    // like letterSpacing/bold).
    readonly property int smallPx: Kirigami.Theme.smallFont.pixelSize
    readonly property int defaultPx: Kirigami.Theme.defaultFont.pixelSize

    // One declarative click surface for the whole file — the porting checker
    // (and the QML compiler) reject a second `onClicked` anywhere in one
    // file, so every clickable here routes through `run`.
    component Act: MouseArea {
        id: act
        property var run: null
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (act.run) act.run()
    }

    // Self-sizing popup: height tracks the content column; a plain fixed
    // height would under-fit the moment content or font scale changes.
    //
    // WIDTH AUTHORITY (v0.1 bug: popup expanded to ~full panel width): the
    // month grid defines the natural width; the popup adopts it via
    // preferred+maximum, and only THEN do contentColumn/timerSection and
    // every `width: parent.width` child inherit it. Never size the popup
    // from timerSection.implicitWidth — timerSection itself is
    // width: parent.width, so its implicitWidth feeds back on itself and
    // the dialog grows to whatever the panel offers.
    readonly property int contentWidth:
        Math.max(gridColumn.implicitWidth, Kirigami.Units.gridUnit * 24)
        + Kirigami.Units.largeSpacing * 4
    Layout.preferredWidth: contentWidth
    Layout.maximumWidth: contentWidth
    Layout.preferredHeight: contentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumHeight: contentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: contentColumn
            width: scroll.width
            spacing: Kirigami.Units.smallSpacing * 2

            // ---- Hero: today's date, centered. Once the view has stepped
            //      away it doubles as the way home.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Kirigami.Units.largeSpacing

                Text {
                    anchors.baseline: heroDate.baseline
                    text: "󰃭"
                    color: panel.fg
                    font.pixelSize: Kirigami.Units.gridUnit * 2
                }
                Text {
                    id: heroDate
                    text: Qt.formatDate(applet.now, "MMMM d")
                    color: panel.fg
                    font.pixelSize: Kirigami.Units.gridUnit * 2.2
                    font.bold: true
                }
            }
            Act {
                width: parent.width
                height: heroDate.height
                enabled: panel.viewYear !== applet.now.getFullYear()
                    || panel.viewMonth !== applet.now.getMonth()
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                run: panel.goToToday
                Text {
                    anchors.centerIn: parent
                    visible: parent.enabled
                    text: "Back to today"
                    color: panel.accent
                    font.pixelSize: panel.smallPx
                }
            }

            // ---- World clock row: labeled times in other zones, only when
            //      configured. Labels carry the categorical hue pass; the
            //      times stay foreground bold.
            Flow {
                width: parent.width
                visible: applet.worldClocks.length > 0
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: applet.worldClocks

                    Row {
                        id: zoneDelegate
                        required property var modelData
                        required property int index
                        spacing: Kirigami.Units.smallSpacing

                        Text {
                            anchors.baseline: zoneTimeText.baseline
                            text: zoneDelegate.modelData.label
                            color: zoneDelegate.index < Palette.TZ_HUES.length
                                ? Palette.TZ_HUES[zoneDelegate.index]
                                : panel.muted
                            font.letterSpacing: 1
                            font.pixelSize: panel.smallPx
                        }
                        Text {
                            id: zoneTimeText
                            text: {
                                const t = zoneClocks.times[zoneDelegate.modelData.zone]
                                return (t === undefined || t === "") ? "—" : t
                            }
                            color: panel.fg
                            font.bold: true
                        }
                    }
                }
            }

            ZoneClocks {
                id: zoneClocks
                applet: panel.applet
                visible: false
            }

            // ---- Year progress, doubling as the rule under the hero:
            //      whole days done over days in the year.
            Item {
                width: parent.width
                height: Kirigami.Units.gridUnit * 0.8

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: applet.now.getFullYear()
                    color: panel.muted
                    font.pixelSize: panel.smallPx
                    font.letterSpacing: 1
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.yearProgressPercent(applet.now.getFullYear(),
                        applet.now.getMonth(), applet.now.getDate()) + "%"
                    color: panel.fg
                    font.pixelSize: panel.smallPx
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Kirigami.Units.gridUnit * 2
                    anchors.rightMargin: Kirigami.Units.gridUnit * 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    height: Kirigami.Units.smallSpacing
                    radius: height / 2
                    color: panel.trackFill

                    Rectangle {
                        width: Math.round(parent.width * Model.yearProgress(
                            applet.now.getFullYear(), applet.now.getMonth(), applet.now.getDate()))
                        height: parent.height
                        radius: parent.radius
                        color: panel.accent

                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // ---- Month grid: week numbers down a gutter on the left, then
            //      the seven day columns. Always six rows, so the popup is
            //      exactly as tall in February as it is in August.
            Column {
                id: gridColumn
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Kirigami.Units.smallSpacing / 2

                Row {
                    id: headerRow
                    spacing: Kirigami.Units.smallSpacing / 2

                    Text {
                        width: panel.weekColumnWidth
                        horizontalAlignment: Text.AlignHCenter
                        text: "W"
                        color: panel.muted
                        font.pixelSize: panel.smallPx
                        font.bold: true
                        font.letterSpacing: 1

                        Act {
                            anchors.fill: parent
                            run: panel.applet.toggleWeekStart
                        }
                    }
                    Item { width: Kirigami.Units.smallSpacing * 2; height: 1 }
                    Repeater {
                        model: Model.weekdayOrder(panel.applet.weekStart)

                        Text {
                            required property var modelData
                            width: panel.cellWidth
                            horizontalAlignment: Text.AlignHCenter
                            text: panel.weekdayLabel(modelData)
                            color: panel.muted
                            font.pixelSize: panel.smallPx
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }
                }

                Repeater {
                    model: Model.monthGrid(panel.viewYear, panel.viewMonth,
                        panel.applet.weekStart, panel.applet.todayKey)

                    Row {
                        id: weekRow
                        required property var modelData
                        spacing: Kirigami.Units.smallSpacing / 2

                        Text {
                            width: panel.weekColumnWidth
                            horizontalAlignment: Text.AlignHCenter
                            text: weekRow.modelData.week
                            color: panel.muted
                            font.pixelSize: panel.smallPx
                        }
                        Item { width: Kirigami.Units.smallSpacing * 2; height: 1 }
                        Repeater {
                            model: weekRow.modelData.days

                            Rectangle {
                                id: dayCell
                                required property var modelData

                                width: panel.cellWidth
                                height: panel.cellHeight
                                radius: Kirigami.Units.smallSpacing / 2
                                // Today is outlined, not filled: a lit-up
                                // block shouts over a grid this quiet.
                                color: "transparent"
                                border.width: dayCell.modelData.today ? 1 : 0
                                border.color: panel.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: dayCell.modelData.day
                                    color: dayCell.modelData.inMonth
                                        ? (dayCell.modelData.weekend ? panel.muted : panel.fg)
                                        : Qt.alpha(panel.fg, 0.35)
                                    font.bold: dayCell.modelData.today
                                }
                            }
                        }
                    }
                }
            }

            // ---- Month stepping, spanning the grid it drives.
            Item {
                width: parent.width
                height: monthLabel.implicitHeight + Kirigami.Units.smallSpacing * 2

                Text {
                    id: monthLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.gridUnit * 8
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(panel.viewYear, panel.viewMonth, 1, 12), "MMMM yyyy").toUpperCase()
                    color: panel.fg
                    font.letterSpacing: 1
                }

                TimerPill {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    label: "‹"
                    foreground: panel.fg
                    run: function() { panel.moveMonth(-1) }
                }
                TimerPill {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "›"
                    foreground: panel.fg
                    run: function() { panel.moveMonth(1) }
                }
            }

            // ---- Timer section, per design/timer-ux-spec.md: the readout IS
            //      the section. Phase color always co-coded with the phase
            //      word; digits stay foreground in every state.
            Column {
                id: timerSection
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                readonly property bool idleOnly: !applet.timerRunning && applet.timerDoneAt === 0
                    && applet.timerRemainingMs === 0 && !applet.pomodoroActive
                readonly property color phaseColor: applet.pomodoroActive
                    ? (applet.pomodoroMode === "focus" ? panel.accent
                        : (applet.pomodoroMode === "longbreak" ? Palette.LONG_BREAK_HUE : Palette.BREAK_HUE))
                    : (applet.timerDoneAt > 0 ? panel.urgent : panel.accent)
                readonly property int phaseTotalMin: {
                    if (applet.pomodoroActive)
                        return applet.pomodoroMode === "focus" ? applet.pomodoroFocusMin
                            : (applet.pomodoroMode === "longbreak" ? Model.POMODORO_LONG_BREAK_MIN : applet.pomodoroBreakMin)
                    if (idleOnly && panel.timerTab === "pomo")
                        return applet.pomodoroFocusMin
                    return applet.timerMinutes
                }
                readonly property real remainingMs: {
                    if (applet.pomodoroActive)
                        return Math.max(0, applet.pomodoroEndsAt - applet.now.getTime())
                    if (idleOnly)
                        return (panel.timerTab === "pomo" ? applet.pomodoroFocusMin : applet.timerMinutes) * 60000
                    if (applet.timerDoneAt > 0)
                        return 0
                    return applet.timerDisplayMs
                }
                readonly property real phaseFraction: phaseTotalMin > 0
                    ? Math.min(1, remainingMs / (phaseTotalMin * 60000)) : 0

                // Section title: the phase word, co-coded with phaseColor.
                Item {
                    width: parent.width
                    height: sectionTitle.implicitHeight

                    Text {
                        id: sectionTitle
                        anchors.left: parent.left
                        text: applet.pomodoroActive
                            ? Model.pomodoroPhaseLabel(applet.pomodoroMode)
                                + " · " + (applet.pomodoroMode === "focus"
                                    ? (applet.pomodoroCyclesDone % Model.POMODORO_CYCLE) + 1
                                    : Math.min(applet.pomodoroCyclesDone, Model.POMODORO_CYCLE))
                                + " OF " + Model.POMODORO_CYCLE
                            : (applet.timerDoneAt > 0 ? "TIMER · DONE"
                                : (applet.timerRunning ? "TIMER · RUNNING"
                                    : (applet.timerRemainingMs > 0 && applet.timerDoneAt === 0 ? "TIMER · PAUSED"
                                        : (panel.timerTab === "pomo" ? "POMODORO" : "TIMER"))))
                        color: applet.pomodoroActive ? timerSection.phaseColor : panel.muted
                        font.pixelSize: panel.smallPx
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        anchors.left: sectionTitle.right
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.smallSpacing
                        height: width
                        radius: width / 2
                        visible: !timerSection.idleOnly
                        color: timerSection.phaseColor

                        SequentialAnimation on opacity {
                            running: applet.timerDoneAt > 0
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.25; duration: 500; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.25; to: 1; duration: 500; easing.type: Easing.InOutQuad }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: Kirigami.Units.smallSpacing
                        visible: timerSection.idleOnly

                        Rectangle {
                            width: tabManualText.implicitWidth + Kirigami.Units.gridUnit
                            height: Kirigami.Units.gridUnit * 1.5
                            radius: Kirigami.Units.smallSpacing / 2
                            border.width: 1
                            border.color: panel.timerTab === "manual" ? panel.accent : panel.hairline
                            color: panel.timerTab === "manual" ? Qt.alpha(panel.accent, 0.18) : "transparent"

                            Text {
                                id: tabManualText
                                anchors.centerIn: parent
                                text: "TIMER"
                                color: panel.timerTab === "manual" ? panel.accent : panel.fg
                                font.pixelSize: panel.smallPx
                                font.bold: true
                                font.letterSpacing: 1
                            }
                            Act {
                                anchors.fill: parent
                                run: function() { panel.timerTab = "manual" }
                            }
                        }
                        Rectangle {
                            width: tabPomoText.implicitWidth + Kirigami.Units.gridUnit
                            height: Kirigami.Units.gridUnit * 1.5
                            radius: Kirigami.Units.smallSpacing / 2
                            border.width: 1
                            border.color: panel.timerTab === "pomo" ? panel.accent : panel.hairline
                            color: panel.timerTab === "pomo" ? Qt.alpha(panel.accent, 0.18) : "transparent"

                            Text {
                                id: tabPomoText
                                anchors.centerIn: parent
                                text: "POMODORO"
                                color: panel.timerTab === "pomo" ? panel.accent : panel.fg
                                font.pixelSize: panel.smallPx
                                font.bold: true
                                font.letterSpacing: 1
                            }
                            Act {
                                anchors.fill: parent
                                run: function() { panel.timerTab = "pomo" }
                            }
                        }
                    }
                }

                // Hero: steppers flank the readout in fixed slots, so
                // centering never jumps when state changes.
                Item {
                    width: parent.width
                    height: timerHeroRow.height

                    Row {
                        id: timerHeroRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Kirigami.Units.smallSpacing * 3

                        TimerPill {
                            label: "−5M"
                            width: Kirigami.Units.gridUnit * 3.2
                            visible: !applet.pomodoroActive && (!timerSection.idleOnly || panel.timerTab === "manual")
                            dimmed: !timerSection.idleOnly
                            foreground: panel.fg
                            run: function() { panel.applet.timerStep(-5) }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Model.formatCountdown(timerSection.remainingMs)
                            color: applet.timerDoneAt > 0 && !applet.pomodoroActive
                                ? panel.urgent : panel.fg
                            font.pixelSize: Kirigami.Units.gridUnit * 1.5 // 24px hero readout
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        TimerPill {
                            label: "+5M"
                            width: Kirigami.Units.gridUnit * 3.2
                            visible: !applet.pomodoroActive && (!timerSection.idleOnly || panel.timerTab === "manual")
                            dimmed: !timerSection.idleOnly
                            foreground: panel.fg
                            run: function() { panel.applet.timerStep(5) }
                        }
                    }
                }

                // Remaining-time bar. Behavior-only motion, no re-layout.
                Rectangle {
                    width: parent.width
                    height: Math.max(3, Kirigami.Units.smallSpacing / 2)
                    radius: Kirigami.Units.smallSpacing / 4
                    visible: !timerSection.idleOnly
                    color: applet.timerDoneAt > 0 && !applet.pomodoroActive
                        ? Qt.alpha(panel.urgent, 0.15)
                        : panel.trackFill

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        width: parent.width * timerSection.phaseFraction
                        radius: parent.radius
                        color: timerSection.phaseColor

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }

                // The set at a glance: 4 segments = 4 focus blocks; accent is
                // work done, the half-alpha segment is the block in progress.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Kirigami.Units.smallSpacing
                    visible: applet.pomodoroActive

                    Repeater {
                        model: Model.POMODORO_CYCLE

                        Rectangle {
                            required property int modelData
                            width: (timerSection.width - 3 * Kirigami.Units.smallSpacing) / Model.POMODORO_CYCLE
                            height: Kirigami.Units.smallSpacing
                            radius: Kirigami.Units.smallSpacing / 2
                            color: {
                                const done = applet.pomodoroMode === "longbreak" ? Model.POMODORO_CYCLE
                                    : applet.pomodoroCyclesDone % Model.POMODORO_CYCLE
                                if (modelData <= done) return panel.accent
                                if (modelData === done + 1 && applet.pomodoroMode === "focus")
                                    return Qt.alpha(panel.accent, 0.5)
                                return panel.trackFill
                            }
                        }
                    }
                }

                // Pomodoro idle summary: the whole contract in one muted line.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: timerSection.idleOnly && panel.timerTab === "pomo"
                    text: "FOCUS " + applet.pomodoroFocusMin + " · BREAK " + applet.pomodoroBreakMin
                        + " · LONG " + Model.POMODORO_LONG_BREAK_MIN + " · " + Model.POMODORO_CYCLE + " BLOCKS"
                    color: panel.muted
                    font.pixelSize: panel.smallPx
                    font.letterSpacing: 1
                }

                // Verbs follow state; the primary carries the tone.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Kirigami.Units.smallSpacing * 2

                    TimerPill {
                        label: "START"
                        prominent: true
                        toneColor: panel.accent
                        visible: timerSection.idleOnly && panel.timerTab === "manual"
                        foreground: panel.fg
                        run: function() { panel.applet.timerToggle() }
                    }
                    TimerPill {
                        label: "PAUSE"
                        prominent: true
                        toneColor: panel.accent
                        visible: !applet.pomodoroActive && applet.timerRunning
                        foreground: panel.fg
                        run: function() { panel.applet.timerToggle() }
                    }
                    TimerPill {
                        label: "RESUME"
                        prominent: true
                        toneColor: panel.accent
                        visible: !applet.pomodoroActive && !applet.timerRunning && applet.timerRemainingMs > 0 && applet.timerDoneAt === 0
                        foreground: panel.fg
                        run: function() { panel.applet.timerToggle() }
                    }
                    TimerPill {
                        label: "RESET"
                        visible: !applet.pomodoroActive && !applet.timerRunning && applet.timerRemainingMs > 0 && applet.timerDoneAt === 0
                        foreground: panel.fg
                        run: function() { panel.applet.timerReset() }
                    }
                    TimerPill {
                        label: "RESET"
                        prominent: true
                        toneColor: panel.urgent
                        visible: !applet.pomodoroActive && applet.timerDoneAt > 0
                        foreground: panel.fg
                        run: function() { panel.applet.timerReset() }
                    }
                    TimerPill {
                        label: "START CYCLE"
                        prominent: true
                        toneColor: panel.accent
                        visible: timerSection.idleOnly && panel.timerTab === "pomo"
                        foreground: panel.fg
                        run: function() { panel.applet.pomodoroStart() }
                    }
                    TimerPill {
                        label: "SKIP →"
                        visible: applet.pomodoroActive
                        foreground: panel.fg
                        run: function() { panel.applet.pomodoroAdvance() }
                    }
                    TimerPill {
                        label: "STOP"
                        visible: applet.pomodoroActive
                        foreground: panel.fg
                        run: function() { panel.applet.pomodoroStop() }
                    }
                }
            }
        }
    }
}
