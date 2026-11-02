import QtQuick
import org.kde.kirigami as Kirigami
import "lib/DonutGeometry.js" as DonutGeometry

// Category donut, 164x164 (spec §D). Fixed sizes, logical coordinates ONLY
// (DPR rule), annular sector paths via the vendored DonutGeometry (2-degree
// separators come from its gap logic). Center label is a Text overlay —
// never canvas text. Hover/tap an arc OR its legend row (page writes
// hoverKey) swaps the center readout; click drills into the category.
Item {
    id: donut

    property var values: []           // bytes per category, display order
    property var labels: []           // category keys, same order
    property var colors: []
    property string totalText: "0 B"
    property string totalLabel: "MAPPED"
    property string emptyLabel: "not scanned"
    property string hoverKey: ""      // shared with legend rows (page-side)

    signal categoryClicked(string key)

    width: 164
    height: 164

    readonly property var built: DonutGeometry.build(values)
    readonly property real ringMid: 61
    readonly property real ringStroke: 26
    readonly property bool anyDrawable: {
        const segs = built.segments
        for (let i = 0; i < segs.length; i++)
            if (segs[i].drawable) return true
        return false
    }
    readonly property int hoverIndex: {
        if (hoverKey === "") return -1
        for (let i = 0; i < labels.length; i++)
            if (labels[i] === hoverKey) return i
        return -1
    }
    function hoverPercent(i) {
        const total = values.length ? values.reduce(function(a, b) { return a + Number(b || 0) }, 0) : 0
        return total > 0 ? Math.round(Number(values[i] || 0) * 100 / total) : 0
    }

    onBuiltChanged: canvas.requestPaint()
    onColorsChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        // imperative canvasSize resync (fleet canvas rule); logical px only
        Component.onCompleted: {
            canvasSize = Qt.size(Math.floor(donut.width), Math.floor(donut.height))
            requestPaint()
        }
        onWidthChanged: {
            canvasSize = Qt.size(Math.floor(donut.width), Math.floor(donut.height))
            requestPaint()
        }
        onHeightChanged: {
            canvasSize = Qt.size(Math.floor(donut.width), Math.floor(donut.height))
            requestPaint()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, donut.width, donut.height)
            const cx = 82, cy = 82, rO = 74, rI = 48
            // full-ring track at 12% text alpha
            ctx.fillStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                    Kirigami.Theme.textColor.b, 0.12)
            annulus(ctx, cx, cy, rO, rI, -Math.PI / 2, Math.PI * 1.5)
            ctx.fill()
            // sectors (fixed category order; gaps baked into segment angles)
            const segs = donut.built.segments
            for (let i = 0; i < segs.length; i++) {
                if (!segs[i].drawable) continue
                ctx.fillStyle = donut.colors[i]
                annulus(ctx, cx, cy, rO, rI, segs[i].start, segs[i].end)
                ctx.fill()
            }
        }
        function annulus(ctx, cx, cy, rO, rI, a0, a1) {
            ctx.beginPath()
            ctx.arc(cx, cy, rO, a0, a1, false)
            ctx.arc(cx, cy, rI, a1, a0, true)
            ctx.closePath()
        }
    }

    MouseArea {
        id: probe
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function(mouse) {
            const segs = donut.built.segments
            for (let i = 0; i < segs.length; i++) {
                if (DonutGeometry.contains(segs[i], mouse.x, mouse.y, 82, 82,
                                           donut.ringMid, donut.ringStroke)) {
                    donut.hoverKey = donut.labels[i]
                    return
                }
            }
            donut.hoverKey = ""
        }
        onExited: donut.hoverKey = ""
        onClicked: function(mouse) {
            const segs = donut.built.segments
            for (let i = 0; i < segs.length; i++) {
                if (DonutGeometry.contains(segs[i], mouse.x, mouse.y, 82, 82,
                                           donut.ringMid, donut.ringStroke)) {
                    donut.categoryClicked(donut.labels[i])
                    return
                }
            }
        }
    }

    // center overlay (Text outside the canvas — fleet rule)
    Column {
        anchors.centerIn: parent
        spacing: 1
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !donut.anyDrawable
            text: donut.emptyLabel
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: donut.anyDrawable && donut.hoverIndex < 0
            text: donut.totalText
            color: Kirigami.Theme.textColor
            font.pixelSize: 13
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: donut.anyDrawable && donut.hoverIndex < 0
            text: donut.totalLabel
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: donut.hoverIndex >= 0
            text: donut.hoverIndex >= 0
                ? MosaicStore.categoryLabel(donut.labels[donut.hoverIndex]) : ""
            color: donut.hoverIndex >= 0 ? donut.colors[donut.hoverIndex]
                                         : Kirigami.Theme.textColor
            font.pixelSize: 13
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: donut.hoverIndex >= 0
            text: donut.hoverIndex >= 0
                ? MosaicStore.formatBytes(Number(donut.values[donut.hoverIndex] || 0), false)
                  + " \u00b7 " + donut.hoverPercent(donut.hoverIndex) + "%" : ""
            color: Kirigami.Theme.textColor
            font.pixelSize: 12
        }
    }
}
