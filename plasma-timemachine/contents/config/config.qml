import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 5
            to: 60
            value: cfg_refreshSeconds
            onValueModified: cfg_refreshSeconds = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Stale after (hours):")
            from: 1
            to: 168
            value: cfg_staleHours
            onValueModified: cfg_staleHours = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Failed after (hours):")
            from: 2
            to: 336
            value: cfg_failHours
            onValueModified: cfg_failHours = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("History window (days):")
            from: 3
            to: 90
            value: cfg_historyDays
            onValueModified: cfg_historyDays = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Rows per expanded day:")
            from: 5
            to: 50
            value: cfg_snapshotRows
            onValueModified: cfg_snapshotRows = value
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Engine conf path:")
            placeholderText: "~/.config/timemachine.conf"
            text: cfg_confPath
            onTextChanged: if (text !== cfg_confPath) cfg_confPath = text
        }
    }
}
