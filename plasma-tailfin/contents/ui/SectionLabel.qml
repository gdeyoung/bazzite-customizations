import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V-6 section label: smallFont size, bold, ALL CAPS, letterSpacing 0.4,
// disabledTextColor. v0.3's 0.5·gu custom size was the microtype floor
// violation — nothing renders below smallFont anywhere in v0.4.
// NOTE: `font: Kirigami.Theme.smallFont` (whole-object bind) plus any
// `font.x:` member bind in the same object throws "Property has already
// been assigned a value" at load — so every member is bound individually
// off the theme font's pixelSize.
PC3.Label {
    property string rawText: ""

    Layout.fillWidth: true
    visible: rawText !== ""
    text: rawText.toUpperCase()
    color: Kirigami.Theme.disabledTextColor
    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.4
    elide: Text.ElideRight
    Layout.topMargin: Kirigami.Units.smallSpacing
}
