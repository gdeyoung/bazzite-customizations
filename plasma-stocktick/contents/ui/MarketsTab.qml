/*
 * MarketsTab v2 — user-directed layout (2026-10-29): horizontal tile strip
 * (selector) above ONE big chart. Click a tile → chart shows that series;
 * horizon chips (1D…5Y, MAX) change the span. Tile values from marketM
 * roles (price/change/pct — notify natively); chart data via
 * api.fetchChart (same engine as DetailView, stale-guarded). No per-tile
 * sparks: ListModel array-role storage is unreliable (community packs
 * series as strings to dodge it — see docs/finance-plasmoid-research).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: tab

    property var api                    // root of main.qml
    property var cardModel: null        // marketM rows: symbol,label,price,change,pct
    property string sel: "^GSPC"
    readonly property var spans: [
        { key: "1D",  range: "1d",  interval: "5m"  },
        { key: "5D",  range: "5d",  interval: "30m" },
        { key: "1M",  range: "1mo", interval: "1h"  },
        { key: "3M",  range: "3mo", interval: "1d"  },
        { key: "6M",  range: "6mo", interval: "1d"  },
        { key: "1Y",  range: "1y",  interval: "1d"  },
        { key: "5Y",  range: "5y",  interval: "1wk" },
        { key: "MAX", range: "max", interval: "1mo" }
    ]
    property string spanKey: api.cfg.chartSpan || "3M"
    property var chartData: null        // {points, times, base, up, meta}
    property string loadState: "loading"

    function spanFor(k) {
        for (var i = 0; i < spans.length; i++) if (spans[i].key === k) return spans[i]
        return spans[3]
    }

    function load() {
        if (!sel) return
        loadState = "loading"
        var reqSym = sel, reqSpan = spanKey
        var s = spanFor(reqSpan)
        api.fetchChart(reqSym, s.range, s.interval, function(ok, data) {
            if (reqSym !== tab.sel || reqSpan !== tab.spanKey) return
            if (ok) { chartData = data; loadState = "ok" }
            else loadState = "error"
        })
    }

    onSelChanged: load()
    onSpanKeyChanged: { api.cfg.chartSpan = spanKey; load() }
    // deferred off the popup-open path: synchronous work during popup
    // instantiation correlates with the popup open/close/reopen failures
    Component.onCompleted: initTimer.start()

    Timer {
        id: initTimer
        interval: 150
        onTriggered: tab.load()
    }

    // selected tile's live quote; re-evaluated whenever a fetch lands
    // (function calls alone carry no binding dependency)
    readonly property var q: {
        api.lastFetchAt
        if (!cardModel) return null
        for (var i = 0; i < cardModel.count; i++) {
            var r = cardModel.get(i)
            if (r.symbol === sel) return r
        }
        return null
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        // ---- tile strip (selector) ------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: tab.cardModel

                delegate: Rectangle {
                    id: tile
                    readonly property bool isTnx: symbol === "^TNX"
                    readonly property bool selected: symbol === tab.sel
                    readonly property real raw: model.price
                    readonly property real delta: model.change
                    readonly property real pctv: model.pct

                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    radius: 8
                    color: selected ? Qt.rgba(1, 1, 1, 0.10)
                          : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.07)
                          : Qt.rgba(1, 1, 1, 0.04)

                    // accent underline marks selection, colored by direction
                    Rectangle {
                        visible: tile.selected
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        width: 18; height: 2; radius: 1
                        color: delta >= 0 ? api.cPos : api.cNeg
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.sel = symbol
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 0

                        Text {
                            text: label
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: 9
                            font.letterSpacing: 0.5
                            font.capitalization: Font.AllUppercase
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                if (raw <= 0) return "—"
                                if (isTnx) return (raw < 25 ? raw : raw / 10).toFixed(2) + "%"
                                return api.fmt(raw)
                            }
                            color: Kirigami.Theme.textColor
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            text: {
                                if (raw <= 0 || isNaN(delta)) return ""
                                var up = delta >= 0
                                if (isTnx)
                                    return (up ? "+" : "−")
                                           + Math.abs(delta * (raw < 25 ? 100 : 10)).toFixed(1) + "bp"
                                return (up ? "+" : "−") + Math.abs(pctv).toFixed(2) + "%"
                            }
                            color: delta >= 0 ? api.cPos : api.cNeg
                            font.pixelSize: 10
                            font.bold: true
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }

        // ---- header: selected name + day move | horizon chips ---------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: (tab.q ? tab.q.label : tab.sel)
                      + (tab.q && tab.q.price > 0
                         ? "   " + (tab.q.change >= 0 ? "▲ +" : "▼ −")
                           + Math.abs(tab.q.pct).toFixed(2) + "% today"
                         : "")
                color: Kirigami.Theme.textColor
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: tab.spans
                delegate: Rectangle {
                    readonly property bool active: modelData.key === tab.spanKey
                    radius: 4
                    width: spText.implicitWidth + 14
                    height: 24
                    color: active ? Qt.rgba(1, 1, 1, 0.14)
                          : spMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    MouseArea {
                        id: spMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.spanKey = modelData.key
                    }
                    Text {
                        id: spText
                        anchors.centerIn: parent
                        text: modelData.key
                        color: active ? Kirigami.Theme.textColor
                                      : Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        font.bold: active
                    }
                }
            }
        }

        // ---- the one big chart ----------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PriceChart {
                anchors.fill: parent
                points: tab.chartData ? tab.chartData.points : []
                times: tab.chartData ? tab.chartData.times : []
                base: tab.chartData ? tab.chartData.base : 0
                lineColor: tab.chartData && tab.chartData.up ? api.cPos : api.cNeg
            }

            Text {
                visible: tab.loadState === "loading"
                anchors.centerIn: parent
                text: "loading chart…"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 12
            }
            QQC2.Button {
                visible: tab.loadState === "error"
                anchors.centerIn: parent
                text: "Couldn't load chart — Retry"
                onClicked: tab.load()
            }
        }
    }

    Text {
        visible: !tab.cardModel || tab.cardModel.count === 0
        anchors.centerIn: parent
        text: "loading markets…"
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: 12
    }
}
