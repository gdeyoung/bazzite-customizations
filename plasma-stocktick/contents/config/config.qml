import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: configPage
    property string cfg_symbols
    property string cfg_primary
    property string cfg_positions
    property int cfg_refreshMin

    Kirigami.FormLayout {
        QQC2TextField {
            Kirigami.formData.label: "Symbols (comma-separated, Stooq format):"
            text: cfg_symbols
            onTextEdited: cfg_symbols = text
            placeholderText: "SPY.US,QQQ.US,AAPL.US"
        }
        QQC2TextField {
            Kirigami.formData.label: "Primary (chip + hero):"
            text: cfg_primary
            onTextEdited: cfg_primary = text
            placeholderText: "SPY.US"
        }
        QQC2SpinBox {
            Kirigami.formData.label: "Refresh (minutes):"
            from: 1; to: 120
            value: cfg_refreshMin
            onValueModified: cfg_refreshMin = value
        }
        QQC2TextArea {
            Kirigami.formData.label: "Positions (optional, one per line SYM:QTY:COST):"
            Layout.preferredWidth: 320
            Layout.preferredHeight: 96
            text: cfg_positions
            onTextChanged: cfg_positions = text
            placeholderText: "AAPL.US:100:182.40"
        }
        QQC2.Label {
            text: "Data: Yahoo Finance chart API — keyless, near-real-time.\n"
                  + "Indices use the caret form (^GSPC, ^NDX)."
            font.pixelSize: 10
            opacity: 0.7
        }
    }
}
