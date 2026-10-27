/*
 * StockTick v3 — rebuilt on the vpsone/stock-monitor-widget skeleton
 * (shipped, working Plasma 6 code) after v2's separate-file delegate never
 * rendered and its dataengine fetch died silently across restarts.
 *   - data: plain XMLHttpRequest to Yahoo chart API straight from QML
 *     (vpsone pattern — no dataengine, no probe script, no exec-bit)
 *   - rows: ListView + inline delegate reading required properties
 *     fed from a ListModel
 *   - popup: fullRepresentation Item root with Layout.minimum* only
 *   - no sparkline (research verdict: text deltas first; QML Canvas is
 *     fragile in Plasma 6 popups)
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color cPos: "#3fd18b"
    readonly property color cNeg: "#f4405c"

    property string selected: sym()

    function sym() {
        return (Plasmoid.configuration.primary || "MSFT").toUpperCase()
    }
    function syms() {
        var raw = Plasmoid.configuration.symbols
                 || "MSFT,ESTC,BTC-USD,ETH-USD,XRP-USD,VOO,SCHD"
        return raw.split(",").map(function(s) { return s.trim().toUpperCase() })
                  .filter(function(s) { return s.length > 0 })
    }

    ListModel { id: stockModel }

    function fmt(n) {
        if (n === null || n === undefined || isNaN(n)) return "—"
        if (n >= 1000) return n.toFixed(0)
        if (n >= 100) return n.toFixed(1)
        return n.toFixed(2)
    }
    function pctStr(v) {
        if (v === null || v === undefined || isNaN(v)) return ""
        return (v >= 0 ? "+" : "") + v.toFixed(2) + "%"
    }

    function row(t) {
        for (var i = 0; i < stockModel.count; i++)
            if (stockModel.get(i).ticker === t) return stockModel.get(i)
        return null
    }

    // ---- fetch: XMLHttpRequest, one per symbol, no external process -------
    function refresh() {
        var tickers = syms()
        if (stockModel.count !== tickers.length) {
            stockModel.clear()
            tickers.forEach(function(t) {
                stockModel.append({
                    ticker: t, name: "…", price: "—",
                    change: "", pctv: "", isPos: true, raw: 0
                })
            })
        }
        tickers.forEach(function(t) {
            var xhr = new XMLHttpRequest()
            var url = "https://query1.finance.yahoo.com/v8/finance/chart/"
                      + t + "?range=2d&interval=1d"
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try { processRow(t, JSON.parse(xhr.responseText)) }
                        catch (e) { /* keep placeholder */ }
                    } else {
                        setRow(t, { name: "offline", price: "—",
                                    change: "", pctv: "", isPos: true, raw: 0 })
                    }
                }
            }
            xhr.open("GET", url)
            xhr.timeout = 15000
            xhr.send()
        })
    }
    function setRow(t, vals) {
        for (var i = 0; i < stockModel.count; i++) {
            if (stockModel.get(i).ticker === t) {
                stockModel.set(i, vals)
                return
            }
        }
    }
    function processRow(t, json) {
        var r = json && json.chart && json.chart.result && json.chart.result[0]
        if (!r || !r.meta) { return }
        var meta = r.meta
        var close = meta.regularMarketPrice
        var prev = meta.chartPreviousClose
        if (prev === undefined || prev === null || prev === 0) {
            var q = r.indicators && r.indicators.quote
                  && r.indicators.quote[0] && r.indicators.quote[0].close
            if (q && q.length > 1) prev = q[q.length - 2]
        }
        var d = (close !== undefined && prev) ? close - prev : 0
        var p = prev ? (d / prev) * 100 : 0
        setRow(t, {
            name: meta.shortName || meta.longName || t,
            price: fmt(close),
            change: (d >= 0 ? "+" : "−") + Math.abs(d).toFixed(2),
            pctv: pctStr(p),
            isPos: d >= 0,
            raw: close
        })
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMin || 5) * 60000
        running: true; repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()

    // ---- chip --------------------------------------------------------------
    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        readonly property real fpx: Math.round(Math.max(8, height * 0.36))
        implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: root.sym()
                color: Kirigami.Theme.textColor
                font.pixelSize: chip.fpx; font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: {
                    var r = root.row(root.sym())
                    return r ? r.price : "—"
                }
                color: Kirigami.Theme.textColor
                font.pixelSize: chip.fpx
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: {
                    var r = root.row(root.sym())
                    return r ? r.pctv : ""
                }
                color: {
                    var r = root.row(root.sym())
                    return (r && !r.isPos) ? root.cNeg : root.cPos
                }
                font.pixelSize: Math.round(chip.fpx * 0.92); font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ---- popup: vpsone pattern — Item root, Layout.minimum* only ----------
    fullRepresentation: Item {
        Layout.minimumWidth: 440
        Layout.minimumHeight: 120 + root.syms().length * 56

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            clip: true
            spacing: 0
            model: stockModel

            delegate: Item {
                width: list.width
                height: 56
                required property int index
                required property string ticker
                required property string name
                required property string price
                required property string change
                required property string pctv
                required property bool isPos
                required property real raw

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected = ticker
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: ticker
                        color: ticker === root.selected
                               ? Kirigami.Theme.textColor
                               : Kirigami.Theme.disabledTextColor
                        font.pixelSize: 15; font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: name
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: price
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    }
                    Rectangle {
                        radius: 4
                        color: isPos
                            ? Qt.rgba(root.cPos.r, root.cPos.g, root.cPos.b, 0.15)
                            : Qt.rgba(root.cNeg.r, root.cNeg.g, root.cNeg.b, 0.88)
                        border.color: isPos ? root.cPos : root.cNeg
                        border.width: 1
                        Layout.preferredWidth: pctText.implicitWidth + Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: pctText.implicitHeight + Kirigami.Units.smallSpacing
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            id: pctText
                            anchors.centerIn: parent
                            text: (change !== "" ? change + "  " : "") + pctv
                            color: isPos ? root.cPos : "#ffffff"
                            font.pixelSize: 11; font.bold: true
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                                   Kirigami.Theme.disabledTextColor.g,
                                   Kirigami.Theme.disabledTextColor.b, 0.25)
                    visible: index < stockModel.count - 1
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 6
            text: "Yahoo Finance · refresh " + (Plasmoid.configuration.refreshMin || 5) + " min · click row = chip symbol"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 10
        }
    }
}
