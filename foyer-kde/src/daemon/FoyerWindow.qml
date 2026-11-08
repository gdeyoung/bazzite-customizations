/*
 * FoyerWindow.qml — layer-shell host for FoyerRoot (user-space build).
 *
 * This is the ONLY host glue in the user-space path: a frameless, centered
 * Layer.Top surface with on-demand keyboard interactivity — the exact window
 * contract the design brief pinned (R1.2: no compilation, no rpm-ostree).
 * FoyerRoot stays host-agnostic; Esc→hide is a HOST duty (fork DNA: Esc at
 * root closes), so it lives here, not in FoyerRoot.
 */
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: win

    objectName: "foyerWindow"
    // kwin assigns the layer surface the full output; the CARD is 920x640
    // centered inside it (fullscreen-launcher geometry: whole-screen input
    // + focus, card floats). Do not fight the compositor for a small surface.
    visible: false
    color: "transparent"

    // ---- layer-shell contract (flat enum members — see qmldir qmltypes) -----
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.scope: "foyer"
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    // Window is not an Item — Keys must live on a focusable child
    Item {
        objectName: "foyerSurface"
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: bridge.hideRequested()

        // daemon → UI state channel (harness driver + tests)
        Connections {
            target: bridge
            function onGotoState(s) { foyerRoot.gotoState(s) }
        }

        // Center on the PRIMARY screen, not the combined virtual desktop —
        // on multi-monitor setups kwin assigns the layer surface the full
        // combined output and plain centerIn: parent would straddle the seam.
        // Python computes the offset once at startup (bridge.cardOffsetX).
        FoyerRoot {
            id: foyerRoot
            objectName: "foyerRoot"
            x: (parent.width - width) / 2 + bridge.cardOffsetX
            y: (parent.height - height) / 2
        }
    }
}
