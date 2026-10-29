/*
 * DetailView — per-symbol drill-in (spec D, pass 1: no crosshair/session chips).
 * Header: ‹ back · symbol + name · price + DAY delta (from watchlist row —
 * always session-true, never range-relative). Span selector: 7 chips, one
 * fetch per change (stale-responses ignored). Chart: PriceChart with baseline
 * at span start close. Stats row: O/H/L/PREV/VOL + day range micro-bar.
 * Pushed over the tab shell; Esc = back.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: detail

    property var api
    property string symbol: ""
    readonly property var spans: [
        { key: "1D", range: "1d",    interval: "5m"  },
        { key: "5D", range: "5d",    interval: "30m" },
        { key: "1M", range: "1mo",   interval: "1h"  },
        { key: "3M", range: "3mo",   interval: "1d"  },
        { key: "6M", range: "6mo",   interval: "1d"  },
        { key: "1Y", range: "1y",    interval: "1d"  },
        { key: "5Y", range: "5y",    interval: "1wk" }
    ]
    property string spanKey: api.cfg.chartSpan || "3M"
    property var chartData: null      // {points, times, base, up, meta}
    property string loadState: "loading"   // loading | ok | error

    function spanFor(k) {
        for (var i = 0; i < spans.length; i++) if (spans[i].key === k) return spans[i]
        return spans[3]
    }

    function load() {
        if (!symbol) return
        loadState = "loading"
        var reqSymbol = symbol
        var reqSpan = spanKey
        var s = spanFor(reqSpan)
        api.fetchChart(reqSymbol, s.range, s.interval, function(ok, data) {
            // stale-guard: only latest symbol+span may paint
            if (reqSymbol !== detail.symbol || reqSpan !== detail.spanKey) return
            if (ok) { chartData = data; loadState = "ok" }
            else loadState = "error"
        })
    }

    onSymbolChanged: { chartData = null; load() }
    onSpanKeyChanged: {
        api.cfg.chartSpan = spanKey
        load()
    }
    Component.onCompleted: load()
    onVisibleChanged: if (visible) forceActiveFocus()

    Keys.onEscapePressed: api.detailSymbol = ""

    readonly property var row: api.marketRow(symbol)

    function fmtVol(n) {
        if (!n || isNaN(n)) return "—"
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return n.toString()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 8

        // ---- header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            QQC2.ToolButton {
                text: "‹"
                font.pixelSize: 22
                onClicked: api.detailSymbol = ""
            }
            ColumnLayout {
                spacing: 0
                RowLayout {
                    spacing: 8
                    Text {
                        text: detail.symbol
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 20; font.weight: Font.DemiBold
                    }
                    Text {
                        text: detail.row ? detail.row.name : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.maximumWidth: 260
                    }
                }
            }
            Item { Layout.fillWidth: true }
            ColumnLayout {
                spacing: 0
                Text {
                    text: detail.row ? detail.row.price : "—"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 24; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: detail.row
                          ? (detail.row.change !== "" ? detail.row.change + "  " : "")
                            + detail.row.pctv : ""
                    color: detail.row && detail.row.isPos ? api.cPos : api.cNeg
                    font.pixelSize: 12; font.bold: true
                    font.features: { "tnum": 1 }
                }
            }
        }

        // ---- span selector
        RowLayout {
            spacing: 4
            Repeater {
                model: detail.spans
                delegate: Rectangle {
                    readonly property bool active: modelData.key === detail.spanKey
                    readonly property bool hovered: spMa.containsMouse
                    radius: 4
                    width: spText.implicitWidth + 16
                    height: 26
                    color: active ? Qt.rgba(1, 1, 1, 0.14)
                          : hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    MouseArea {
                        id: spMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: detail.spanKey = modelData.key
                    }
                    Text {
                        id: spText
                        anchors.centerIn: parent
                        text: modelData.key
                        color: active ? Kirigami.Theme.textColor
                                      : Kirigami.Theme.disabledTextColor
                        font.pixelSize: 12
                        font.bold: active
                    }
                }
            }
        }

        // ---- chart
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PriceChart {
                anchors.fill: parent
                points: detail.chartData ? detail.chartData.points : []
                times: detail.chartData ? detail.chartData.times : []
                base: detail.chartData ? detail.chartData.base : 0
                lineColor: detail.chartData && detail.chartData.up ? api.cPos : api.cNeg
            }

            Text {
                visible: detail.loadState === "loading"
                anchors.centerIn: parent
                text: "loading chart…"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 12
            }
            ColumnLayout {
                visible: detail.loadState === "error"
                anchors.centerIn: parent
                spacing: 4
                Text { Layout.alignment: Qt.AlignHCenter; text: "Couldn't load chart"; color: Kirigami.Theme.textColor; font.pixelSize: 13 }
                QQC2.Button { Layout.alignment: Qt.AlignHCenter; text: "Retry"; onClicked: detail.load() }
            }
        }

        // ---- stats row
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Repeater {
                model: {
                    var m = detail.chartData ? detail.chartData.meta : null
                    var lo = m ? m.regularMarketDayLow : 0
                    var hi = m ? m.regularMarketDayHigh : 0
                    var cur = detail.row ? detail.row.raw : 0
                    return [
                        { label: "OPEN",  v: m ? api.fmt(m.regularMarketOpen) : "—" },
                        { label: "HIGH",  v: m ? api.fmt(hi) : "—" },
                        { label: "LOW",   v: m ? api.fmt(lo) : "—" },
                        { label: "PREV",  v: m ? api.fmt(m.chartPreviousClose) : "—" },
                        { label: "VOL",   v: m ? detail.fmtVol(m.regularMarketVolume) : "—" },
                        { label: "DAY RANGE", v: (lo && hi) ? api.fmt(lo) + " – " + api.fmt(hi) : "—",
                          lo: lo, hi: hi, cur: cur }
                    ]
                }
                delegate: ColumnLayout {
                    spacing: 2
                    property var stat: modelData
                    Text { text: stat.label; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 9; font.letterSpacing: 0.5 }
                    Text { text: stat.v; color: Kirigami.Theme.textColor; font.pixelSize: 12; font.features: { "tnum": 1 } }
                    // day-range micro-bar: marker = current position
                    Rectangle {
                        visible: stat.label === "DAY RANGE" && stat.hi > stat.lo
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.15)
                        Rectangle {
                            readonly property real frac: stat.cur > 0
                                ? Math.min(1, Math.max(0, (stat.cur - stat.lo) / (stat.hi - stat.lo)))
                                : 0
                            width: 5; height: 5; radius: 2.5
                            x: (parent.width - 5) * frac
                            anchors.verticalCenter: parent.verticalCenter
                            color: Kirigami.Theme.textColor
                        }
                    }
                }
            }
        }
    }
}
