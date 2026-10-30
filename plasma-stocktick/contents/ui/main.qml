/*
 * StockTick v4 — per DESIGN-v4.md (UX designer spec, 2026-10-29).
 * Architecture: this file = root (config, models, fetch engine, chip);
 * PopupShell/MarketsTab/WatchlistTab/PortfolioTab/DetailView/
 * PriceChart/Sparkline = components. One grammar per surface (spec G).
 * Data: keyless Yahoo chart + search endpoints, QML XHR only (vpsone
 * pattern — curl 429s from this IP, XHR works).
 * Fetch matrix (spec appendix): watchlist always (1d/30m, rows+sparks);
 * chip series on selection/refresh (1d/15m); markets on popup open;
 * detail chart per span; search debounced in WatchlistTab.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- visual tokens (spec G: fixed hex — Kirigami semantic pos/neg
    // resolve undefined in compact reps on 6.7; pair = systemmonitor's)
    readonly property color cPos: "#3fd18b"
    readonly property color cNeg: "#f4405c"

    // ---- state
    property int rotIndex: Math.max(0, syms().indexOf(sym()))
    property string selected: syms()[rotIndex] || sym()
    property string detailSymbol: ""
    property var chipSeries: []
    property var lastFetchAt: null       // epoch ms of last good quote
    property int marketsTick: 0          // bumped when marketM rows update
    readonly property bool freshData: lastFetchAt !== null
                                      && (Date.now() - lastFetchAt) < 10 * 60 * 1000
    readonly property string asOfTime: lastFetchAt !== null
                                       ? Qt.formatDateTime(new Date(lastFetchAt), "h:mm AP")
                                       : "—"

    function sym() {
        return (Plasmoid.configuration.primary || "MSFT").toUpperCase()
    }
    function syms() {
        var raw = Plasmoid.configuration.symbols
                 || "MSFT,ESTC,BTC-USD,ETH-USD,XRP-USD,VOO,SCHD"
        return raw.split(",").map(function(s) { return s.trim().toUpperCase() })
                  .filter(function(s) { return s.length > 0 })
    }
    function setSyms(list) {
        Plasmoid.configuration.symbols = list.join(",")
    }
    function addSymbol(t) {
        var list = syms()
        if (list.indexOf(t) < 0) { list.push(t); setSyms(list) }
        rebuild()
        refresh()
    }
    function removeSymbol(t) {
        var list = syms().filter(function(s) { return s !== t })
        setSyms(list)
        rebuild()
        if (selected === t) rotIndex = 0
    }

    // ---- models
    ListModel { id: stockModel }
    ListModel { id: marketM }
    // exposed for component files (Plasmoid context prop is root-file-only —
    // verified the hard way; components get everything through `api`)
    readonly property alias marketModel: marketM
    readonly property alias watchModel: stockModel
    readonly property QtObject cfg: Plasmoid.configuration
    function openConfigure() {
        var a = Plasmoid.internalAction("configure")
        if (a) a.trigger()
    }
    readonly property var marketCards: [
        { symbol: "^GSPC",  label: "S&P 500" },
        { symbol: "^IXIC",  label: "NASDAQ" },
        { symbol: "^DJI",   label: "DOW 30" },
        { symbol: "^TNX",   label: "10-YR YIELD" },
        { symbol: "^VIX",   label: "VIX" },
        { symbol: "BTC-USD", label: "BITCOIN" }
    ]

    function rebuild() {
        var tickers = syms()
        stockModel.clear()
        tickers.forEach(function(t) {
            stockModel.append({
                ticker: t, name: "…", price: "—",
                change: "", pctv: "", isPos: true, raw: 0, series: []
            })
        })
    }

    // unified quote lookup across watchlist + markets (portfolio + detail use this)
    function marketRow(t) {
        if (!t) return null
        var s = t.toUpperCase()
        for (var i = 0; i < stockModel.count; i++) {
            var r = stockModel.get(i)
            if (r.ticker === s) return r
        }
        for (var j = 0; j < marketM.count; j++) {
            var m = marketM.get(j)
            if (m.symbol === s) return m
        }
        return null
    }
    function row(t) { return marketRow(t) }

    // ---- formatting
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

    // ---- XHR helpers -------------------------------------------------------
    function xhrGet(url, cb) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var ok = false, json = null
                if (xhr.status === 200) {
                    try { json = JSON.parse(xhr.responseText); ok = true }
                    catch (e) { ok = false }
                }
                cb(ok, json)
            }
        }
        xhr.open("GET", url)
        xhr.timeout = 15000
        xhr.send()
        return xhr
    }

    function chartUrl(sym_, range, interval) {
        return "https://query1.finance.yahoo.com/v8/finance/chart/"
               + encodeURIComponent(sym_) + "?range=" + range + "&interval=" + interval
    }

    // watchlist quotes: 1d/30m gives rows AND row sparklines
    function refresh() {
        var tickers = syms()
        tickers.forEach(function(t) {
            xhrGet(chartUrl(t, "1d", "30m"), function(ok, json) {
                if (ok) processRow(t, json)
                else setRow(t, { name: "offline", price: "—",
                                 change: "", pctv: "", isPos: true, raw: 0, series: [] })
            })
        })
        fetchChipSeries()
    }

    function setRow(t, vals) {
        for (var i = 0; i < stockModel.count; i++) {
            if (stockModel.get(i).ticker === t) { stockModel.set(i, vals); return }
        }
    }

    function extractCloses(r) {
        var q = r.indicators && r.indicators.quote
              && r.indicators.quote[0] && r.indicators.quote[0].close
        var ts = r.timestamp || []
        var pts = [], times = []
        if (!q) return { pts: pts, times: times }
        for (var i = 0; i < q.length; i++) {
            if (q[i] !== null && q[i] !== undefined && ts[i]) {
                pts.push(q[i]); times.push(ts[i])
            }
        }
        return { pts: pts, times: times }
    }

    function processRow(t, json) {
        var r = json && json.chart && json.chart.result && json.chart.result[0]
        if (!r || !r.meta) return
        var meta = r.meta
        var close = meta.regularMarketPrice
        var prev = meta.chartPreviousClose
        if (prev === undefined || prev === null || prev === 0) prev = meta.previousClose
        var d = (close !== undefined && prev) ? close - prev : 0
        var p = prev ? (d / prev) * 100 : 0
        var ex = extractCloses(r)
        setRow(t, {
            name: meta.shortName || meta.longName || t,
            price: fmt(close),
            change: (d >= 0 ? "+" : "−") + Math.abs(d).toFixed(2),
            pctv: pctStr(p),
            isPos: d >= 0,
            raw: close,
            series: ex.pts
        })
        lastFetchAt = Date.now()
    }

    // chip sparkline series (1d/15m) — piggybacks refresh + selection changes
    function fetchChipSeries() {
        var s = selected
        xhrGet(chartUrl(s, "1d", "15m"), function(ok, json) {
            if (s !== selected) return      // stale
            if (!ok) { return }
            var r = json && json.chart && json.chart.result && json.chart.result[0]
            if (!r) return
            chipSeries = extractCloses(r).pts
        })
    }

    // markets cards — fetched only while popup is open
    function fetchMarkets() {
        marketCards.forEach(function(c) {
            xhrGet(chartUrl(c.symbol, "1d", "30m"), function(ok, json) {
                var found = false
                for (var i = 0; i < marketM.count; i++)
                    if (marketM.get(i).symbol === c.symbol) { found = true; break }
                if (!found)
                    marketM.append({ symbol: c.symbol, label: c.label,
                                         price: 0, change: 0, pct: 0, series: [] })
                if (!ok) return
                var r = json && json.chart && json.chart.result && json.chart.result[0]
                if (!r || !r.meta) return
                var meta = r.meta
                var close = meta.regularMarketPrice
                var prev = meta.chartPreviousClose || meta.previousClose
                var d = (close !== undefined && prev) ? close - prev : 0
                for (var j = 0; j < marketM.count; j++) {
                    if (marketM.get(j).symbol === c.symbol) {
                        marketM.set(j, {
                            symbol: c.symbol, label: c.label,
                            price: close, change: d,
                            pct: prev ? (d / prev) * 100 : 0,
                            series: extractCloses(r).pts
                        })
                        root.marketsTick++
                        break
                    }
                }
            })
        })
    }

    // generic chart fetch for DetailView (span change = one fetch)
    function fetchChart(sym_, range, interval, cb) {
        xhrGet(chartUrl(sym_, range, interval), function(ok, json) {
            if (!ok) { cb(false, null); return }
            var r = json && json.chart && json.chart.result && json.chart.result[0]
            if (!r || !r.meta) { cb(false, null); return }
            var ex = extractCloses(r)
            if (ex.pts.length < 5) { cb(false, null); return }
            var base = (range === "1d")
                       ? (r.meta.chartPreviousClose || r.meta.previousClose || ex.pts[0])
                       : ex.pts[0]
            cb(true, {
                points: ex.pts, times: ex.times,
                base: base,
                up: ex.pts[ex.pts.length - 1] >= ex.pts[0],
                meta: r.meta
            })
        })
    }

    // symbol search (Yahoo /v1/finance/search, keyless; degrades to [] on failure)
    function searchYahoo(q, cb) {
        xhrGet("https://query1.finance.yahoo.com/v1/finance/search?q="
               + encodeURIComponent(q) + "&quotesCount=8&newsCount=0",
               function(ok, json) {
                   if (!ok || !json || !json.quotes) { cb([]); return }
                   var out = []
                   json.quotes.forEach(function(it) {
                       if (!it.symbol) return
                       out.push({
                           symbol: it.symbol.toUpperCase(),
                           shortname: it.shortname || it.longname || "",
                           quoteType: it.quoteType || ""
                       })
                   })
                   cb(out)
               })
    }

    function refreshAll() { refresh(); fetchMarkets() }

    // ---- timers ------------------------------------------------------------
    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMin || 5) * 60000
        running: true; repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        // Chip rotation: 0 disables (pinned). >=5s floor.
        interval: Math.max(5, Plasmoid.configuration.rotateSeconds || 0) * 1000
        running: (Plasmoid.configuration.rotateSeconds || 0) > 0
                 && root.syms().length > 1
        repeat: true
        onTriggered: root.rotIndex = (root.rotIndex + 1) % root.syms().length
    }
    onSelectedChanged: fetchChipSeries()
    // fetches deferred off the open signal itself — the synchronous XHR
    // burst inside the expanded-changed handler is the prime suspect for
    // the v4.1 popup open-then-close flakiness (weatherx does no work here)
    onExpandedChanged: function(expanded) {
        if (expanded) openFetchTimer.restart()
    }
    Timer {
        id: openFetchTimer
        interval: 150
        onTriggered: if (root.expanded) fetchMarkets()
    }
    Component.onCompleted: { rebuild(); refresh() }

    // ---- chip (spec A: two-line lockup, price is the headline) -------------
    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true
        // EXACT pattern of plasma-weatherx compact (proven flawless on this
        // build) — function-form handler, toggle PlasmoidItem.expanded.
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.openConfigure()
            else
                root.expanded = !root.expanded
        }

        readonly property real bigPx: Math.round(Math.max(12, height * 0.44))
        readonly property real smallPx: Math.round(Math.max(10, height * 0.30))

        // FIXED cell width (design-spec note): rotation cycles symbols of
        // different rendered widths — a natural-size chip physically moves
        // under the pointer between ticks, and missed clicks read as
        // "popup won't reopen". The cell must cover the WIDEST lockup ever
        // shown (all symbols' price + spark), measured with TextMetrics —
        // a hardcoded 132 underestimated the price column and the RowLayout
        // overflowed LEFT past the item bounds: visible-but-unclickable
        // strip (user-reported 2026-10-30). Width is computed from ALL
        // rows, not the currently shown one, so it never moves on rotation.
        //
        // SIZING RULE (panelpad lesson, c361156): a compactRepresentation
        // that sets ONLY implicitWidth collapses to a ~34px default cell —
        // the rest of the content paints outside the hit area. Set
        // width/implicit/preferred/minimum TOGETHER or the MouseArea stays
        // tiny.
        TextMetrics {
            id: tmPrice
            font.pixelSize: chip.bigPx
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
        TextMetrics {
            id: tmSym
            font.pixelSize: chip.smallPx
            font.letterSpacing: 0.6
        }
        readonly property real measuredW: {
            var c = root.watchModel.count
            // dependency kick: rows are appended as stubs ("—" prices) and
            // filled AFTER, with count unchanged — reading row 0's price
            // here re-fires this binding when real prices land.
            var kick = c > 0 ? (root.watchModel.get(0).price || "") : ""
            var w = 0
            for (var i = 0; i < c; i++) {
                var r = root.watchModel.get(i)
                tmPrice.text = r.price || ""
                var col = tmPrice.advanceWidth
                tmSym.text = (r.symbol || "") + "  ▲00.00%"
                col = Math.max(col, tmSym.advanceWidth)
                if (col > w) w = col
            }
            return w
        }
        readonly property real cellW: Math.max(
            132,
            Math.ceil(measuredW) + 64 /* spark */
                + Kirigami.Units.smallSpacing * 3 /* row spacing + right margin */
                + 2)
        width: cellW
        implicitWidth: cellW
        Layout.preferredWidth: cellW
        Layout.minimumWidth: cellW
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        // hover feedback so pointer-on-chip is visible
        Rectangle {
            anchors.fill: parent
            radius: 4
            color: chip.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        }

        RowLayout {
            id: chipRow
            // RIGHT-anchored: the right edge (nearest the clock) never moves
            // when rotation swaps symbols — gap stays constant, group
            // geometry stable. Left part of the cell = clickable space.
            anchors.right: parent.right
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Kirigami.Units.smallSpacing

            Column {
                spacing: 1
                Layout.alignment: Qt.AlignVCenter

                Text {
                    text: {
                        var r = root.row(root.selected)
                        return r ? r.price : "—"
                    }
                    color: Kirigami.Theme.textColor
                    font.pixelSize: chip.bigPx
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Row {
                    spacing: Kirigami.Units.smallSpacing
                    Text {
                        text: root.selected
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: chip.smallPx
                        font.letterSpacing: 0.6
                    }
                    Text {
                        text: {
                            var r = root.row(root.selected)
                            if (!r || r.pctv === "") return ""
                            return (r.isPos ? "▲" : "▼") + r.pctv
                        }
                        color: {
                            var r = root.row(root.selected)
                            return (r && !r.isPos) ? root.cNeg : root.cPos
                        }
                        font.pixelSize: chip.smallPx
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Sparkline {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: chip.height - 10
                points: root.chipSeries
                lineColor: {
                    var r = root.row(root.selected)
                    return (r && !r.isPos) ? root.cNeg : root.cPos
                }
            }
        }
    }

    // ---- popup shell -------------------------------------------------------
    // Popup size resolution, Plasma 6.7 (source-verified, libplasma v6.7.5
    // src/plasmaquick/appletpopup.cpp + plasma-desktop desktoppackage
    // CompactApplet.qml — full writeup in docs/popup-sizing-plasma67.md):
    //   1. popupWidth/popupHeight in THIS applet's config group win over
    //      everything, forever (m_sizeExplicitlySetFromConfig early-return
    //      in updateSize). hideEvent writes both keys on EVERY popup close
    //      (and Alt+RightClick-drag persists a resized size the same way),
    //      so one close at a wrong size pins it across restarts — delete
    //      the two keys with the shell STOPPED to unstick.
    //   2. Otherwise wanted size = fullRep Layout.preferred* if > 0, else
    //      fullRep implicitWidth/Height (via CompactApplet's appletParent
    //      implicit bindings), else CompactApplet fallback
    //      iconSizes.sizeForLabels*35 × *25  (the old 720×520 floor).
    //   3. Final = clamp(wanted, Layout.minimum*, min(Layout.maximum*,
    //      95% of screen)).
    // A bare Item root has implicit size 0, so Layout.minimum* = design size
    // clamps the fallback UP to 960×640 — the shipped pattern of
    // vpsone/stock-monitor-widget, harness-verified: content item exactly
    // 960 wide × 640+1 (the +1 is CompactApplet's 1px panel separator,
    // extraHeight), popup window 968×649 = content + 4px/side frame padding.
    fullRepresentation: Item {
        Layout.minimumWidth: 960
        Layout.minimumHeight: 640

        PopupShell {
            anchors.fill: parent
            api: root
        }
    }
}
