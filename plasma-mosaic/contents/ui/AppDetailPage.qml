import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "lib/ViewModel.js" as ViewModel

// App detail (spec §E): hero with per-app lower bound + actions, then
// evidence-forward path cards. Known-confidence paths first; possible/
// shared under a "MEASURED, EXCLUDED FROM TOTALS" divider at 60% opacity.
ColumnLayout {
    id: page

    readonly property var app: {
        MosaicStore.viewStack; MosaicStore.snapshot     // notifier guards
        return MosaicStore.findApp(MosaicStore.currentArg)
    }
    property string busyNote: ""
    readonly property bool deepRunning: app && MosaicStore.deepBusy[app.id] === true
    // open/copy target: the app's largest known path
    readonly property var primaryPath: {
        if (!app || !app.paths) return null
        let best = null
        for (let i = 0; i < app.paths.length; i++) {
            const p = app.paths[i]
            if (p.confidence !== "known") continue
            if (!best || Number(p.bytes || 0) > Number(best.bytes || 0)) best = p
        }
        return best ? best.path : (app.paths.length > 0 ? app.paths[0].path : "")
    }
    // rows model: known (bytes desc) + divider + excluded (bytes desc)
    readonly property var displayPaths: {
        MosaicStore.snapshot
        if (!app || !app.paths) return []
        const known = [], excluded = []
        for (let i = 0; i < app.paths.length; i++) {
            const p = app.paths[i]
            if (p.confidence === "known") known.push(p)
            else if (p.confidence === "possible" || p.confidence === "shared") excluded.push(p)
        }
        const byBytes = function(a, b) { return Number(b.bytes || 0) - Number(a.bytes || 0) }
        known.sort(byBytes)
        excluded.sort(byBytes)
        const rows = known.map(function(p) { return { kind: "path", entry: p } })
        if (excluded.length > 0) {
            rows.push({ kind: "divider" })
            for (let j = 0; j < excluded.length; j++)
                rows.push({ kind: "path", entry: excluded[j] })
        }
        return rows
    }

    spacing: 8

    // ---- hero (88) ---------------------------------------------------------
    Rectangle {
        visible: page.app !== null && page.app !== undefined
        Layout.fillWidth: true
        Layout.preferredHeight: 88
        radius: Kirigami.Units.smallSpacing
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.06)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing + 2
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                source: page.app && page.app.icon ? page.app.icon : "application-x-executable"
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 160
                spacing: 2
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing / 2 + 2
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 60
                        text: page.app ? page.app.name : ""
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    StatChip {
                        visible: page.app && page.app.status === "partial"
                        text: "partial"
                        dotColor: "#ffd23f"
                    }
                }
                // category chips: dot + short name + bytes, fixed order
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing / 2 + 2
                    Repeater {
                        model: {
                            const out = []
                            if (page.app && page.app.categories) {
                                const cats = MosaicStore.categories
                                for (let i = 0; i < cats.length; i++) {
                                    const b = Number(page.app.categories[cats[i]] || 0)
                                    if (b > 0)
                                        out.push({ key: cats[i],
                                                   text: MosaicStore.categoryLabel(cats[i])
                                                         + " " + MosaicStore.formatBytes(b, false) })
                                }
                            }
                            return out
                        }
                        delegate: StatChip {
                            required property var modelData
                            text: modelData.text
                            dotColor: MosaicStore.categoryColor(modelData.key)
                        }
                    }
                }
            }
            Text {
                text: page.app ? MosaicStore.appSizeText(page.app) : ""
                color: Kirigami.Theme.textColor
                font.pixelSize: 24
            }

            // actions, one target apart, right-aligned
            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Button {
                        text: page.deepRunning ? "Measuring\u2026" : "Deeper scan"
                        enabled: !page.deepRunning
                        icon.name: page.deepRunning ? "" : "zoom-in"
                        onClicked: {
                            if (!page.app) return
                            const result = MosaicStore.deepScan(page.app.id)
                            if (result.busy) page.flashBusyNote()
                        }
                    }
                    PC3.Button {
                        text: "Open folder"
                        icon.name: "folder-open"
                        enabled: page.primaryPath ? true : false
                        onClicked: MosaicStore.openFolder(page.primaryPath)
                    }
                    PC3.ToolButton {
                        icon.name: "edit-copy"
                        enabled: page.primaryPath ? true : false
                        onClicked: MosaicStore.copyToClipboard(page.primaryPath)
                        Accessible.name: "Copy path"
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    visible: page.busyNote !== ""
                    text: page.busyNote
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: 260
                    visible: MosaicStore.openError !== "" && page.openErrorFresh
                    text: MosaicStore.openError
                    color: "#f4405c"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }
    }

    property bool openErrorFresh: false
    Connections {
        target: MosaicStore
        function onOpenErrorAtChanged() {
            if (MosaicStore.openErrorAt > 0) {
                page.openErrorFresh = true
                openErrorFade.restart()
            }
        }
    }
    Timer { id: openErrorFade; interval: 5000; onTriggered: page.openErrorFresh = false }

    function flashBusyNote() {
        busyNote = "Scan already running"
        busyNoteFade.restart()
    }
    Timer { id: busyNoteFade; interval: 3000; onTriggered: page.busyNote = "" }

    // ---- path cards --------------------------------------------------------
    Text {
        visible: page.app === null || page.app === undefined
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "Application not in the current snapshot."
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: 12
    }

    ListView {
        visible: page.displayPaths.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.displayPaths
        spacing: 0
        PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }

        delegate: Loader {
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            sourceComponent: modelData.kind === "divider" ? dividerComp : cardComp
            onLoaded: {
                if (modelData.kind !== "divider") {
                    item.entry = Qt.binding(function() { return modelData.entry })
                    item.expanded = Qt.binding(function() {
                        return MosaicStore.expandedPath === modelData.entry.path
                    })
                }
            }
        }
        Component {
            id: cardComp
            PathCard {
                onToggleRequested: {
                    MosaicStore.expandedPath = (MosaicStore.expandedPath === entry.path) ? "" : entry.path
                }
            }
        }
        Component {
            id: dividerComp
            Item {
                height: 28
                implicitHeight: 28
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Kirigami.Theme.disabledTextColor
                    opacity: 0.4
                }
                Text {
                    anchors.centerIn: parent
                    text: "MEASURED, EXCLUDED FROM TOTALS"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                    font.letterSpacing: 0.4
                }
            }
        }
    }

    // keep the accordion binding correct when entries swap after a deep scan
    Connections {
        target: MosaicStore
        function onSnapshotChanged() {
            if (MosaicStore.expandedPath === "") return
            let found = false
            const rows = page.displayPaths
            for (let i = 0; i < rows.length; i++)
                if (rows[i].kind === "path" && rows[i].entry.path === MosaicStore.expandedPath) found = true
            if (!found) MosaicStore.expandedPath = ""
        }
    }
}
