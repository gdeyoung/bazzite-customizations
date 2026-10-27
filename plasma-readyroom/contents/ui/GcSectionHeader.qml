import QtQuick
import org.kde.kirigami as Kirigami

// Small bold section header. Port of PanelSectionHeader.
Text {
    color: Kirigami.Theme.textColor
    opacity: 0.7
    font.weight: Font.Bold
    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    elide: Text.ElideRight
}
