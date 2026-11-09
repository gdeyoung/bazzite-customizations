/*
 * FoyerWindow.qml — layer-shell host for FoyerRoot (user-space build).
 *
 * Host glue only (R1.2 contract): Layer.Top surface, keyboard, centering,
 * scaling, and THEME PINNING. FoyerRoot stays host-agnostic.
 *
 * Live-session lessons baked in (2026-11-07, gdtower):
 *  - KeyboardInteractivityOnDemand never delivers keys to a plain layer
 *    surface under kwin → Exclusive while visible (Esc/arrows/typing).
 *  - Kirigami standalone resolves fallback tokens differently per env
 *    (kdeglobals may lack ColorScheme=) → pin the converged design tokens
 *    here; descendants inherit them, so the daemon renders identically to
 *    the harness regardless of ambient scheme state.
 *  - kwin assigns the full combined output; center on the primary screen
 *    (bridge.cardOffsetX) and scale the card on super-ultrawide panels
 *    (bridge.cardScale, 1.45× when aspect ≥ 2.6) — the 920×640 card was
 *    designed for 2560-wide screens and reads tiny on a 5120 panel.
 */
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami

Window {
    id: win

    objectName: "foyerWindow"
    visible: false
    color: "transparent"

    // ---- layer-shell contract (flat enum members — see qmldir qmltypes) -----
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.scope: "foyer"
    // Exclusive: the launcher owns the keyboard while visible (Esc closes,
    // arrows navigate, typing filters). OnDemand never granted keys on kwin.
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true

    // Window is not an Item — Keys must live on a focusable child
    Item {
        id: foyerSurface
        objectName: "foyerSurface"
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: foyerRoot.confirmArmed ? foyerRoot.disarmConfirm()
                                                     : bridge.hideRequested()

        // ---- pinned theme (converged v4 token table, CONVERGED-DESIGN.md).
        // Attached properties inherit to every descendant — deterministic in
        // any host; no ambient scheme resolution in the daemon.
        Kirigami.Theme.backgroundColor: "#232629"
        Kirigami.Theme.alternateBackgroundColor: "#31363b"
        Kirigami.Theme.textColor: "#fcfcfc"
        Kirigami.Theme.disabledTextColor: "#a1a9b1"
        Kirigami.Theme.highlightColor: "#1e92ff"
        Kirigami.Theme.hoverColor: "#3daee9"
        Kirigami.Theme.negativeTextColor: "#da4453"
        Kirigami.Theme.positiveTextColor: "#27ae60"
        Kirigami.Theme.neutralTextColor: "#f67400"
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        // Click on the dim area outside the card dismisses (mouse way out —
        // Esc stays the keyboard way out).
        MouseArea {
            id: dismissArea
            anchors.fill: parent
            z: 0
            onClicked: function(mouse) {
                var c = cardBox.mapToItem(foyerSurface, 0, 0)
                var inside = mouse.x >= c.x && mouse.x <= c.x + cardBox.width &&
                             mouse.y >= c.y && mouse.y <= c.y + cardBox.height
                if (!inside) bridge.hideRequested()
            }
        }

        // daemon → UI state channel (harness driver + tests)
        Connections {
            target: bridge
            function onGotoState(s) { foyerRoot.gotoState(s, true) }
            function onKeyDriven(k) { foyerRoot.navKey(k) }
        }

        // Card container: primary-screen center + ultrawide upscaling.
        // FoyerRoot renders at its designed 920×640 and is scaled as a whole
        // (transform scales hit-testing too, so clicks stay true).
        Item {
            id: cardBox
            objectName: "cardBox"
            z: 1
            opacity: bridge.cardOpacity / 100
            x: (parent.width - width) / 2 + bridge.cardOffsetX
            y: bridge.cardAnchor === "top" ? 48
             : bridge.cardAnchor === "bottom"
               ? parent.height - height - 48
               : (parent.height - height) / 2
            width: 920 * bridge.cardScale
            height: 640 * bridge.cardScale

            FoyerRoot {
                id: foyerRoot
                objectName: "foyerRoot"
                // Adaptive scale: structure follows cardScale fully (u);
                // type is clamped (t) so the hierarchy spreads at scale
                // instead of zooming. FoyerRoot sizes itself 920u × 640u.
                u: bridge.cardScale
                t: Math.min(bridge.cardScale, 1.18)
                appsJson: bridge.appsJson
            sshJson: bridge.sshJson
            recentsJson: bridge.recentsJson
            favsJson: bridge.favsJson
            fleetJson: bridge.fleetJson
            updateOut: bridge.updateOut   // live .desktop scan
            aiQuestion: bridge.aiQuestion
            aiStream: bridge.aiStream
            aiDone: bridge.aiDone
            aiModelName: bridge.aiModel
            recentJson: bridge.recentJson
            fuzzyOn: bridge.fuzzy
            cardAnchor: bridge.cardAnchor
                onLaunchApp: (exec) => bridge.launchRequested(exec)
                onSystemAction: (name) => bridge.systemActionRequested(name)
                onOpenSsh: (alias) => bridge.openSshRequested(alias)
                onRunUpdate: (which) => bridge.updateRunRequested(which)
                onProbeFleet: () => bridge.fleetProbeRequested()
                onAskHermes: (question) => bridge.askRequested(question)
                onAskCancel: () => bridge.askCancelRequested()
                onCopyText: (text) => bridge.copyRequested(text)
                onContinueChat: (question) => bridge.continueRequested(question)
                onSettingLever: (name) => bridge.settingChanged(name)
            }
        }
    }
}
