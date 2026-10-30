import QtQuick
import org.kde.kirigami as Kirigami

// CoreGrid v2 — per-core utilization grid, amber->violet hue walk (fixed per
// core index), fill bottom-up, AND the core's integer % drawn inside the cell
// at 10px tnum when cells are >=26px wide (the v0.6 3px-cell grid was
// unreadable; numbers below 26px would render as noise, so they drop out).
// Legend strip under the grid maps color -> core number.
Item {
    id: root
    property var corePcts: []
    property int perRow: 16
    property real cellH: 56
    property bool showLegend: true

    readonly property int n: corePcts ? corePcts.length : 0
    readonly property int rows: n > 0 ? Math.ceil(n / perRow) : 1
    readonly property real gap: 3
    readonly property int perRowActual: Math.min(perRow, Math.max(1, n))
    readonly property real cellW: Math.min(30, (width - (perRowActual - 1) * gap) / perRowActual)
    readonly property bool numbered: cellW >= 26

    function coreColor(i, a) {
        const h = 55 + (205 * i) / Math.max(1, n - 1)
        return Qt.hsla((h % 360) / 360, 0.72, 0.58, a === undefined ? 1 : a)
    }

    implicitHeight: rows * cellH + (rows - 1) * gap + (showLegend && n > 1 ? 16 : 0)

    Column {
        width: parent.width
        spacing: root.gap

        Repeater {
            model: root.rows

            Row {
                id: row
                required property int index
                width: parent.width
                spacing: root.gap

                Repeater {
                    model: Math.min(root.perRow, root.n - row.index * root.perRow)

                    Rectangle {
                        id: cell
                        required property int index
                        readonly property int coreIdx: row.index * root.perRow + index
                        readonly property real pct: root.corePcts ? (root.corePcts[coreIdx] || 0) : 0
                        width: root.cellW
                        height: root.cellH
                        radius: 3
                        color: root.coreColor(coreIdx, 0.14)

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(4, parent.height * Math.min(1, cell.pct / 100))
                            radius: 3
                            color: root.coreColor(cell.coreIdx, 0.62)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.numbered
                            text: Math.round(cell.pct)
                            color: Kirigami.Theme.textColor
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
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
                    color: root.coreColor(index, 1)
                }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 5
            text: "1"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 5
            text: root.n + " CORES"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
            font.features: ({ "tnum": 1 })
        }
    }
}
