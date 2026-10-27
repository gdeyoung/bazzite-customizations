/*
 * StockTick v2 — panel chip (primary symbol + price + colored Δ%) and popup
 * (watchlist rows; click a row → hero with price, Δ, 3-month sparkline).
 * Plumbing mirrors weatherx exactly: one fire-once connectSource per fetch,
 * curl-driven shell probe, single-line JSON contract.
 * Colors: fixed hex (Kirigami positiveText/negativeText are undefined in
 * plasmoid compactRepresentation on Plasma 6.7 — journal-verified).
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model

PlasmoidItem {
    id: root

    // fixed green/red — Kirigami semantic colors are undefined here
    readonly property color cPos: "#3fd18b"
    readonly property color cNeg: "#f4405c"

    property var doc: null
    property string sym: (Plasmoid.configuration.primary || "MSFT").toUpperCase()
    property string selected: sym            // hero symbol in the popup
    readonly property var quotes: (doc && doc.ok) ? doc.quotes : ({})
    readonly property var q: quotes[selected] || null
    readonly property var q0: quotes[sym] || null
    onSymChanged: selected = sym

    readonly property var syms: {
        const raw = (Plasmoid.configuration.symbols
                     || "MSFT,ESTC,BTC-USD,ETH-USD,XRP-USD,VOO,SCHD")
        return raw.split(",").map(s => s.trim().toUpperCase()).filter(s => s.length > 0)
    }

    // ---- fetch (weatherx pattern: connectSource once, disconnect on data) --
    function probeCmd() {
        return Qt.resolvedUrl("../scripts/fetch-quotes.sh")
            .toString().replace("file://", "") + " " + syms.join(",")
    }
    function refetch() { exec.connectSource(probeCmd()) }
    Component.onCompleted: refetch()

    DataSource {
        id: exec
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            const out = data["stdout"] || ""
            try {
                root.doc = JSON.parse(out.trim().split("\n").pop())
            } catch (e) { /* keep last good */ }
            exec.disconnectSource(sourceName)
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMin || 5) * 60000
        running: true; repeat: true
        onTriggered: root.refetch()
    }

    // ---- chip ----------------------------------------------------------------
    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true
        readonly property real fpx: Math.round(Math.max(8, height * 0.36))
        implicitWidth: chipRow.implicitWidth + Kirigami.Units.gridUnit * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing * 1.5

            Text {
                text: root.sym.replace(".US", "")
                color: Kirigami.Theme.textColor
                font.pixelSize: chip.fpx; font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.q0 ? Model.fmtPrice(root.q0.close) : "—"
                color: Kirigami.Theme.textColor
                font.pixelSize: chip.fpx
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.q0 ? Model.fmtPct(root.q0.deltaPct) : ""
                color: root.q0 && root.q0.deltaPct >= 0 ? root.cPos : root.cNeg
                font.pixelSize: Math.round(chip.fpx * 0.92); font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        onClicked: root.expanded = !root.expanded
    }

    // ---- popup ---------------------------------------------------------------
    fullRepresentation: Column {
        id: popup
        width: Kirigami.Units.gridUnit * 34
        spacing: Kirigami.Units.largeSpacing
        leftPadding: Kirigami.Units.gridUnit
        rightPadding: Kirigami.Units.gridUnit
        topPadding: Kirigami.Units.gridUnit * 0.6
        bottomPadding: Kirigami.Units.gridUnit * 0.6

        // hero: selected symbol
        Column {
            width: parent.width - parent.leftPadding - parent.rightPadding
            spacing: Kirigami.Units.smallSpacing

            Row {
                spacing: Kirigami.Units.largeSpacing
                Text {
                    text: root.selected.replace(".US", "")
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    font.bold: true
                }
                Text {
                    text: root.q ? Model.fmtPrice(root.q.close) : "—"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    font.bold: true
                }
                Text {
                    text: root.q ? Model.fmtPct(root.q.deltaPct) : ""
                    color: root.q && root.q.deltaPct >= 0 ? root.cPos : root.cNeg
                    font.pixelSize: Kirigami.Units.gridUnit * 0.9
                    font.bold: true
                }
                Text {
                    text: root.doc && root.doc.ok ? "Yahoo · 3mo" : "loading…"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.5
                }
            }

            // sparkline for the selected symbol
            Canvas {
                id: heroSpark
                width: parent.width
                height: Kirigami.Units.gridUnit * 4
                visible: root.q && root.q.spark && root.q.spark.length > 1

                onPaint: {
                    var pts = root.q ? root.q.spark : []
                    if (pts.length < 2) return
                    var ctx = getContext("2d")
                    ctx.reset()
                    var min = Math.min.apply(null, pts), max = Math.max.apply(null, pts)
                    if (max === min) max = min + 1
                    var up = pts[pts.length - 1] >= pts[0]
                    ctx.strokeStyle = up ? root.cPos : root.cNeg
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < pts.length; i++) {
                        var x = i / (pts.length - 1) * width
                        var y = height - 4 - (pts[i] - min) / (max - min) * (height - 8)
                        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                Connections {
                    target: root
                    function onQChanged() { heroSpark.requestPaint() }
                    function onSelectedChanged() { heroSpark.requestPaint() }
                }
                Component.onCompleted: requestPaint()
            }
        }

        Rectangle {
            width: parent.width - parent.leftPadding - parent.rightPadding
            height: 1
            color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                           Kirigami.Theme.disabledTextColor.g,
                           Kirigami.Theme.disabledTextColor.b, 0.4)
        }

        // watchlist rows (delegate in StockRow.qml — one-handler rule)
        Repeater {
            model: root.syms
            StockRow {
                panel: root
                modelData: modelData
            }
        }

        Text {
            text: "click a row to inspect · data: Yahoo Finance (keyless) · every "
                  + (Plasmoid.configuration.refreshMin || 5) + " min"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.45
            width: parent.width - parent.leftPadding - parent.rightPadding
        }
    }
}
