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

    // ---- layer-shell contract ------------------------------------------------
    LayerShell.Window.layer: LayerShell.Window.Layer.Top
    LayerShell.Window.scope: "foyer"
    // unanchored Layer.Top overlay; on-demand keyboard, focused on show
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivity.OnDemand
    LayerShell.Window.activateOnShow: true

    // Esc at root = close (host duty; FoyerRoot never sees this as a state)
    Keys.onEscapePressed: bridge.hideRequested()

    // daemon → UI state channel (harness driver + tests)
    Connections {
        target: bridge
        function onGotoState(s) { foyerRoot.gotoState(s) }
    }

    FoyerRoot {
        id: foyerRoot
        objectName: "foyerRoot"
        anchors.centerIn: parent
    }
}
