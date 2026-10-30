import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".."
import ".." as U

// ProcsTab — v0.7 real process manager.
// Root fix is the probe (full list <=600 rows, not top-14-by-CPU); this tab
// adds: search/filter, USER/S/RSS columns, sort on every column with a
// visible arrow, ListView scroll that survives 2s model resets (contentY
// restore over fixed 24px rows), totals over the filtered set, and the
// existing kill+confirm mechanic (now with EPERM surfacing — KillBar).
Item {
    id: tab
    required property var sysmon

    readonly property var sortCol: ({ name: 2, user: 1, pid: 0, cpu: 3, mem: 4, rss: 5 })
    readonly property int fixedW: 472

    property int selectedPid: 0

    // filter is routed through sysmon (main.qml) so the harness and future
    // external triggers can drive it; state also survives tab switches.
    readonly property string filter: sysmon.procFilter

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color cBlue: "#7aa2f7"
    readonly property color cGreen: "#3fd18b"
    readonly property color cAmber: "#e5c07b"
    readonly property color cRed: "#f4405c"

    // Column contract shared by header + ProcRow delegate so they cannot
    // drift. Fixed cols sum 472; NAME gets the remaining ~456 of 928.
    readonly property var procCols: [
        { key: "name",  label: "NAME",  w: -1 },
        { key: "user",  label: "USER",  w: 84 },
        { key: "state", label: "S",     w: 24 },
        { key: "pid",   label: "PID",   w: 60 },
        { key: "cpu",   label: "CPU%",  w: 60 },
        { key: "mem",   label: "MEM%",  w: 60 },
        { key: "rss",   label: "RSS",   w: 68 },
        { key: "hist",  label: "1m",    w: 88 },
        { key: "kill",  label: "",      w: 28 }
    ]
    readonly property var view: {
        const src = sysmon.procs
        const q = filter.trim().toLowerCase()
        let arr = q === "" ? src.slice() : src.filter(r =>
            String(r[2]).toLowerCase().indexOf(q) >= 0 ||
            String(r[1]).toLowerCase().indexOf(q) >= 0 ||
            String(r[0]).indexOf(q) >= 0)
        const ci = sortCol[sysmon.procSort] === undefined ? 3 : sortCol[sysmon.procSort]
        const text = sysmon.procSort === "name" || sysmon.procSort === "user"
        arr.sort((a, b) => {
            const d = text ? String(a[ci]).localeCompare(String(b[ci]))
                           : Number(b[ci]) - Number(a[ci])
            return d !== 0 ? d : Number(a[0]) - Number(b[0])   // tiebreak pid asc
        })
        return arr
    }

    readonly property var totals: {
        let cpu = 0, mem = 0, rss = 0
        for (let i = 0; i < view.length; i++) {
            cpu += Number(view[i][3]) || 0
            mem += Number(view[i][4]) || 0
            rss += Number(view[i][5]) || 0
        }
        return { cpu: cpu, mem: mem, rss: rss }
    }

    function cpuColor(v) { return v >= 60 ? cRed : (v >= 15 ? cAmber : fg) }
    function stateColor(s) { return s === "D" ? cAmber : (s === "Z" ? cRed : muted) }
    function headerArrow(key) {
        if (sysmon.procSort !== key) return ""
        return (key === "name" || key === "user") ? " \u25B4" : " \u25BE"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- toolbar 36 ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 8

            Row {
                spacing: 2
                PC3.TextField {
                    id: search
                    width: 240
                    placeholderText: i18n("Filter \u00B7 name, user, pid")
                    font.pixelSize: 11
                    onTextEdited: sysmon.procFilter = text
                    Keys.onEscapePressed: { text = ""; sysmon.procFilter = "" }
                }
                Item {
                    width: 22
                    height: search.height
                    visible: sysmon.procFilter !== ""
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        color: tab.muted
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { search.text = ""; sysmon.procFilter = ""; search.forceActiveFocus() }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: tab.view.length === sysmon.procs.length
                      ? "showing " + tab.view.length
                      : "showing " + tab.view.length + " / " + sysmon.procs.length
                color: tab.muted
                font.pixelSize: 10
                font.features: ({ "tnum": 1 })
            }
        }

        // ---- sticky column header 26 ----------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 0
            Repeater {
                model: tab.procCols
                Item {
                    id: hcell
                    required property var modelData
                    Layout.fillWidth: hcell.modelData.w < 0
                    Layout.preferredWidth: hcell.modelData.w > 0 ? hcell.modelData.w : 0
                    Layout.preferredHeight: 26

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: hcell.modelData.key === "name" ? 8 : 0
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: {
                            const k = hcell.modelData.key
                            return (k === "name" || k === "user") ? Text.AlignLeft
                                 : (k === "state" || k === "kill") ? Text.AlignHCenter
                                 : Text.AlignRight
                        }
                        text: hcell.modelData.label + (tab.sortCol[hcell.modelData.key] !== undefined ? tab.headerArrow(hcell.modelData.key) : "")
                        color: sysmon.procSort === hcell.modelData.key ? tab.fg : tab.muted
                        font.bold: sysmon.procSort === hcell.modelData.key
                        font.pixelSize: 10
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: tab.sortCol[hcell.modelData.key] !== undefined
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: sysmon.procSort = hcell.modelData.key
                    }
                }
            }
        }
        U.Hair { Layout.fillWidth: true }

        // ---- list (442 or 414 with the confirm bar visible) ------------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.StopAtBounds
            PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }

            Component.onCompleted: model = tab.view
            Connections {
                target: tab
                function onViewChanged() {
                    // Array reset + contentY restore: fixed 24px rows make the
                    // restore exact, so scrolling survives the 2s model ticks.
                    const y = list.contentY
                    list.model = tab.view
                    list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height))
                }
            }

            // skeleton while the first fetch is in flight
            Column {
                parent: list
                anchors.fill: parent
                anchors.margins: 8
                visible: sysmon.procs.length === 0
                spacing: 14
                Repeater {
                    model: 16
                    U.SkeletonRow { w: 240 + (index % 5) * 120 }
                }
            }
            // empty-filter state
            Item {
                parent: list
                anchors.fill: parent
                visible: sysmon.procs.length > 0 && tab.view.length === 0
                Text {
                    anchors.centerIn: parent
                    text: i18n("no matches for \u201C" + sysmon.procFilter + "\u201D")
                    color: tab.muted
                    font.pixelSize: 11
                }
            }

            delegate: ProcRow { owner: tab }
        }

        // ---- confirm bar (fixed 28 — appearance never reflows the frame) ----
        KillBar {
            Layout.fillWidth: true
            sysmon: tab.sysmon
        }

        // ---- totals 28 --------------------------------------------------------
        U.Hair { Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Item { Layout.fillWidth: true }
            Text {
                text: "\u03A3 CPU " + totals.cpu.toFixed(1) + "%"
                    + " \u00B7 \u03A3 MEM " + totals.mem.toFixed(1) + "%"
                    + " \u00B7 \u03A3 RSS " + sysmon.fmtRss(totals.rss)
                    + " \u00B7 " + ((sysmon.procSort === "name" || sysmon.procSort === "user") ? "a\u2013z" : "high\u2013low")
                color: tab.muted
                font.pixelSize: 10
                font.letterSpacing: 0.3
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
