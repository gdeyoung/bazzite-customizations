import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Status poll interval (seconds):")
            from: 5
            to: 3600
            value: cfg_interval
            onValueModified: cfg_interval = value
        }
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Offline devices:")
            text: i18n("Show offline devices in the list (default: collapsed behind a count)")
            checked: cfg_showOffline
            onToggled: cfg_showOffline = checked
        }
    }
}
