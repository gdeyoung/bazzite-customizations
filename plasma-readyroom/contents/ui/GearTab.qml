import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Gear tab: GPU summary (one-shot gc-stats via gc-gear-stats), MangoHud
// profile switcher (gc-mangohud), and desk-gear batteries (gc-gear-probe).
// Port of controllers/GearTab.qml + the MangoHud part of overlay/.
ColumnLayout {
    id: root

    property var gear: null            // gc-gear-probe rows
    property var stats: null           // gc-gear-stats {hello, first}
    property bool busy: false
    property var mh: null              // {position,cpu,gpu,ram,vram,temps,power}
    property var mangohudTap: function() {}

    spacing: Kirigami.Units.largeSpacing

    // --------------------------------------------------------- GPU summary

    GcSectionHeader { Layout.fillWidth: true; text: "GPU" }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing / 2

        Repeater {
            model: [
                { label: "GPU", kind: "gpu" },
                { label: "VRAM", kind: "vram" },
                { label: "CPU", kind: "cpu" },
                { label: "RAM", kind: "ram" }
            ]

            RowLayout {
                id: statRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: statRow.modelData.label
                    color: Kirigami.Theme.textColor
                    opacity: 0.55
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                Text {
                    Layout.alignment: Qt.AlignRight
                    horizontalAlignment: Text.AlignRight
                    text: root.statLine(statRow.modelData.kind)
                    color: Kirigami.Theme.textColor
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }

    // --------------------------------------------------------- MangoHud

    GcSectionHeader { Layout.fillWidth: true; text: "MangoHud profile" }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
        text: "Writes the same metrics and corner into a managed block of MangoHud.conf — everything outside the block stays yours. FPS still needs `mangohud %command%` in the game's launch options."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: "Corner"
            color: Kirigami.Theme.textColor
            opacity: 0.55
            font: Kirigami.Theme.smallFont
        }
        Item { Layout.fillWidth: true }
        GcPill {
            text: "‹ " + (root.mh ? root.mh.position : "top-left") + " ›"
            tap: function() {
                if (!root.mh) return
                var vals = ["top-left", "top-right", "bottom-left", "bottom-right"]
                var i = vals.indexOf(root.mh.position)
                if (i < 0) i = 0
                root.mh.position = vals[(i + 1) % vals.length]
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: [
                { prop: "cpu", label: "CPU" }, { prop: "gpu", label: "GPU" },
                { prop: "ram", label: "RAM" }, { prop: "vram", label: "VRAM" },
                { prop: "temps", label: "Temp" }, { prop: "power", label: "W" }
            ]

            GcPill {
                id: metricPill
                required property var modelData
                text: modelData.label
                active: root.mh ? root.mh[modelData.prop] === true : false
                tap: function() {
                    if (root.mh)
                        root.mh[modelData.prop] = !root.mh[modelData.prop]
                }
            }
        }
        Item { Layout.fillWidth: true }
    }

    GcButton {
        Layout.fillWidth: true
        enabled: !root.busy
        opacity: root.busy ? 0.5 : 1.0
        text: root.busy ? "Writing…" : "Apply MangoHud profile"
        tap: function() { root.mangohudTap() }
    }

    GcSeparator { Layout.fillWidth: true }

    // --------------------------------------------------------- gear rows

    GcSectionHeader { Layout.fillWidth: true; text: "Desk gear batteries" }

    GcEmptyState {
        Layout.fillWidth: true
        visible: root.gearReady && root.gearCount === 0
        glyph: "\uF0750"
        title: "No battery gear found"
        detail: "Mice, keyboards and headsets with batteries appear here when paired."
    }

    Repeater {
        model: root.gearCount

        RowLayout {
            id: gearRow
            required property int index
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            readonly property var device: root.gear ? root.gear[index] : null
            readonly property bool low: device && device.level !== null
                && device.level !== undefined && device.level <= 20
            readonly property string levelText: {
                if (!device) return ""
                if (device.level === null || device.level === undefined)
                    return device.charging === true ? "charging" : "—"
                var suffix = device.charging === true ? " \uF0084" : ""
                return device.level + "%" + suffix
            }

            Text {
                text: root.kindGlyph(gearRow.device)
                font.family: "Symbols Nerd Font"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.textColor
                opacity: 0.75
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: gearRow.device ? gearRow.device.name : ""
                color: Kirigami.Theme.textColor
                font: Kirigami.Theme.smallFont
            }

            Text {
                text: gearRow.levelText
                color: gearRow.low ? Kirigami.Theme.negativeTextColor
                                   : Kirigami.Theme.textColor
                opacity: gearRow.low ? 1.0 : 0.8
                font: Kirigami.Theme.smallFont
            }
        }
    }

    // --------------------------------------------------------- helpers

    readonly property bool gearReady: gear !== null
    readonly property int gearCount: gearReady ? gear.length : 0

    function statLine(kind) {
        if (!stats) return "…"
        var h = stats.hello || {}
        var s = stats.first || {}
        if (kind === "gpu") {
            var name = h.gpu === "nvidia" ? "NVIDIA" : (h.gpu === "amd" ? "AMD" : "")
            var g = s.gpu || {}
            var bits = []
            if (g.percent !== undefined && g.percent !== null) bits.push(g.percent + "%")
            if (g.temp !== undefined && g.temp !== null) bits.push(g.temp + "°C")
            if (g.watts !== undefined && g.watts !== null) bits.push(g.watts + "W")
            if (bits.length) return (name ? name + " " : "") + bits.join(" · ")
            return name || "—"
        }
        if (kind === "vram") {
            var g2 = s.gpu || {}
            if (g2.vramUsedMb === undefined || g2.vramUsedMb === null) return "—"
            return g2.vramUsedMb + " / " + g2.vramTotalMb + " MB"
        }
        if (kind === "cpu") {
            var c = s.cpu || {}
            if (c.percent === undefined) return "—"
            var out = c.percent + "%"
            if (c.temp !== undefined && c.temp !== null) out += " · " + c.temp + "°C"
            return out
        }
        if (kind === "ram") {
            var r = s.ram
            if (!r) return "—"
            return r.percent + "% · " + r.usedMb + "/" + r.totalMb + "MB"
        }
        return "—"
    }

    function kindGlyph(device) {
        if (!device) return ""
        var map = {
            mouse: "\uF037D", keyboard: "\uF030C", headset: "\uF02CB",
            earbuds: "\uF0949", gamepad: "\uF02B4", phone: "\uF011B",
            tablet: "\uF011C", watch: "\uF095A"
        }
        return map[device.kind] !== undefined ? map[device.kind] : "\uF0092"
    }
}
