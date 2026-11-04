import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V-3/§V-8 search row: edit-find icon + TextField (placeholder
// `Search peers`) + trailing ✕ clear (visible iff text non-empty).
// Ctrl+F (popup focused) → focus + select-all; Esc → clear if non-empty,
// else blur. The popup wires those keys — this row renders and syncs the
// ctx.peerQuery property (the single source of truth, so programmatic
// clears — Esc, popup close — and typing stay in one place).
RowLayout {
    id: searchRow

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    property var field: queryField   // exposed for focus()/selectAll() calls

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.9
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.7
        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.7
        source: "edit-find"
        color: Kirigami.Theme.disabledTextColor
        isMask: true
    }

    PC3.TextField {
        id: queryField
        Layout.fillWidth: true
        placeholderText: i18n("Search peers")
        text: searchRow.ctx.peerQuery
        onTextChanged: {
            if (text !== searchRow.ctx.peerQuery) {
                searchRow.ctx.peerQuery = text
            }
        }
        font: Kirigami.Theme.smallFont
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
    }

    PC3.ToolButton {
        visible: searchRow.ctx.peerQuery !== ""
        flat: true
        icon.name: "edit-clear-all"
        display: PC3.AbstractButton.IconOnly
        QQC2.ToolTip.text: i18n("Clear search")
        QQC2.ToolTip.visible: hovered
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
        onClicked: {
            searchRow.ctx.peerQuery = ""
            queryField.forceActiveFocus()
        }
    }

    // External updates (Esc, popup close, ✕) land without recursion.
    Connections {
        target: searchRow.ctx
        function onPeerQueryChanged() {
            const q = searchRow.ctx.peerQuery
            if (queryField.text !== q) queryField.text = q
        }
    }
}
