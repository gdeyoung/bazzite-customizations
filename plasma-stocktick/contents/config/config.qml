import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: configPage
    property string cfg_symbols
    property string cfg_primary
    property int cfg_refreshMin

    Kirigami.FormLayout {
        QQC2.TextField {
            Kirigami.formData.label: "Symbols (comma-separated, Yahoo format):"
            text: cfg_symbols
            onTextEdited: cfg_symbols = text
            placeholderText: "MSFT,ESTC,BTC-USD,ETH-USD,XRP-USD,VOO,SCHD"
        }
        QQC2.TextField {
            Kirigami.formData.label: "Primary (chip + hero):"
            text: cfg_primary
            onTextEdited: cfg_primary = text
            placeholderText: "MSFT"
        }
        QQC2SpinBox {
            Kirigami.formData.label: "Refresh (minutes):"
            from: 1; to: 120
            value: cfg_refreshMin
            onValueModified: cfg_refreshMin = value
        }
        QQC2.Label {
            text: "Data: Yahoo Finance chart API — keyless, near-real-time.\n"
                  + "Indices use the caret form (^GSPC, ^NDX). Click a row in the\n"
                  + "popup to inspect it; the hero shows a 3-month sparkline."
            font.pixelSize: 10
            opacity: 0.7
        }
    }
}
