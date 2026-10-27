import QtQuick
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// One watchlist row: sym | price | colored change | mini sparkline.
// Click selects the symbol for the hero. Lives in its own file so main.qml
// holds at most one handler per signal name (duplicate handlers block the
// whole applet on Plasma 6 — same reason weatherx splits out TabChip etc).
MouseArea {
    id: row
    required property var panel       // the PlasmoidItem (colors, selection)
    required property var modelData   // symbol string
    readonly property var rq: panel.quotes[modelData]

    width: parent ? parent.width : 200
    height: Kirigami.Units.gridUnit * 1.7
    hoverEnabled: true
    onClicked: panel.selected = modelData

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing
        color: row.containsMouse
               ? Qt.rgba(Kirigami.Theme.textColor.r,
                         Kirigami.Theme.textColor.g,
                         Kirigami.Theme.textColor.b, 0.08)
               : "transparent"
    }
    Row {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: (row.modelData || "").replace(".US", "")
            width: Kirigami.Units.gridUnit * 4
            color: row.modelData === panel.selected
                   ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            font.bold: row.modelData === panel.selected
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: row.rq ? Model.fmtPrice(row.rq.close) : ""
            width: Kirigami.Units.gridUnit * 4
            horizontalAlignment: Text.AlignRight
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: row.rq ? Model.fmtChange(row.rq.close, row.rq.prevClose,
                                           row.rq.deltaPct) : ""
            width: Kirigami.Units.gridUnit * 5.5
            horizontalAlignment: Text.AlignRight
            color: row.rq && row.rq.deltaPct >= 0 ? panel.cPos : panel.cNeg
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: Kirigami.Units.gridUnit * 0.7; height: 1 }
        Canvas {
            id: rowSpark
            width: Kirigami.Units.gridUnit * 6
            height: parent.height - Kirigami.Units.smallSpacing
            visible: !!(row.rq && row.rq.spark && row.rq.spark.length > 1)
            anchors.verticalCenter: parent.verticalCenter
            onPaint: {
                var pts = row.rq ? row.rq.spark : []
                if (pts.length < 2) return
                var ctx = getContext("2d")
                ctx.reset()
                var min = Math.min.apply(null, pts), max = Math.max.apply(null, pts)
                if (max === min) max = min + 1
                var up = pts[pts.length - 1] >= pts[0]
                ctx.strokeStyle = up ? panel.cPos : panel.cNeg
                ctx.lineWidth = 1.5
                ctx.beginPath()
                for (var i = 0; i < pts.length; i++) {
                    var x = i / (pts.length - 1) * width
                    var y = height - 2 - (pts[i] - min) / (max - min) * (height - 4)
                    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                }
                ctx.stroke()
            }
            Connections {
                target: row
                function onRqChanged() { rowSpark.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }
}
