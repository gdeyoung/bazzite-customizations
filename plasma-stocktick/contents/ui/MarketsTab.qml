/*
 * MarketsTab — 3×2 grid of macro/index cards (spec C).
 * Row 1 risk assets: ^GSPC ^IXIC ^DJI · Row 2 macro/fear: ^TNX ^VIX BTC-USD
 * Card: micro-caps label → value 22px semibold tabular → arrow+delta →
 * spark 60×28. White 5% fill, radius 8, hover 8%, click → detail.
 * ^TNX special: yield % display, delta in basis points.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: tab

    property var api                    // root of main.qml
    property var cardModel: null        // ListModel with role fields

    GridLayout {
        anchors.fill: parent
        anchors.margins: 20
        columns: 3
        columnSpacing: 12
        rowSpacing: 12

        Repeater {
            model: tab.cardModel

            Rectangle {
                readonly property bool isTnx: symbol === "^TNX"
                // bind to model ROLES (price/change/pct/series) — they
                // notify on model.set(). A marketRow() function call here
                // created no binding dependency, so cards froze at their
                // empty creation state ("—", no spark) even after fetch.
                readonly property real raw: model.price
                readonly property real delta: model.change
                readonly property real pctv: model.pct
                readonly property var pts: model.series

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                                        : Qt.rgba(1, 1, 1, 0.05)

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: api.detailSymbol = symbol
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 2

                    Text {
                        text: label
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 10
                        font.letterSpacing: 0.6
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: {
                            if (raw <= 0) return "—"
                            if (isTnx)
                                return (raw < 25 ? raw : raw / 10).toFixed(2) + "%"
                            return api.fmt(raw)
                        }
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        text: {
                            if (raw <= 0 || isNaN(delta)) return ""
                            var up = delta >= 0
                            var arrow = up ? "▲" : "▼"
                            if (isTnx)
                                return arrow + (up ? "+" : "−")
                                       + Math.abs(delta * (raw < 25 ? 100 : 10)).toFixed(1) + "bp"
                            return arrow + (up ? "+" : "−")
                                   + Math.abs(pctv).toFixed(2) + "%"
                        }
                        color: raw > 0 && delta >= 0 ? api.cPos : api.cNeg
                        font.pixelSize: 12
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                    Item { Layout.fillHeight: true }
                    Sparkline {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignLeft | Qt.AlignBottom
                        points: pts
                        lineColor: delta >= 0 ? api.cPos : api.cNeg
                    }
                }
            }
        }
    }

    Text {
        // empty / first-paint state: cards exist as skeletons via "—" data
        visible: !tab.cardModel || tab.cardModel.count === 0
        anchors.centerIn: parent
        text: "loading markets…"
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: 12
    }
}
