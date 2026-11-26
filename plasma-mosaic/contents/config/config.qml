import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.kcmutils as KCM

// plasma-mosaic v0.1 settings (spec §I): hero accent color + donut toggle.
KCM.SimpleKCM {
    id: config

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        PC3.CheckBox {
            Kirigami.FormData.label: "Overview:"
            text: "Show category donut"
            checked: config.cfg_showDonut !== false
            onCheckedChanged: config.cfg_showDonut = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Hero accent:"
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
                width: 16
                height: 16
                radius: 3
                color: config.cfg_heroAccentColor
                border.color: Kirigami.Theme.textColor
                border.width: 1
            }
            PC3.TextField {
                Layout.preferredWidth: 120
                placeholderText: "#58a6ff"
                text: config.cfg_heroAccentColor
                onTextChanged: if (/^#[0-9a-fA-F]{6}$/.test(text)) config.cfg_heroAccentColor = text
            }
        }
        Kirigami.Label {
            text: "Hex color (e.g. #58a6ff). Applies to the overview hero total."
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
