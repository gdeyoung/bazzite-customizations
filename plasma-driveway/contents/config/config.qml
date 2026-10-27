import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

// Driveway settings — maps the Omarchy plugin's GeneralSettings.qml onto a
// KConfig XT page (cfg_* keys mirror contents/config/main.xml).
KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Refresh interval while closed (seconds):")
            from: 2
            to: 300
            value: cfg_pollIntervalSec
            onValueModified: cfg_pollIntervalSec = value
        }
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Drives tab:")
            text: i18n("Show network shares and cloud drives")
            checked: cfg_showNetwork
            onToggled: cfg_showNetwork = checked
        }
        QQC2.CheckBox {
            text: i18n("Show plugged-in but unmounted drives")
            checked: cfg_showUnmounted
            onToggled: cfg_showUnmounted = checked
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Thumb drive size limit (GB):")
            from: 8
            to: 4096
            stepSize: 8
            value: cfg_thumbMaxGb
            onValueModified: cfg_thumbMaxGb = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Hide unmounted partitions under (MB):")
            from: 0
            to: 4096
            stepSize: 16
            value: cfg_minUnmountedMb
            onValueModified: cfg_minUnmountedMb = value
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Nearly full at (%):")
            from: 50
            to: 100
            value: cfg_fullWarnPct
            onValueModified: cfg_fullWarnPct = value
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Glyph font family (blank = default):")
            text: cfg_glyphFontFamily
            onTextEdited: cfg_glyphFontFamily = text
            placeholderText: i18n("e.g. Noto Sans Nerd Font")
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("rclone remotes to show (blank = all):")
            text: cfg_cloudRemotes
            onTextEdited: cfg_cloudRemotes = text
            placeholderText: i18n("gdrive-personal, plexdrive")
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("LUKS unlock terminal command:")
            text: cfg_unlockCommand
            onTextEdited: cfg_unlockCommand = text
        }
    }

    QQC2.Label {
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: i18n("Shares (host-specific inventory — kept here, not in the repo). " +
                   "JSON array of {\"id\",\"label\",\"url\",\"mountpoint\",\"scheme\",\"fstype\",\"mountCommand\"}. " +
                   "Mounted/unmounted state is read live from mount tables; " +
                   "mountpoint matches the lister row exactly.")
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
    }
    QQC2.TextField {
        id: sharesField
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing * 2
        text: cfg_sharesJson
        onTextEdited: cfg_sharesJson = text
        placeholderText: i18n('[{"id":"nas-media","label":"NAS media","url":"smb://nas/media","mountpoint":"/run/user/1000/gvfs/smb-share:server=nas,share=media","scheme":"smb","fstype":"SMB"}]')
        font: Kirigami.Theme.smallFont
        wrapMode: TextEdit.WordWrap
    }
    QQC2.Label {
        visible: sharesField.text.length > 0 && !validJson
        text: i18n("Not valid JSON — share rows will be empty until fixed.")
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
        property bool validJson: {
            try { JSON.parse(sharesField.text); return true } catch (e) { return false }
        }
    }
}
