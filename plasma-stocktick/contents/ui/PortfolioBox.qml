// Portfolio section: header + one row per position + totals.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model

ColumnLayout {
    id: pf
    property var quotes: ({})
    property string positions: ""
    property color cPos: Kirigami.Theme.positiveText
    property color cNeg: Kirigami.Theme.negativeText
    readonly property var calc: Model.portfolio(Model.parsePositions(positions), quotes)
    readonly property bool modelOk: calc.rows.length > 0
    spacing: 2

    PC3.Label {
        text: "Portfolio"
        font.bold: true; opacity: 0.7
    }
    Repeater {
        model: pf.calc.rows
        RowLayout {
            Layout.fillWidth: true
            PC3.Label { text: modelData.sym; font.pixelSize: 12 }
            PC3.Label { text: "×" + modelData.qty; font.pixelSize: 10; opacity: 0.7 }
            Item { Layout.fillWidth: true }
            PC3.Label {
                Layout.alignment: Qt.AlignRight
                text: Model.fmtMoney(modelData.mkt); font.pixelSize: 12
            }
            PC3.Label {
                Layout.alignment: Qt.AlignRight
                text: Model.fmtPct(modelData.dayPl / (modelData.mkt - modelData.dayPl) * 100)
                font.pixelSize: 11; font.bold: true
                color: modelData.dayPl >= 0 ? pf.cPos : pf.cNeg
            }
        }
    }
    RowLayout {                                          // totals
        Layout.fillWidth: true
        PC3.Label { text: "Total"; font.bold: true }
        Item { Layout.fillWidth: true }
        PC3.Label {
            Layout.alignment: Qt.AlignRight
            text: Model.fmtMoney(pf.calc.totMkt); font.bold: true
        }
        PC3.Label {
            Layout.alignment: Qt.AlignRight
            text: Model.fmtMoney(pf.calc.totPl)
            font.bold: true
            color: pf.calc.totPl >= 0 ? pf.cPos : pf.cNeg
        }
    }
    PC3.Label {                                          // honesty row
        visible: !pf.calc.ok
        font.pixelSize: 10; opacity: 0.7
        text: "some symbols missing from the watchlist — add them to Symbols"
    }
}
