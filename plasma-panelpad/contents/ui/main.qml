/*
 * PanelPad — invisible fixed-width spacer for panel layouts.
 * Width from config (padWidth, default 48 px). No visuals, no click action:
 * it exists purely to put exact, scriptable space between widgets.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    compactRepresentation: Item {
        // The entire purpose: occupy exactly padWidth logical px.
        implicitWidth: Math.max(1, Plasmoid.configuration.padWidth || 48)
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2
    }

    // Never meaningfully opened (no click handler), but keep it valid.
    fullRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit
        implicitHeight: Kirigami.Units.gridUnit
    }
}
