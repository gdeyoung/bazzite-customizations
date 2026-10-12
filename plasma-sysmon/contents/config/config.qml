import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 1
            to: 10
            value: cfg_refreshSeconds
            onValueModified: cfg_refreshSeconds = value
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Bar layout:")
            model: [
                { value: "compact", text: i18n("Compact — letters + level bars") },
                { value: "values", text: i18n("Values — full readouts") }
            ]
            textRole: "text"
            currentIndex: cfg_barMode === "values" ? 1 : 0
            onActivated: function(index) {
                cfg_barMode = index === 1 ? "values" : "compact"
            }
        }
    }
}
