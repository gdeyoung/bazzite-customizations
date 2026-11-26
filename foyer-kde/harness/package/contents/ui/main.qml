/*
 * main.qml — HARNESS HOST ONLY (never ships).
 * Loads the real src/qml/FoyerRoot.qml (assembled into this package) at
 * full 920x640 and drives its `state` from /tmp/foyer-state so the
 * harness bash can capture every UI state without synthetic input.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: shell

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // harness auto-open (the only working popup-open method; fires once,
    // 6s, after the applet is panel-ready)
    Timer {
        interval: 6000
        running: true
        onTriggered: {
            shell.expanded = true;
            console.error("HARNESS-POPUP-OPEN");
        }
    }

    fullRepresentation: Item {
        id: host
        property bool railProbeOn: false
        Layout.preferredWidth: 920
        Layout.preferredHeight: 640

        FoyerRoot {
            id: foyer
            anchors.fill: parent
        }

        // harness state driver (polls package-relative file; harmless if absent)
        Timer {
            interval: 250
            running: true
            repeat: true
            property string last: ""
            property bool first: true
            onTriggered: {
                if (first) { first = false; console.error("HARNESS-TIMER tick"); }
                var req = new XMLHttpRequest();
                req.open("GET", Qt.resolvedUrl("state.txt"), true);
                req.onreadystatechange = function () {
                    if (req.readyState === XMLHttpRequest.DONE) {
                        if (req.status === 0 || req.status === 200) {
                            var s = req.responseText.trim();
                            if (s.length > 0 && s !== last) {
                                last = s;
                                foyer.gotoState(s);
                                console.error("HARNESS-STATE " + s);
                            }
                        }
                    }
                };
                req.send();
            }
        }

        Component.onCompleted: {
            foyer.gotoState("boot");
            console.error("HARNESS-LOADED 920x640");
        }
        // post-theme-settle probe (theme resolves async in the applet context)
        Timer {
            interval: 8000; running: true
            onTriggered: console.error("HARNESS-TOKENS8 accent=" + foyer.cAccent + " pos=" + foyer.cPos +
                                       " neg=" + foyer.cNeg + " neutral=" + foyer.cWarn +
                                       " hover=" + foyer.cHover + " text=" + foyer.cText + " dim=" + foyer.cDim)
        }
        // rail structure probe (one-shot; answered R3 — kept off by default)
        Timer {
            interval: 9000; running: host.railProbeOn
            onTriggered: console.error("HARNESS-RAIL " + foyer.railProbe())
        }
    }
}
