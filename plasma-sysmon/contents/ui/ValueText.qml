import QtQuick
import org.kde.kirigami as Kirigami

// ValueText — 14px semibold tabular numerals (spec typography: value tier).
Text {
    color: Kirigami.Theme.textColor
    font.pixelSize: 14
    font.weight: Font.DemiBold
    font.features: ({ "tnum": 1 })
}
