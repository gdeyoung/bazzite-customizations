import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "../ui/zones.js" as Zones
import "../ui/Model.js" as Model

// Settings dialog (KConfig XT) for Time Piece — the Plasma-side equivalent of
// the Omarchy SettingsView.qml: world clocks (× to remove), a type-to-search
// city picker over the full tz database (zones.js, ported verbatim, with
// ET/PT/UTC aliases), the date-in-chip toggle + time format, and the timer /
// pomodoro defaults. The popup stays a read-out.
//
// Porting rule honored here too: one handler per signal per file — every
// button routes through ZoneButton.run, every spinbox through NumField.write,
// so onClicked / onValueModified appear exactly once each.
KCM.SimpleKCM {
    id: page

    component ZoneButton: QQC2.Button {
        property var run: null
        display: QQC2.AbstractButton.IconOnly
        onClicked: if (run) run()
    }

    component NumField: QQC2.SpinBox {
        property int bound: 0
        property var write: null
        value: bound
        onValueModified: if (write) write(value)
    }

    function chosenZones() {
        return Model.parseWorldClocks(String(cfg_worldClocks || ""))
    }

    function zoneIndex(zone) {
        const current = chosenZones()
        for (let i = 0; i < current.length; i++)
            if (current[i].zone === zone) return i
        return -1
    }

    function zoneAdd(zone) {
        const current = chosenZones()
        for (let i = 0; i < current.length; i++)
            if (current[i].zone === zone) return
        if (current.length >= 5) return
        const parts = zone.split("/")
        const city = parts[parts.length - 1]
        current.push({ label: city === "UTC" ? "UTC" : city.replace(/_/g, " "), zone: zone })
        cfg_worldClocks = Model.zonesToString(current)
    }

    function zoneRemove(zone) {
        const current = chosenZones()
        const kept = []
        for (let i = 0; i < current.length; i++)
            if (current[i].zone !== zone) kept.push(current[i])
        cfg_worldClocks = Model.zonesToString(kept)
    }

    Kirigami.FormLayout {
        id: form

        // ---- World clocks -------------------------------------------------
        ColumnLayout {
            Kirigami.FormData.label: i18n("World clocks:")
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: chosenRepeater
                model: page.chosenZones()

                RowLayout {
                    id: zoneRow
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: zoneRow.modelData.label
                        font.bold: true
                    }
                    QQC2.Label {
                        text: zoneRow.modelData.zone
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }
                    Item { Layout.fillWidth: true }
                    ZoneButton {
                        icon.name: "list-remove"
                        QQC2.ToolTip.text: i18n("Remove %1", zoneRow.modelData.zone)
                        QQC2.ToolTip.visible: hovered
                        run: function() { page.zoneRemove(zoneRow.modelData.zone) }
                    }
                }
            }
            QQC2.Label {
                visible: chosenRepeater.count === 0
                text: i18n("None yet — search below to add one (max 5).")
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }

        // Add-a-city search: matches on city first (US zone abbreviations as
        // aliases), region names only from three characters up, capped at 8.
        ColumnLayout {
            Kirigami.FormData.label: i18n("Add a city:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: searchField
                placeholderText: i18n("Search — city, region, or ET/PT/UTC…")
                onTextChanged: resultsRepeater.model = Model.filterZones(Zones.TZ_REGIONS, text, 8)
            }

            Repeater {
                id: resultsRepeater
                model: []

                RowLayout {
                    id: resultRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: resultRow.modelData.city
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.Label {
                        text: resultRow.modelData.subregion !== ""
                            ? resultRow.modelData.region + " · " + resultRow.modelData.subregion
                            : resultRow.modelData.region
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }
                    ZoneButton {
                        icon.name: "list-add"
                        enabled: page.zoneIndex(resultRow.modelData.zone) < 0
                        QQC2.ToolTip.text: i18n("Add %1", resultRow.modelData.zone)
                        QQC2.ToolTip.visible: hovered
                        run: function() {
                            page.zoneAdd(resultRow.modelData.zone)
                            searchField.clear()
                            searchField.forceActiveFocus()
                        }
                    }
                }
            }
            QQC2.Label {
                visible: searchField.displayText !== "" && resultsRepeater.count === 0
                text: i18n("No match — try a bigger city nearby.")
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }

        // ---- Chip ----------------------------------------------------------
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Panel chip:")
            text: i18n("Show the date in the panel chip")
            checked: cfg_showDate
            onToggled: cfg_showDate = checked
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Time format:")
            text: cfg_clockFormat
            placeholderText: "dddd MMM d h:mm AP"
            onEditingFinished: cfg_clockFormat = text
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Week starts on:")
            // s index 0 = Sunday … 6 = Saturday, matching JS Date.getDay()
            readonly property var dayNames: ["sunday", "monday", "tuesday", "wednesday",
                "thursday", "friday", "saturday"]
            model: [i18n("Locale default")].concat(dayNames.map(function(d) { return d.charAt(0).toUpperCase() + d.slice(1) }))
            currentIndex: {
                const idx = dayNames.indexOf(String(cfg_weekStartDay || ""))
                return idx < 0 ? 0 : idx + 1
            }
            onActivated: function(index) {
                cfg_weekStartDay = index === 0 ? "" : dayNames[index - 1]
            }
        }

        // ---- Timer / pomodoro ----------------------------------------------
        NumField {
            Kirigami.FormData.label: i18n("Timer default (minutes):")
            from: 1; to: 600
            bound: cfg_timerMinutes
            write: function(v) { cfg_timerMinutes = v }
        }
        NumField {
            Kirigami.FormData.label: i18n("Pomodoro focus (minutes):")
            from: 1; to: 120
            bound: cfg_pomodoroFocusMin
            write: function(v) { cfg_pomodoroFocusMin = v }
        }
        NumField {
            Kirigami.FormData.label: i18n("Pomodoro break (minutes):")
            from: 1; to: 60
            bound: cfg_pomodoroBreakMin
            write: function(v) { cfg_pomodoroBreakMin = v }
        }
        QQC2.Label {
            text: i18n("4 focus blocks, then a 15-minute long break. Phases advance on their own; a desktop notification marks each flip. The timer and pomodoro are mutually exclusive — starting one stops the other.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.preferredWidth: form.width - Kirigami.Units.gridUnit * 4
            wrapMode: Text.WordWrap
        }
    }
}
