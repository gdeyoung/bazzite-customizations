import QtQuick
import QtQuick.Layouts

// HistBars — scrolling bar chart of a {t, v} series: one bar per sample,
// newest at the right, older bars fading toward the left. No positioner:
// bars get explicit x/y. logScale maps v through the log activity curve
// (1 Gbit/s = 100). Ported verbatim from gdeyoung/omarchy-sysmon.
Item {
    id: root

    property var series: []
    property bool logScale: false
    property color activeColor: "#3fb950"
    property real barW: 7
    property real gap: 3
    property real maxH: 34
    property int maxBars: 220

    Layout.fillWidth: true
    implicitHeight: maxH

    function mapV(v) {
        return logScale ? (Math.log(1 + v) / Math.log(1 + 125000000)) * 100 : v
    }

    readonly property real step: barW + gap

    readonly property int nBars: Math.max(4, Math.min(maxBars, Math.floor((width + gap + 0.5) / step)))

    readonly property var view: {
        const s = series || []
        const n = Math.min(nBars, s.length)
        return n > 0 ? s.slice(s.length - n) : []
    }

    Repeater {
        model: root.view.length

        Rectangle {
            id: bar
            required property int index
            readonly property real v: root.mapV(Number(root.view[bar.index].v) || 0)
            x: root.width - (root.view.length - bar.index) * root.step + root.gap
            y: root.maxH - bar.height
            width: root.barW
            height: Math.max(2, Math.min(100, bar.v) / 100 * (root.maxH - 2))
            radius: 1
            color: root.activeColor
            opacity: 0.30 + 0.62 * ((bar.index + 1) / root.view.length)
        }
    }
}
