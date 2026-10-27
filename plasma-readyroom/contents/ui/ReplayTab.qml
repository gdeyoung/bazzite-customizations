import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Replay tab: arm/disarm the gpu-screen-recorder ring buffer, save the last
// N seconds, recent clips. Port of replay/ReplayTab.qml minus the Hyprland
// keybind editor (gc-binds is Hyprland-only; KDE custom shortcuts can call
// gc-replay save directly — README documents it).
ColumnLayout {
    id: root

    property var replay: null          // gc-replay status object
    property var clips: []             // gc-replay clips array
    property int replaySeconds: 300
    property var cfg: null             // write-back sink {seconds,storage,quality,audio}
    property var armTap: function() {}
    property var disarmTap: function() {}
    property var saveTap: function() {}
    property var openTap: function(path) {}

    spacing: Kirigami.Units.largeSpacing

    readonly property bool ready: replay !== null
    readonly property bool armed: replay ? !!replay.armed : false
    readonly property string replayError: replay ? String(replay.error || "") : ""
    readonly property int clipCount: clips ? clips.length : 0

    readonly property string replayStorage: cfg ? String(cfg.replayStorage) : "disk"
    readonly property string replayQuality: cfg ? String(cfg.replayQuality) : "balanced"

    // kbps × seconds ÷ 8 is the payload; the encoder's working set is a large
    // fixed cost on top of it. Same arithmetic as gc-replay's preflight.
    readonly property int estimateMb: {
        if (!ready) return 0
        var kbps = replay.activeKbps > 0 ? replay.activeKbps : 26000
        return Math.round(kbps * root.replaySeconds / 8 / 1024) + 400
    }

    // --------------------------------------------------------- state row

    GcToggle {
        Layout.fillWidth: true
        label: root.armed ? "Replay buffer running" : "Replay buffer"
        description: {
            var r = root.replay
            if (!r) return ""
            if (r.busy) return "working…"
            if (root.armed)
                return "holding the last " + root.replaySeconds + "s of "
                    + (r.activeMonitor || "the display") + " · ~" + root.estimateMb + "MB"
            return "keeps the last " + root.replaySeconds
                + "s so you can save it after it happens"
        }
        checked: root.armed
        tap: function() { root.armed ? root.disarmTap() : root.armTap() }
    }

    GcButton {
        Layout.fillWidth: true
        text: "Save the last "
            + (root.replaySeconds > 0 ? root.replaySeconds : 30) + " seconds"
        enabled: root.armed
        opacity: root.armed ? 1.0 : 0.4
        tap: function() { root.saveTap() }
    }

    Text {
        Layout.fillWidth: true
        visible: root.armed
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
        text: "Buffer running. Changes below apply the next time it starts."
    }

    GcSeparator { Layout.fillWidth: true }

    // --------------------------------------------------------- settings

    GcSectionHeader { Layout.fillWidth: true; text: "Buffer length" }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: [{ value: 60, label: "1m" }, { value: 300, label: "5m" },
                    { value: 600, label: "10m" }, { value: 900, label: "15m" }]

            GcPill {
                id: lenPill
                required property var modelData
                text: modelData.label
                active: root.replaySeconds === modelData.value
                tap: function() { if (root.cfg) root.cfg.setReplay("seconds", modelData.value) }
            }
        }
        Item { Layout.fillWidth: true }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 2

        Repeater {
            model: [
                { prop: "quality", label: "Quality",
                  values: ["low", "balanced", "high", "ultra"] },
                { prop: "storage", label: "Storage", values: ["disk", "ram"] }
            ]

            ColumnLayout {
                id: cfgRow
                required property var modelData
                spacing: Kirigami.Units.smallSpacing / 2

                Text {
                    text: cfgRow.modelData.label
                    color: Kirigami.Theme.textColor
                    opacity: 0.55
                    font: Kirigami.Theme.smallFont
                }
                GcPill {
                    text: "‹ " + (root.cfg ? String(root.cfg["replay" +
                        (cfgRow.modelData.prop === "quality" ? "Quality" : "Storage")]) : "…") + " ›"
                    tap: function() {
                        if (!root.cfg) return
                        var vals = cfgRow.modelData.values
                        var key = "replay" + (cfgRow.modelData.prop === "quality"
                            ? "Quality" : "Storage")
                        var i = vals.indexOf(String(root.cfg[key]))
                        if (i < 0) i = 0
                        root.cfg.setReplay(cfgRow.modelData.prop,
                                           vals[(i + 1) % vals.length])
                    }
                }
            }
        }
        Item { Layout.fillWidth: true }
    }

    Text {
        Layout.fillWidth: true
        visible: root.replaySeconds >= 600 && root.replayStorage === "ram"
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        opacity: 0.9
        font: Kirigami.Theme.smallFont
        text: "A " + (root.replaySeconds / 60) + "-minute buffer in RAM costs "
            + Math.round(root.estimateMb / 1024)
            + "GB held for the whole session. Prefer disk storage unless you have headroom."
    }

    GcSeparator { Layout.fillWidth: true }

    // --------------------------------------------------------- clips

    GcSectionHeader { Layout.fillWidth: true; text: "Recent clips" }

    Text {
        Layout.fillWidth: true
        visible: root.clipCount === 0
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
        text: "No clips yet."
    }

    Repeater {
        model: Math.min(root.clipCount, 6)

        RowLayout {
            id: clipRow
            required property int index
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            readonly property var clip: root.clips ? root.clips[index] : null

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: clipRow.clip ? clipRow.clip.name : ""
                    color: Kirigami.Theme.textColor
                    font: Kirigami.Theme.smallFont
                }
                Text {
                    Layout.fillWidth: true
                    text: clipRow.clip
                        ? Math.max(1, Math.round(clipRow.clip.size / 1048576)) + "MB"
                          + " · " + new Date(clipRow.clip.mtime * 1000)
                              .toLocaleString(Qt.locale(), "d MMM HH:mm")
                        : ""
                    color: Kirigami.Theme.textColor
                    opacity: 0.5
                    font: Kirigami.Theme.smallFont
                }
            }

            GcPill {
                text: "open"
                linkStyle: true
                tap: function() { if (clipRow.clip) root.openTap(clipRow.clip.path) }
            }
        }
    }

    // --------------------------------------------------------- footer

    Text {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        color: root.replayError !== "" ? Kirigami.Theme.negativeTextColor
                                       : Kirigami.Theme.textColor
        opacity: root.replayError !== "" ? 1.0 : 0.6
        font: Kirigami.Theme.smallFont
        text: {
            var r = root.replay
            if (!r) return "starting…"
            if (r.error && r.error !== "") return r.error
            if (r.stockRecording)
                return "A screen recording is also running — both share the GPU encoder."
            return root.armed ? "Buffer running." : ""
        }
    }
}
