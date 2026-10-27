import QtQuick
import org.kde.plasma.components as PC3

// Generic row action button: icon (IconOnly) or text (TextOnly), optional
// tooltip, emits `activated`. One control, one onClicked handler in this
// file — port law: a handler name may appear at most once per file, so
// every clickable in this widget funnels through this component and rows
// dispatch on a key (see DriveRow/CloudRowItem).
PC3.ToolButton {
    id: btn

    property string iconName: ""
    property string tooltipText: ""

    signal activated()

    icon.name: iconName
    display: iconName !== "" ? PC3.ToolButton.IconOnly : PC3.ToolButton.TextOnly
    PC3.ToolTip.text: tooltipText
    PC3.ToolTip.visible: hovered && tooltipText !== ""

    onClicked: btn.activated()
}
