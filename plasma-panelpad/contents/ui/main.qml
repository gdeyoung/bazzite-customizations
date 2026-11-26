/*
 * PanelPad — invisible fixed-width spacer for panel layouts.
 * Width from config (padWidth, default 48 px). No visuals, no click action:
 * it exists purely to put exact, scriptable space between widgets.
 *
 * Sizing: Plasma 6.7 panel containers do NOT size a compactRepresentation
 * from implicitWidth alone (verified the hard way: a bare Item collapses to
 * a default ~34px square cell and ignores config). Set width + implicitWidth
 * + Layout.preferred/minimum together, vpsone stock-monitor pattern.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    compactRepresentation: MouseArea {
        id: pad

        // One source of truth for the width.
        readonly property real w: Math.max(1, Plasmoid.configuration.padWidth || 48)

        width: w
        implicitWidth: w
        Layout.preferredWidth: w
        Layout.minimumWidth: w

        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2
        // Deliberately no visual children and no click behavior: this
        // widget occupies space, nothing more. MouseArea root (not bare
        // Item) so the container treats it as a normal compact chip.
    }

    // Never meaningfully opened, but keep it valid.
    fullRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit
        implicitHeight: Kirigami.Units.gridUnit
    }
}
