/*
 * StockTick — panel chip: SYM price ±Δ%; popup: primary hero + sparkline,
 * watchlist, optional portfolio. Pure QML + shell probe, user-level install.
 * Color semantics: Kirigami.Theme.positiveText / negativeText only.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model

PlasmoidItem {
    id: root

    property var doc: null              // last parsed probe document
    property string sym: (Plasmoid.configuration.primary || "MSFT").toUpperCase()
    property var quotes: doc && doc.ok ? doc.quotes : ({})
    property var primaryQuote: quotes[sym] ?? null
    // Fixed green/red, same approach as sysmon (Kirigami positiveText/
    // negativeText resolve to undefined in this plasmoid context on Plasma 6.7).
    property bool up: primaryQuote ? (primaryQuote.deltaPct >= 0) : false
    readonly property color cPos: "#3fd18b"
    readonly property color cNeg: "#f4405c"

    // fetch loop: fire-once executable source, weatherx's proven pattern —
    // connectSource once; onNewData disconnects. (Setting connectedSources
    // then clearing it races the engine and kills the fetch mid-run.)
    function refetch() {
        const syms = (Plasmoid.configuration.symbols
                      || "MSFT,ESTC,BTC-USD,ETH-USD,XRP-USD,VOO,SCHD").trim();
        const pos = (Plasmoid.configuration.positions || "").trim();
        fetch.connectSource(Qt.resolvedUrl("../scripts/fetch-quotes.sh")
            .toString().replace("file://", "") + " " + syms + " "
            + (Plasmoid.configuration.primary || "MSFT") + " "
            + (pos ? "'" + pos.split("'").join("") + "'" : "-"));
    }

    // Fetch once at load, then on the refresh timer.
    Component.onCompleted: refetch()

    DataSource {
        id: fetch
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            const out = data["stdout"] || "";
            try {
                root.doc = JSON.parse(out.trim().split("\n").pop());  // single-line contract
            } catch (e) { /* keep last good doc */ }
            fetch.disconnectSource(sourceName);
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMin || 5) * 60000
        running: true; repeat: true
        triggeredOnStart: true
        onTriggered: root.refetch()
    }

    compactRepresentation: MouseArea {
        id: chip
        hoverEnabled: true
        // Same sizing pattern as weatherx/sysmon (proven on this panel):
        // bind implicitWidth to the row or the chip collapses to icon width.
        // Extra width = breathing room next to the clock (no spacer widgets).
        implicitWidth: chipRow.implicitWidth + Kirigami.Units.gridUnit * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: root.sym.replace(".US", "")
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.58
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.primaryQuote ? Model.fmtPrice(root.primaryQuote.close) : "…"
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.58
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.primaryQuote ? Model.fmtPct(root.primaryQuote.deltaPct) : ""
                color: root.up ? Kirigami.Theme.positiveText : Kirigami.Theme.negativeText
                font.pixelSize: Kirigami.Units.gridUnit * 0.55
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: ColumnLayout {
        id: popup
        Layout.preferredWidth: 340
        Layout.minimumHeight: 160
        spacing: Kirigami.Units.smallSpacing
        Layout.preferredHeight: headerRow.implicitHeight + watchLabel.implicitHeight
            + watchList.implicitHeight + (pfBox.visible ? pfBox.implicitHeight : 0)
            + asofLabel.implicitHeight + 7 * Kirigami.Units.smallSpacing

        RowLayout {                                        // hero: primary symbol
            id: headerRow
            Layout.fillWidth: true
            PC3.Label {
                text: root.sym.replace(".US", "")
                font.pixelSize: 20; font.bold: true
            }
            Item { Layout.fillWidth: true }
            ColumnLayout {
                spacing: 0
                PC3.Label {
                    Layout.alignment: Qt.AlignRight
                    text: root.primaryQuote ? Model.fmtPrice(root.primaryQuote.close) : "—"
                    font.pixelSize: 20; font.bold: true
                }
                PC3.Label {
                    Layout.alignment: Qt.AlignRight
                    text: root.primaryQuote
                          ? Model.fmtPct(root.primaryQuote.deltaPct) : ""
                    font.bold: true
                    color: root.up ? root.cPos : root.cNeg
                }
            }
            Sparkline {                                    // 30-day series
                Layout.leftMargin: Kirigami.Units.smallSpacing
                implicitWidth: 90; implicitHeight: 40
                series: Model.normalizeSeries(root.doc ? root.doc.spark : [])
                lineColor: root.up ? root.cPos : root.cNeg
            }
        }

        PC3.Label {                                        // watchlist
            id: watchLabel
            text: "Watchlist"
            font.bold: true; opacity: 0.7
        }
        Repeater {                                         // one row per symbol
            id: watchList
            model: {
                const out = [];
                const syms = (Plasmoid.configuration.symbols || "").toUpperCase()
                    .split(",").map(s => s.trim()).filter(s => s && s !== root.sym);
                syms.forEach(s => out.push(root.quotes[s] ? s : null));
                return out.filter(Boolean);
            }
            RowLayout {
                Layout.fillWidth: true
                PC3.Label { text: modelData.replace(".US", ""); font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: root.quotes[modelData]
                          ? Model.fmtPrice(root.quotes[modelData].close) : "—"
                    font.pixelSize: 12
                }
                PC3.Label {
                    text: root.quotes[modelData]
                          ? Model.fmtPct(root.quotes[modelData].deltaPct) : ""
                    font.pixelSize: 11; font.bold: true
                    color: (root.quotes[modelData].deltaPct >= 0)
                           ? root.cPos : root.cNeg
                }
            }
        }

        PortfolioBox {                                     // optional positions
            id: pfBox
            visible: modelOk
            quotes: root.quotes
            positions: Plasmoid.configuration.positions || ""
            cPos: root.cPos; cNeg: root.cNeg
        }

        PC3.Label {                                        // as-of + refresh hint
            id: asofLabel
            Layout.fillWidth: true
            font.pixelSize: 10; opacity: 0.6
            text: root.doc && root.doc.ok
                  ? ("Stooq · " + new Date(root.doc.asof * 1000).toLocaleTimeString()
                     + " · refreshes every "
                     + (Plasmoid.configuration.refreshMin || 5) + " min")
                  : (root.doc && !root.doc.ok ? "fetch failed — retrying next tick"
                                               : "waiting for first fetch…")
        }
    }
}
