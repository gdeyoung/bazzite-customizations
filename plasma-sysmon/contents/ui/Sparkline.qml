import QtQuick

// Sparkline — one Canvas, paints {t, v} series scaled to fit.
// t maps to x proportionally (mixed sample cadences stay honest); v maps to
// y over [lo, hi] when fixed bounds are given, else the series' own min/max.
// Fill is a vertical gradient; the newest sample gets a glow dot.
// seriesB/strokeB paint a second overlaid line (net up over net down).
// Ported verbatim from gdeyoung/omarchy-sysmon (Quickshell → Plasma).
Canvas {
    id: cv
    property var series: []          // [{t, v}, ...] oldest -> newest
    property var seriesB: null       // optional second series, same window
    property real lo: 0
    property real hi: 100
    property bool autoScale: false   // true: use series min/max (padding 5%)
    property color stroke: "#7aa2f7"
    property color strokeB: "#bb9af7"
    property color fill: "transparent"
    property real lineWidth: 1.5
    property bool glow: true

    onSeriesChanged: requestPaint()
    onSeriesBChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const W = width, H = height
        if (!series || series.length < 2) return

        let mn = autoScale ? Infinity : lo
        let mx = autoScale ? -Infinity : hi
        if (autoScale) {
            for (let i = 0; i < series.length; i++) {
                const v = series[i].v
                if (v < mn) mn = v
                if (v > mx) mx = v
            }
            if (seriesB) {
                for (let i = 0; i < seriesB.length; i++) {
                    const v = seriesB[i].v
                    if (v < mn) mn = v
                    if (v > mx) mx = v
                }
            }
            if (!isFinite(mn) || !isFinite(mx)) return
            if (mx - mn < 1e-9) { mn -= 1; mx += 1 }
            const pad = (mx - mn) * 0.05
            mn -= pad; mx += pad
        }
        const t0 = series[0].t
        const t1 = series[series.length - 1].t
        const span = Math.max(1, t1 - t0)
        const x = (p) => ((p.t - t0) / span) * (W - 4) + 2
        const y = (p) => H - 2 - ((p.v - mn) / (mx - mn)) * (H - 6)

        if (fill.toString() !== "transparent") {
            const grad = ctx.createLinearGradient(0, 0, 0, H)
            grad.addColorStop(0, Qt.rgba(fill.r, fill.g, fill.b, 0.32))
            grad.addColorStop(1, Qt.rgba(fill.r, fill.g, fill.b, 0.0))
            ctx.beginPath()
            ctx.moveTo(x(series[0]), H)
            for (let i = 0; i < series.length; i++) ctx.lineTo(x(series[i]), y(series[i]))
            ctx.lineTo(x(series[series.length - 1]), H)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()
        }

        if (seriesB && seriesB.length >= 2) {
            ctx.beginPath()
            ctx.moveTo(x(seriesB[0]), y(seriesB[0]))
            for (let i = 1; i < seriesB.length; i++) ctx.lineTo(x(seriesB[i]), y(seriesB[i]))
            ctx.strokeStyle = strokeB
            ctx.lineWidth = Math.max(1, lineWidth - 0.5)
            ctx.lineJoin = "round"
            ctx.stroke()
        }

        ctx.beginPath()
        ctx.moveTo(x(series[0]), y(series[0]))
        for (let i = 1; i < series.length; i++) ctx.lineTo(x(series[i]), y(series[i]))
        ctx.strokeStyle = stroke
        ctx.lineWidth = lineWidth
        ctx.lineJoin = "round"
        ctx.stroke()

        const lastX = x(series[series.length - 1])
        const lastY = y(series[series.length - 1])
        if (glow) {
            ctx.save()
            ctx.shadowColor = stroke
            ctx.shadowBlur = 8
            ctx.beginPath()
            ctx.arc(lastX, lastY, 2.5, 0, Math.PI * 2)
            ctx.fillStyle = stroke
            ctx.fill()
            ctx.restore()
        }
    }
}
