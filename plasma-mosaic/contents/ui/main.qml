import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support 2.0
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// com.gdeyoung.plasma.mosaic — Plasma 6 port of naolselemon/mosaic
// (Omarchy app-storage explorer). Engine vendored byte-identical under
// contents/lib/mosaic; this layer is Plasma-native QML driven by the
// host CLI (contents/scripts/mosaic) over the plasma5support executable
// dataengine — no resident daemon, scans are explicit + single-flight,
// the popup opens instantly from the cached snapshot.
PlasmoidItem {
    id: root

    // ---- config (KConfigXT; defaults mirror main.xml) --------------------
    readonly property bool cfgShowDonut: Plasmoid.configuration.showDonut !== false
        && Plasmoid.configuration.showDonut !== "false"
    readonly property string cfgHeroAccent: Plasmoid.configuration.heroAccentColor || "#58a6ff"

    Component.onCompleted: {
        Plasmoid.toolTipMainText = "Mosaic"
        Plasmoid.toolTipSubText = "Click to see what each application stores"
        Plasmoid.toolTipTextFormat = 0
    }

    // =========================================================================
    // COMPACT (panel chip): glyph + mapped total — states in Chip.qml (§C)
    // =========================================================================
    compactRepresentation: Chip {
        applet: root
    }

    // Sizing hints live ONLY on the popup root (MosaicPopup, spec §A).
    fullRepresentation: MosaicPopup {
        cfgShowDonut: root.cfgShowDonut
        cfgHeroAccent: root.cfgHeroAccent
    }
}
