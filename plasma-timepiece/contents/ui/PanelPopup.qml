import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Model.js" as Model
import "Palette.js" as Palette

// PanelPopup — fullRepresentation for com.gdeyoung.plasma.timepiece.
// v0.2 redesign per design/popup-ux-review-v2.md (UX-agent pass, 2026-10-30):
// the timer readout is the only hero (24px); date is title tier (14px); every
// label is micro caps (11px) on the fleet scale set in sysmon v0.8. One
// content width — the month grid's — for every section (the GU*24 floor that
// broke every left edge is gone). Month nav + TODAY pill live ABOVE the grid
// where calendars put them. The timer state machine (phases, bar, rail,
// verbs) is carried over verbatim from design/timer-ux-spec.md.
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

    // ---- Fleet type scale (sysmon v0.8): literal px on purpose —
    //      cross-widget consistency beats per-theme font scaling here.
    //      Popup geometry still scales via Kirigami.Units.
    readonly property int heroPx: 24   // bold        — timer readout ONLY
    readonly property int titlePx: 14  // DemiBold    — header date
    readonly property int bodyPx: 12   // regular/bold — day numbers, zone times
    readonly property int microPx: 11  // caps + ls   — every label/caption/pill

    readonly property int padH: Kirigami.Units.largeSpacing * 2        // 16 @1x
    readonly property int padV: Math.round(Kirigami.Units.largeSpacing * 1.5) // 12 @1x
    readonly property int sectionGap: Kirigami.Units.largeSpacing * 2   // 16 @1x
    readonly property int innerGap: Kirigami.Units.smallSpacing * 2     // 8 @1x

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

    // Calendar cell metrics (fixed seven-column grid).
    readonly property int cellWidth: Kirigami.Units.gridUnit * 2.4
    readonly property int cellHeight: Kirigami.Units.gridUnit * 1.6
    readonly property int weekColumnWidth: Kirigami.Units.gridUnit * 1.2

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

    function weekdayLabel(weekday) {
        return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
    }

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
    // WIDTH AUTHORITY: the month grid (gridColumn — header row + six week
    // rows, all fixed-width cells, no width:parent.width children) defines
    // the natural width; the popup adopts it via preferred+maximum, and only
    // then do the full-width sections inherit it. v0.1 had a GU*24 floor
    // here that made the popup ~76px wider than the grid while three
    // sections spanned full width — three content margins (P0-2). Removed.
    readonly property int contentWidth: gridColumn.implicitWidth + padH * 2
    Layout.preferredWidth: contentWidth
    Layout.maximumWidth: contentWidth
    Layout.preferredHeight: contentColumn.implicitHeight + padV * 2
    Layout.minimumHeight: contentColumn.implicitHeight + padV * 2

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + padV * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: contentColumn
            x: padH
            y: padV
            width: scroll.width - padH * 2
            spacing: sectionGap

            // ---- Header: date title + year-progress caption, rule below.
            //      The static date dropped from a ~35px hero to title tier
            //      (the live timer readout is the widget's only hero), the
            //      dead "Back to today" band is gone (TODAY pill on the nav
            //      row replaces it), and the year labels no longer collide
            //      with the track — one right-aligned caption, full-width
            //      symmetric track.
            Column {
                width: parent.width
                spacing: 4

                Item {
                    width: parent.width
                    height: dateTitle.implicitHeight

                    Text {
                        id: dateTitle
                        anchors.left: parent.left
                        text: Qt.formatDate(applet.now, "dddd, MMMM d")
                        color: panel.fg
                        font.pixelSize: panel.titlePx
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.baseline: dateTitle.baseline
                        anchors.right: parent.right
                        text: Model.yearProgressPercent(applet.now.getFullYear(),
                            applet.now.getMonth(), applet.now.getDate())
                            + "% OF " + applet.now.getFullYear()
                        color: panel.muted
                        font.pixelSize: panel.microPx
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 1.5
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

            // ---- World clocks: equal-width stacked cells, one per zone —
            //      hue label over bold time, all sharing the grid's edges
            //      (was a left-hugging Flow reading as one run-on string).
            Row {
                width: parent.width
                visible: applet.worldClocks.length > 0

                Repeater {
                    model: applet.worldClocks

                    Item {
                        id: zoneCell
                        required property var modelData
                        required property int index
                        width: applet.worldClocks.length > 0
                            ? parent.width / applet.worldClocks.length : 0
                        height: 30

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: zoneCell.modelData.label
                                color: zoneCell.index < Palette.TZ_HUES.length
                                    ? Palette.TZ_HUES[zoneCell.index]
                                    : panel.muted
                                font.pixelSize: panel.microPx
                                font.letterSpacing: 1
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: {
                                    const t = zoneClocks.times[zoneCell.modelData.zone]
                                    return (t === undefined || t === "") ? "—" : t
                                }
                                color: panel.fg
                                font.bold: true
                                font.pixelSize: panel.bodyPx
                            }
                        }
                    }
                }
            }

            ZoneClocks {
                id: zoneClocks
                applet: panel.applet
                visible: false
            }

            // ---- Calendar block: nav row + weekday header + six week rows.
            //      gridColumn is the popup's WIDTH AUTHORITY — keep it free
            //      of width:parent.width children (navRow is an Item with
            //      implicit 0).
            Column {
                id: gridColumn
                spacing: Kirigami.Units.smallSpacing / 2

                // Nav: month label with its arrows, above the grid; TODAY
                // pill appears the moment the view steps away.
                Item {
                    width: parent.width
                    height: 28

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        TimerPill {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "‹"
                            width: 28
                            height: 24
                            foreground: panel.fg
                            run: function() { panel.moveMonth(-1) }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDate(new Date(panel.viewYear, panel.viewMonth, 1, 12),
                                "MMMM yyyy").toUpperCase()
                            color: panel.fg
                            font.pixelSize: panel.microPx
                            font.letterSpacing: 1.5
                        }
                        TimerPill {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "›"
                            width: 28
                            height: 24
                            foreground: panel.fg
                            run: function() { panel.moveMonth(1) }
                        }
                    }

                    TimerPill {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.viewYear !== applet.now.getFullYear()
                            || panel.viewMonth !== applet.now.getMonth()
                        label: "TODAY"
                        prominent: true
                        toneColor: panel.accent
                        foreground: panel.fg
                        run: panel.goToToday
                    }
                }

                Item { width: 1; height: Kirigami.Units.smallSpacing / 2 }

                // Weekday header. The "W" is a plain caption now — the
                // hidden click-to-toggle (zero discoverability) is gone;
                // week start lives in settings, one path.
                Row {
                    id: headerRow
                    spacing: Kirigami.Units.smallSpacing / 2

                    Text {
                        width: panel.weekColumnWidth
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 4
                        text: "W"
                        color: panel.muted
                        font.pixelSize: panel.microPx
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
                            font.pixelSize: panel.microPx
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
                            horizontalAlignment: Text.AlignRight
                            rightPadding: 4
                            text: weekRow.modelData.week
                            color: panel.muted
                            font.pixelSize: panel.microPx
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
                                    font.pixelSize: panel.bodyPx
                                    font.bold: dayCell.modelData.today
                                }
                            }
                        }
                    }
                }
            }

            // ---- Divider: gives the timer section a floor without boxing
            //      it into a card.
            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(panel.fg, 0.12)
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

                // Header: idle → the mode tabs ARE the label (no duplicated
                // section title); active → phase word + pulse dot.
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        id: sectionTitle
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !timerSection.idleOnly
                        text: applet.pomodoroActive
                            ? Model.pomodoroPhaseLabel(applet.pomodoroMode)
                                + " · " + (applet.pomodoroMode === "focus"
                                    ? (applet.pomodoroCyclesDone % Model.POMODORO_CYCLE) + 1
                                    : Math.min(applet.pomodoroCyclesDone, Model.POMODORO_CYCLE))
                                + " OF " + Model.POMODORO_CYCLE
                            : (applet.timerDoneAt > 0 ? "TIMER · DONE"
                                : (applet.timerRunning ? "TIMER · RUNNING"
                                    : "TIMER · PAUSED"))
                        color: applet.pomodoroActive ? timerSection.phaseColor : panel.muted
                        font.pixelSize: panel.microPx
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        anchors.left: sectionTitle.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
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
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Kirigami.Units.smallSpacing
                        visible: timerSection.idleOnly

                        Rectangle {
                            width: tabManualText.implicitWidth + Kirigami.Units.gridUnit
                            height: 24
                            radius: Kirigami.Units.smallSpacing / 2
                            border.width: 1
                            border.color: panel.timerTab === "manual" ? panel.accent : panel.hairline
                            color: panel.timerTab === "manual" ? Qt.alpha(panel.accent, 0.18) : "transparent"

                            Text {
                                id: tabManualText
                                anchors.centerIn: parent
                                text: "TIMER"
                                color: panel.timerTab === "manual" ? panel.accent : panel.fg
                                font.pixelSize: panel.microPx
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
                            height: 24
                            radius: Kirigami.Units.smallSpacing / 2
                            border.width: 1
                            border.color: panel.timerTab === "pomo" ? panel.accent : panel.hairline
                            color: panel.timerTab === "pomo" ? Qt.alpha(panel.accent, 0.18) : "transparent"

                            Text {
                                id: tabPomoText
                                anchors.centerIn: parent
                                text: "POMODORO"
                                color: panel.timerTab === "pomo" ? panel.accent : panel.fg
                                font.pixelSize: panel.microPx
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
                            font.pixelSize: panel.heroPx
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
                    height: 3
                    radius: 1.5
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
                    font.pixelSize: panel.microPx
                    font.letterSpacing: 1
                }

                // Verbs follow state; the primary carries the tone —
                // prominent pills get a persistent tinted fill + tone border
                // (the selected-tab idiom), not recolored text alone.
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
