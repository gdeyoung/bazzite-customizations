/*
 * Sparkline — shared Canvas polyline, no axes.
 * Spec G/A: 1.5px line in day-direction color, 0.15-alpha fill to baseline,
 * drawn only when >= 5 points (width collapses otherwise — never a blank gap).
 * Hydration: set `points`; repaints only on data arrival.
 */
import QtQuick

Canvas {
    id: spark

    property var points: []          // array of numbers (closes), oldest → newest
    property color lineColor: "#3fd18b"
    property real lineWidth: 1.5
    // guarded: NaN dpr silently kills every paint call
    readonly property real dpr: {
        var v = Screen.devicePixelRatio
        return (v !== undefined && v !== null && isFinite(v) && v > 0) ? v : 1
    }

    visible: points !== null && points.length >= 5
    antialiasing: true
    // hidpi + backing-store: same resync pattern as PriceChart — a
    // canvasSize binding alone doesn't reliably re-allocate the store
    // on post-creation resize (panel thickness change, theme reload).
    function resync() {
        var cw = Math.max(1, Math.floor(width * dpr))
        var ch = Math.max(1, Math.floor(height * dpr))
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
        if (!visible || width < 4 || height < 4) return
        var pts = points
        var n = pts.length
        if (n < 5) return

        var min = Infinity, max = -Infinity
        for (var i = 0; i < n; i++) {
            if (pts[i] === null || pts[i] === undefined) continue
            if (pts[i] < min) min = pts[i]
            if (pts[i] > max) max = pts[i]
        }
        if (!isFinite(min) || !isFinite(max) || max === min) return

        var w = width * dpr, h = height * dpr, pad = 2 * dpr
        var sx = (w - pad * 2) / (n - 1)
        var sy = (h - pad * 2) / (max - min)
        function X(i) { return pad + i * sx }
        function Y(v) { return h - pad - (v - min) * sy }

        // fill under line, 0.15 alpha to baseline
        ctx.beginPath()
        ctx.moveTo(X(0), Y(pts[0]))
        for (var j = 1; j < n; j++) ctx.lineTo(X(j), Y(pts[j]))
        ctx.lineTo(X(n - 1), h)
        ctx.lineTo(X(0), h)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.15)
        ctx.fill()

        // polyline
        ctx.beginPath()
        ctx.moveTo(X(0), Y(pts[0]))
        for (var k = 1; k < n; k++) ctx.lineTo(X(k), Y(pts[k]))
        ctx.strokeStyle = lineColor
        ctx.lineWidth = lineWidth * dpr
        ctx.lineJoin = "round"
        ctx.stroke()
    }

    onPointsChanged: requestPaint()
}
