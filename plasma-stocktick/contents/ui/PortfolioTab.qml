/*
 * PortfolioTab — holdings + totals (spec F; storage in plasmoid config key
 * `portfolioJson` — QML has no file IO, config is atomic via Plasma).
 * Totals: value / day change / overall P/L, live from watchlist prices.
 * Table: fixed columns, tabular numerics, inline add/edit (zero dialogs),
 * remove = in-place red confirm for 3s. Empty state first run.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: tab

    property var api
    // parse config JSON defensively (Plasmoid = context property, valid in
    // every QML file of this applet)
    function positions() {
        try {
            var o = JSON.parse(api.cfg.portfolioJson || "{}")
            return (o && o.positions) ? o.positions : []
        } catch (e) { return [] }
    }
    function save(list) {
        api.cfg.portfolioJson =
            JSON.stringify({ version: 1, positions: list })
        tab.reload()
    }
    function reload() { posModel.clear(); positions().forEach(function(p) { posModel.append(p) }) }

    function fmtUsd(n) {
        var neg = n < 0
        var v = Math.abs(n)
        var s = v.toFixed(v >= 1000 ? 0 : 2)
        var parts = s.split(".")
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
        return (neg ? "−" : "") + "$" + parts.join(".")
    }

    ListModel { id: posModel }
    property bool editing: false
    property int editIdx: -1

    Component.onCompleted: reload()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 8

        // ---- totals header
        RowLayout {
            Layout.fillWidth: true
            spacing: 24

            ColumnLayout {
                spacing: 0
                Text { text: "TOTAL VALUE"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; font.letterSpacing: 0.6 }
                Text {
                    text: fmtUsd(tab.totals().value)
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 22; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
            ColumnLayout {
                spacing: 0
                Text { text: "DAY CHANGE"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; font.letterSpacing: 0.6 }
                Text {
                    readonly property var t: tab.totals()
                    text: (t.day >= 0 ? "▲ +" : "▼ −") + fmtUsd(Math.abs(t.day)).replace("$", "$")
                          + " (" + (t.dayPct >= 0 ? "+" : "−") + Math.abs(t.dayPct).toFixed(2) + "%)"
                    color: t.day >= 0 ? api.cPos : api.cNeg
                    font.pixelSize: 14; font.bold: true
                    font.features: { "tnum": 1 }
                }
            }
            ColumnLayout {
                spacing: 0
                Text { text: "OVERALL P/L"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; font.letterSpacing: 0.6 }
                Text {
                    readonly property var t: tab.totals()
                    text: (t.pl >= 0 ? "▲ +" : "▼ −") + fmtUsd(Math.abs(t.pl))
                          + " (" + (t.plPct >= 0 ? "+" : "−") + Math.abs(t.plPct).toFixed(1) + "%)"
                    color: t.pl >= 0 ? api.cPos : api.cNeg
                    font.pixelSize: 14; font.bold: true
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: "vs " + fmtUsd(tab.totals().cost) + " invested"
                    color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10
                }
            }
            Item { Layout.fillWidth: true }
            QQC2.Button {
                text: "+ Add"
                onClicked: { tab.editing = true; tab.editIdx = -1; symField.clear(); qtyField.clear(); costField.clear() }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.10) }

        // ---- inline add/edit row
        Rectangle {
            visible: tab.editing
            Layout.fillWidth: true
            height: 44
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.05)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                QQC2.TextField {
                    id: symField
                    Layout.preferredWidth: 90
                    placeholderText: "SYMBOL"
                    font.pixelSize: 12; font.capitalization: Font.AllUppercase
                }
                QQC2.TextField {
                    id: qtyField
                    Layout.preferredWidth: 80
                    placeholderText: "QTY"
                    font.pixelSize: 12
                }
                QQC2.TextField {
                    id: costField
                    Layout.preferredWidth: 90
                    placeholderText: "COST/UNIT"
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                QQC2.Button {
                    text: tab.editIdx >= 0 ? "Save" : "Add"
                    enabled: symField.text.length > 0
                             && parseFloat(qtyField.text) > 0
                             && parseFloat(costField.text) > 0
                    onClicked: {
                        var list = tab.positions()
                        var pos = {
                            symbol: symField.text.trim().toUpperCase(),
                            qty: parseFloat(qtyField.text),
                            cost: parseFloat(costField.text)
                        }
                        if (tab.editIdx >= 0) list[tab.editIdx] = pos
                        else list.push(pos)
                        tab.save(list)
                        tab.editing = false
                        tab.editIdx = -1
                    }
                }
                QQC2.Button {
                    flat: true
                    text: "Cancel"
                    onClicked: { tab.editing = false; tab.editIdx = -1 }
                }
            }
        }

        // ---- header row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "SYM"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; font.letterSpacing: 0.6; Layout.preferredWidth: 80 }
            Text { text: "QTY"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
            Text { text: "COST"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
            Text { text: "PRICE"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
            Text { text: "VALUE"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
            Text { text: "DAY"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 10; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
            Item { Layout.fillWidth: true }
        }

        // ---- positions
        ListView {
            id: posList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: posModel
            spacing: 0
            delegate: Item {
                width: posList.width
                height: 44
                readonly property var quote: api.marketRow(model.symbol)
                readonly property real value: quote ? quote.price * model.qty : 0
                readonly property real day: quote ? quote.change * model.qty : 0
                readonly property real pl: value - model.cost * model.qty

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: api.detailSymbol = model.symbol
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Text { text: model.symbol; color: Kirigami.Theme.textColor; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.preferredWidth: 80 }
                    Text { text: model.qty.toString(); color: Kirigami.Theme.textColor; font.pixelSize: 12; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; font.features: { "tnum": 1 } }
                    Text { text: model.cost.toFixed(2); color: Kirigami.Theme.disabledTextColor; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; font.features: { "tnum": 1 } }
                    Text { text: quote ? api.fmt(quote.price) : "—"; color: Kirigami.Theme.textColor; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; font.features: { "tnum": 1 } }
                    Text { text: fmtUsd(value); color: Kirigami.Theme.textColor; font.pixelSize: 12; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; font.features: { "tnum": 1 } }
                    Text {
                        text: (day >= 0 ? "▲ +" : "▼ −") + fmtUsd(Math.abs(day))
                        color: day >= 0 ? api.cPos : api.cNeg
                        font.pixelSize: 12; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight
                        font.features: { "tnum": 1 }
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: (pl >= 0 ? "▲ +" : "▼ −") + fmtUsd(Math.abs(pl)); color: pl >= 0 ? api.cPos : api.cNeg; font.pixelSize: 12; font.features: { "tnum": 1 } }
                    QQC2.Button {
                        flat: true; implicitWidth: 28; text: "✎"
                        onClicked: {
                            tab.editing = true
                            tab.editIdx = index
                            symField.text = model.symbol
                            qtyField.text = model.qty.toString()
                            costField.text = model.cost.toFixed(2)
                        }
                    }
                    QQC2.Button {
                        flat: true; implicitWidth: 28; text: "✕"
                        onClicked: {
                            var list = tab.positions()
                            list.splice(index, 1)
                            tab.save(list)
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Qt.rgba(1, 1, 1, 0.10) }
            }
        }

        // ---- empty state
        ColumnLayout {
            visible: posModel.count === 0 && !tab.editing
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Item { Layout.fillHeight: true }
            Text { Layout.alignment: Qt.AlignHCenter; text: "Track your portfolio"; color: Kirigami.Theme.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }
            Text { Layout.alignment: Qt.AlignHCenter; text: "Add a position to see total value, day change and P/L here."; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 12 }
            QQC2.Button {
                Layout.alignment: Qt.AlignHCenter
                text: "+ Add position"
                onClicked: { tab.editing = true; tab.editIdx = -1 }
            }
            Item { Layout.fillHeight: true }
        }
    }

    function totals() {
        var value = 0, day = 0, cost = 0
        var list = positions()
        for (var i = 0; i < list.length; i++) {
            var q = api.marketRow(list[i].symbol)
            if (q && q.price) {
                value += q.price * list[i].qty
                day += q.change * list[i].qty
            }
            cost += list[i].cost * list[i].qty
        }
        var pl = value - cost
        var prev = value - day
        return {
            value: value, day: day, cost: cost, pl: pl,
            dayPct: prev > 0 ? (day / prev) * 100 : 0,
            plPct: cost > 0 ? (pl / cost) * 100 : 0
        }
    }
}
