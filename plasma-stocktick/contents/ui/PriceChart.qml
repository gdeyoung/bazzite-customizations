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
    // guarded: NaN dpr silently kills every paint call
    readonly property real dpr: {
        var v = Screen.devicePixelRatio
        return (v !== undefined && v !== null && isFinite(v) && v > 0) ? v : 1
    }

    readonly property real labelW: 56 * dpr
    readonly property real tickH: 18 * dpr

    visible: points !== null && points.length >= 5
    antialiasing: true
    // hidpi: match canvas coordinate space to device pixels (see Sparkline)
    canvasSize: Qt.size(Math.max(1, width * dpr), Math.max(1, height * dpr))

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

        var w = width * dpr, h = height * dpr
        var padL = 4 * dpr, padR = labelW, padT = 6 * dpr, padB = tickH
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
            ctx.font = (10 * dpr) + "px sans-serif"
            ctx.textAlign = "left"
            ctx.textBaseline = "middle"
            ctx.fillText(fmt(gridSteps[g]), padL + iw + 4 * dpr, gy)
        }

        // dashed baseline at span start
        if (base > 0) {
            var by = Y(base)
            ctx.beginPath()
            ctx.setLineDash([4 * dpr, 4 * dpr])
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
        ctx.lineWidth = 2 * dpr
        ctx.lineJoin = "round"
        ctx.stroke()

        // 3 date ticks bottom
        var intraDay = (tms[n - 1] - tms[0]) < 86400 * 2
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.40)
        ctx.font = (10 * dpr) + "px sans-serif"
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
            ctx.fillText(label, tx, padT + ih + 3 * dpr)
        }
    }

    function fmt(v) {
        if (v >= 1000) return v.toFixed(0)
        if (v >= 100) return v.toFixed(1)
        return v.toFixed(2)
    }

    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
