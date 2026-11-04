import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §R-2 type scale: section label — 0.5·gu bold, all-caps, muted, tracked.
// Source strings stay Title Case; the CAPS rendering happens here.
PC3.Label {
    property string rawText: ""

    Layout.fillWidth: true
    text: rawText.toUpperCase()
    color: Kirigami.Theme.disabledTextColor
    font.bold: true
    font.pixelSize: Kirigami.Units.gridUnit * 0.5
    font.letterSpacing: 0.4
    elide: Text.ElideRight
    topPadding: Kirigami.Units.smallSpacing
}
