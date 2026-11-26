import QtQuick
import org.kde.kirigami as Kirigami

// MicroLabel — 10px CAPS tracking label (spec typography: micro tier).
Text {
    color: Kirigami.Theme.disabledTextColor
    font.pixelSize: 11
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
}
