import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "lib/ViewModel.js" as ViewModel

// Overview (spec §D): hero + donut + legend + meta on the left (384),
// searchable app list on the right (528). Primary readouts fit without
// scrolling; the 254-row list scrolls in a reserved scrollbar lane.
ColumnLayout {
    id: page

    property bool showDonut: true
    property string heroAccent: "#58a6ff"

    readonly property bool hasData: MosaicStore.hasSnapshot
    readonly property var summary: hasData && MosaicStore.snapshot.summary ? MosaicStore.snapshot.summary : null
    readonly property var meta: hasData && MosaicStore.snapshot.meta ? MosaicStore.snapshot.meta : null
    readonly property bool limited: meta ? meta.limited === true : false
    readonly property int appTotal: hasData ? MosaicStore.snapshot.apps.length : 0
    readonly property int completeCount: summary ? summary.completed : 0
    readonly property int partialCount: {
        const list = hasData ? MosaicStore.snapshot.apps : []
        let n = 0
        for (let i = 0; i < list.length; i++)
            if (list[i].status === "partial") n++
        return n
    }
    readonly property color cardColor: {
        Kirigami.Theme.backgroundColor; Kirigami.Theme.textColor
        const b = Kirigami.Theme.backgroundColor, t = Kirigami.Theme.textColor
        return Qt.rgba(b.r + (t.r - b.r) * 0.06, b.g + (t.g - b.g) * 0.06,
                       b.b + (t.b - b.b) * 0.06, 1)
    }
    // donut inputs in fixed display order (notifier guard: snapshot)
    readonly property var donutValues: {
        MosaicStore.snapshot
        if (!summary || !summary.categories) return [0, 0, 0, 0]
        return MosaicStore.categories.map(function(k) { return Number(summary.categories[k] || 0) })
    }
    readonly property var donutTotal: donutValues.reduce(function(a, b) { return a + b }, 0)
    // search-filtered, sorted rows (notifier guards: snapshot + searchQuery)
    readonly property var listApps: {
        MosaicStore.snapshot; MosaicStore.searchQuery
        return ViewModel.appsFor(hasData ? MosaicStore.snapshot.apps : [], MosaicStore.searchQuery)
    }

    spacing: 0

    // never scanned: centered empty state with the primary action
    Rectangle {
        visible: !page.hasData
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "transparent"
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "No scan yet"
                color: Kirigami.Theme.textColor
                font.pixelSize: 14
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Mosaic maps what each application stores on this machine."
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 12
            }
            PC3.Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: "Scan applications"
                icon.name: "view-refresh"
                onClicked: MosaicStore.rescan()
            }
        }
    }

    RowLayout {
        visible: page.hasData
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16

        // ================= LEFT 384: hero / categories / meta ==============
        ColumnLayout {
            Layout.preferredWidth: 384
            Layout.fillHeight: true
            spacing: 12

            // ---- hero card (104) ----------------------------------------
            Rectangle {
                Layout.preferredHeight: 104
                Layout.fillWidth: true
                radius: Kirigami.Units.smallSpacing
                color: page.cardColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing + 2
                    spacing: 2

                    Text {
                        text: page.summary
                            ? MosaicStore.formatBytes(page.summary.bytes, page.limited) : "0 B"
                        color: page.heroAccent
                        font.pixelSize: 24
                    }
                    Text {
                        text: "MAPPED \u00b7 " + MosaicStore.mappedCount + " OF "
                              + page.appTotal + " APPS"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        font.letterSpacing: 0.4
                    }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing / 2 + 2
                        StatChip {
                            text: page.completeCount + " complete"
                            dotColor: "#3fd18b"
                        }
                        StatChip {
                            visible: page.partialCount > 0
                            text: page.partialCount + " partial"
                            dotColor: "#ffd23f"
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ---- categories card (320): donut + legend --------------------
            Rectangle {
                Layout.preferredHeight: 320
                Layout.fillWidth: true
                radius: Kirigami.Units.smallSpacing
                color: page.cardColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing + 2
                    spacing: Kirigami.Units.smallSpacing / 2

                    Text {
                        text: "CATEGORIES BY SIZE"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
                    }
                    Item { Layout.fillHeight: page.showDonut ? false : true }
                    DonutCanvas {
                        id: donut
                        visible: page.showDonut
                        Layout.alignment: Qt.AlignHCenter
                        values: page.donutValues
                        labels: MosaicStore.categories
                        colors: MosaicStore.categories.map(function(k) {
                            return MosaicStore.categoryColor(k)
                        })
                        totalText: MosaicStore.formatBytes(page.donutTotal, false)
                        onCategoryClicked: function(key) { MosaicStore.pushView("cat:" + key) }
                    }
                    Item { Layout.fillHeight: true }

                    // legend: 4 x 24 rows, the arc's clickable/accessible twin
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: MosaicStore.categories
                            delegate: Item {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                readonly property real catBytes: page.donutValues[index]
                                readonly property real catShare: page.donutTotal > 0
                                    ? Math.round(catBytes * 100 / page.donutTotal) : 0

                                Accessible.role: Accessible.Button
                                Accessible.name: MosaicStore.categoryLabel(modelData) + ", "
                                    + MosaicStore.formatBytes(catBytes, false) + ", "
                                    + catShare + " percent"

                                MouseArea {
                                    id: legendHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: donut.hoverKey = modelData
                                    onExited: donut.hoverKey = ""
                                    onClicked: MosaicStore.pushView("cat:" + modelData)
                                }
                                Rectangle {
                                    visible: legendHover.containsMouse
                                    anchors.fill: parent
                                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                        Kirigami.Theme.textColor.g,
                                        Kirigami.Theme.textColor.b, 0.06)
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                        Kirigami.Theme.textColor.g,
                                        Kirigami.Theme.textColor.b, 0.12)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 2
                                    anchors.rightMargin: 2
                                    spacing: Kirigami.Units.smallSpacing / 2 + 2
                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: MosaicStore.categoryColor(modelData)
                                    }
                                    Text {
                                        text: MosaicStore.categoryLabel(modelData)
                                        color: Kirigami.Theme.textColor
                                        font.pixelSize: 12
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 40
                                    }
                                    Text {
                                        text: MosaicStore.formatBytes(catBytes, false)
                                        color: Kirigami.Theme.textColor
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        text: catShare + "%"
                                        color: Kirigami.Theme.disabledTextColor
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 34
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- meta card (120): as-of · coverage · warnings -------------
            Rectangle {
                Layout.preferredHeight: 120
                Layout.fillWidth: true
                radius: Kirigami.Units.smallSpacing
                color: page.cardColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing + 2
                    spacing: Kirigami.Units.smallSpacing / 2

                    Text {
                        text: "AS OF " + (MosaicStore.asOfText !== "" ? MosaicStore.asOfText : "\u2014")
                              + " \u00b7 FULL SCAN"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        font.letterSpacing: 0.4
                    }
                    Text {
                        visible: page.limited
                        text: "Some paths were skipped; totals are lower bounds."
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: MosaicStore.scanState === "error"
                        text: "Last scan failed: " + MosaicStore.lastError
                        color: "#f4405c"
                        font.pixelSize: 11
                        wrapMode: Text.ElideRight
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    // coverage: measured paths / inventoried paths
                    Text {
                        visible: page.meta && page.meta.paths
                        text: page.meta && page.meta.paths
                            ? ("PATHS " + page.meta.paths.completed + " / " + page.meta.paths.total)
                            : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        font.letterSpacing: 0.4
                    }
                    Rectangle {
                        visible: page.meta && page.meta.paths && page.meta.paths.total > 0
                        Layout.preferredHeight: 3
                        Layout.fillWidth: true
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.12)
                        Rectangle {
                            height: 3
                            width: parent.width * (page.meta && page.meta.paths
                                ? page.meta.paths.completed / page.meta.paths.total : 0)
                            color: "#3fd18b"
                        }
                    }
                    // warnings disclosure (expands in place, <=3 lines)
                    PC3.ToolButton {
                        visible: page.meta && page.meta.warnings && page.meta.warnings.length > 0
                        text: "warnings (" + (page.meta && page.meta.warnings
                                              ? page.meta.warnings.length : 0) + ") \u25b8"
                        font.pixelSize: 11
                        onClicked: warnRepeater.visible = !warnRepeater.visible
                    }
                    Repeater {
                        id: warnRepeater
                        visible: false
                        model: page.meta && page.meta.warnings ? page.meta.warnings.slice(0, 3) : []
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: 11
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ================= RIGHT 528: search + app list ====================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: Kirigami.Units.smallSpacing

                PC3.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search applications\u2026"
                    onTextChanged: debounce.restart()
                    Keys.onEscapePressed: {
                        text = ""
                        focus = false
                    }
                }
                Timer {
                    id: debounce
                    interval: 120
                    repeat: false
                    onTriggered: MosaicStore.searchQuery = searchField.text
                }
                StatChip {
                    showDot: false
                    text: page.listApps.length + (MosaicStore.searchQuery !== ""
                        ? " / " + page.appTotal : "")
                }
                PC3.ToolButton {
                    visible: searchField.text !== ""
                    text: "\u2715"
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                    Accessible.name: "Clear search"
                }
            }

            // no-match empty state replaces the list in place
            Item {
                visible: page.listApps.length === 0 && page.hasData
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No applications match \u2018" + MosaicStore.searchQuery + "\u2019"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 12
                    }
                    PC3.Button {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Clear"
                        onClicked: searchField.text = ""
                    }
                }
            }

            ListView {
                id: appList
                visible: page.listApps.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: page.listApps
                PC3.ScrollBar.vertical: PC3.ScrollBar {
                    policy: PC3.ScrollBar.AsNeeded
                }
                delegate: AppRow {
                    required property var modelData
                    app: modelData
                    maxBytes: MosaicStore.maxAppBytes
                    onActivated: MosaicStore.pushView("app:" + modelData.id)
                }
            }
        }
    }
}
