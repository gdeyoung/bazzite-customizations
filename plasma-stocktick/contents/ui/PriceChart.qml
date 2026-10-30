/*
 * PriceChart — detail-view line chart (Canvas).
 * Spec D: 2px line colored by SPAN direction (first→last), 0.18→0 gradient
 * fill, dashed baseline at span start close, 3 faint gridlines with right-edge
 * price labels, 3–5 date ticks bottom. Crosshair deferred to pass 2.
 * Pass in: points (closes), times (epoch s), base (baseline value).
 */
import QtQuick

Canvas {
    id: chart

    property var points: []
    property var times: []           // epoch seconds, aligned with points
    property real base: 0            // baseline value (span start / prev close)
    property color lineColor: "#3fd18b"
    // Logical-coordinate drawing (omastocks pattern): the Canvas context is
    // already scaled by the session's device ratio — multiplying paint
    // coordinates by Screen.devicePixelRatio on top of that DOUBLE-scales
    // whenever the two diverge (QT_SCALE_FACTOR, or kscreen 1.05 with dpr
    // reporting 2): labels/gridlines land off-canvas, the line shifts low,
    // right/bottom clip. No dpr math anywhere in the paint path.
    readonly property real labelW: 56
    readonly property real tickH: 18

    visible: points !== null && points.length >= 5
    antialiasing: true
    // canvasSize managed imperatively via resync() — a binding alone does
    // not reliably re-allocate the backing store when the item is laid out
    // after creation (popup opens → item resizes → stale store clips
    // everything furthest from the origin: right-edge price labels and
    // bottom date ticks vanish while the top-left of the chart paints).
    // Canvas size = LOGICAL item size; Qt scales the store for the device.
    function resync() {
        var cw = Math.max(1, Math.floor(width))
        var ch = Math.max(1, Math.floor(height))
        canvasSize = Qt.size(cw, ch)
        // (imperative canvasSize assignment re-allocates the store + repaints)
        requestPaint()
    }
    onWidthChanged: resync()
    onHeightChanged: resync()
    Component.onCompleted: resync()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!visible || width < 40 || height < 40) return
        var pts = points, tms = times
        var n = pts.length
        if (n < 5 || tms.length < n) return

        var min = Infinity, max = -Infinity, first = null, last = null
        for (var i = 0; i < n; i++) {
            var v = pts[i]
            if (v === null || v === undefined) continue
            if (first === null) first = v
            last = v
            if (v < min) min = v
            if (v > max) max = v
        }
        if (!isFinite(min) || !isFinite(max)) return
        if (base > 0) { if (base < min) min = base; if (base > max) max = base }
        if (max === min) { max = min + 1 }

        // Headroom (omastocks pattern): pad the y-range so the line and the
        // dashed baseline never touch the plot edges — troughs read as cut
        // off otherwise. 12% of span (min 0.05% of price, min 0.01).
        var head = Math.max((max - min) * 0.12, Math.abs(max) * 0.0005, 0.01)
        min -= head
        max += head

        var w = width, h = height
        var padL = 4, padR = labelW, padT = 10, padB = 24
        var iw = w - padL - padR, ih = h - padT - padB
        var sx = iw / (n - 1)
        var sy = ih / (max - min)
        function X(i) { return padL + i * sx }
        function Y(v) { return padT + ih - (v - min) * sy }

        // gridlines: max / mid / min, textColor 12%; right-edge labels
        var gridSteps = [max, (max + min) / 2, min]
        for (var g = 0; g < 3; g++) {
            var gy = Y(gridSteps[g])
            ctx.beginPath()
            ctx.moveTo(padL, gy)
            ctx.lineTo(padL + iw, gy)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
            ctx.lineWidth = 1
            ctx.stroke()
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.45)
            ctx.font = "10px sans-serif"
            ctx.textAlign = "left"
            ctx.textBaseline = "middle"
            ctx.fillText(fmt(gridSteps[g]), padL + iw + 4, gy)
        }

        // dashed baseline at span start
        if (base > 0) {
            var by = Y(base)
            ctx.beginPath()
            ctx.setLineDash([4, 4])
            ctx.moveTo(padL, by)
            ctx.lineTo(padL + iw, by)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.30)
            ctx.lineWidth = 1
            ctx.stroke()
            ctx.setLineDash([])
        }

        // gradient fill under line
        var grad = ctx.createLinearGradient(0, padT, 0, padT + ih)
        grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18))
        grad.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0))
        ctx.beginPath()
        ctx.moveTo(X(0), Y(pts[0]))
        for (var j = 1; j < n; j++) ctx.lineTo(X(j), Y(pts[j]))
        ctx.lineTo(X(n - 1), padT + ih)
        ctx.lineTo(X(0), padT + ih)
        ctx.closePath()
        ctx.fillStyle = grad
        ctx.fill()

        // line
        ctx.beginPath()
        ctx.moveTo(X(0), Y(pts[0]))
        for (var k = 1; k < n; k++) ctx.lineTo(X(k), Y(pts[k]))
        ctx.strokeStyle = lineColor
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.stroke()

        // 3 date ticks bottom
        var intraDay = (tms[n - 1] - tms[0]) < 86400 * 2
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.40)
        ctx.font = "10px sans-serif"
        ctx.textBaseline = "top"
        var slots = [0, Math.floor((n - 1) / 2), n - 1]
        var aligns = ["left", "center", "right"]
        for (var s = 0; s < 3; s++) {
            var d = new Date(tms[slots[s]] * 1000)
            var label = intraDay
                ? Qt.formatDateTime(d, "h:mm AP")
                : Qt.formatDateTime(d, "MMM d")
            ctx.textAlign = aligns[s]
            var tx = X(slots[s])
            if (aligns[s] === "left") tx = padL
            if (aligns[s] === "right") tx = padL + iw
            ctx.fillText(label, tx, padT + ih + 3)
        }
    }

    function fmt(v) {
        if (v >= 1000) return v.toFixed(0)
        if (v >= 100) return v.toFixed(1)
        return v.toFixed(2)
    }

    onPointsChanged: requestPaint()
}
