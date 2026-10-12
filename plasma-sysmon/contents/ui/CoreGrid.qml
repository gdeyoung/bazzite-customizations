import QtQuick
import org.kde.kirigami as Kirigami

// CoreGrid — per-core utilization "rainbow": one colored bar per logical CPU
// (amber->violet hue walk), each bar showing its core's live %. Colors are
// fixed by core index so a core keeps its color across ticks. Legend strip
// under the grid maps color -> core number.
// Ported from gdeyoung/omarchy-sysmon; Style.* tokens swapped for Kirigami.
Item {
    id: root
    property var corePcts: []
    property int perRow: 12
    property real barH: 30
    property bool showLegend: true

    readonly property int n: corePcts ? corePcts.length : 0
    readonly property int rows: n > 0 ? Math.ceil(n / perRow) : 1
    readonly property real gap: 3

    function coreColor(i) {
        const h = 55 + (205 * i) / Math.max(1, n - 1)
        return Qt.hsla((h % 360) / 360, 0.72, 0.58, 1)
    }
    function coreGhost(i) {
        const h = 55 + (205 * i) / Math.max(1, n - 1)
        return Qt.hsla((h % 360) / 360, 0.72, 0.58, 0.16)
    }

    readonly property var chunks: {
        const out = []
        for (let r = 0; r < rows; r++) {
            const pcts = []
            for (let c = 0; c < perRow; c++) {
                const i = r * perRow + c
                if (i < n) pcts.push(corePcts[i] || 0)
            }
            out.push({ base: r * perRow, pcts: pcts })
        }
        return out
    }

    implicitHeight: rows * barH + (rows - 1) * gap + (showLegend ? 14 : 0)

    Column {
        id: grid
        width: parent.width
        spacing: root.gap

        Repeater {
            model: root.chunks

            Row {
                id: row
                required property var modelData
                width: parent.width
                spacing: root.gap

                Repeater {
                    model: row.modelData.pcts

                    Rectangle {
                        id: cell
                        required property int index
                        readonly property int coreIdx: row.modelData.base + index
                        readonly property real pct: modelData
                        width: (parent.width - (row.modelData.pcts.length - 1) * root.gap) / row.modelData.pcts.length
                        height: root.barH
                        radius: 2
                        color: root.coreGhost(coreIdx)

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: parent.width
                            height: Math.max(3, parent.height * Math.min(1, pct / 100))
                            radius: 2
                            color: root.coreColor(coreIdx)
                        }
                    }
                }
            }
        }
    }

    Item {
        visible: root.showLegend && root.n > 1
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16

        Row {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            spacing: 0
            Repeater {
                model: root.n
                Rectangle {
                    required property int index
                    width: parent.width / root.n
                    height: 3
                    radius: 1
                    color: root.coreColor(index)
                }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 5
            text: "1"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 5
            text: root.n + " cores"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
    }
}
