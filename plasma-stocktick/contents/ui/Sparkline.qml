// Minimal sparkline — normalized series in, themed polyline out.
import QtQuick

Canvas {
    id: c
    property var series: []
    property color lineColor: "green"   // set by parent from theme tokens

    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        if (!series || series.length < 2) return;
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        const w = width - 2, h = height - 2;
        for (let i = 0; i < series.length; i++) {
            const x = 1 + series[i].x * w;
            const y = 1 + (1 - series[i].y) * h;   // y down in canvas space
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.stroke();
    }
}
