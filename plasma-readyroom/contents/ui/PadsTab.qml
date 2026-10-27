import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Pads tab: connected controllers with battery (segments vs percent), test
// rumble, bounded live-input sampling, claimed-pad sentences, dongle section.
// Port of controllers/PadsTab.qml; all verbs are callback properties.
ColumnLayout {
    id: root

    property var pads: null            // gc-pad-probe result object
    property string streamNode: ""     // node being sampled ("" = none)
    property var liveSample: null      // latest {b:{},a:{}} state line
    property string error: ""
    property var rumbleTap: function(node) {}
    property var streamTap: function(node) {}
    property var udevTap: function() {}

    spacing: Kirigami.Units.largeSpacing

    readonly property bool ready: pads !== null
    readonly property var padList: ready ? (pads.pads || []) : []
    readonly property int count: padList.length
    readonly property var claimed: ready ? (pads.claimed || []) : []
    readonly property var claimedFirst: claimed.length > 0 ? claimed[0] : null
    readonly property var dongle: ready && (pads.dongles || []).length > 0
        ? pads.dongles[0] : null

    // --------------------------------------------------------- empty state

    GcEmptyState {
        Layout.fillWidth: true
        visible: root.count === 0 && root.ready
        glyph: "\uF02B4"
        title: {
            if (root.claimedFirst === null) return "No controllers connected"
            if (root.claimed.length > 1) return root.claimed.length + " controllers are in use"
            if (root.claimedFirst.connection === "dongle")
                return root.claimedFirst.name + " adapter is in use"
            return root.claimedFirst.name + " is in use"
        }
        detail: {
            if (!root.ready) return ""
            if (root.claimedFirst !== null) {
                var c = root.claimedFirst
                var who = (c.holder && c.holder.name) ? c.holder.name : "another program"
                var subject = c.connection === "dongle"
                      ? "Its wireless adapter is open in "
                      : "It is open in "
                if (root.claimed.length > 1) subject = "They are open in "
                return subject + who + " — close that program and the controller comes back."
            }
            if (root.dongle)
                return "An Xbox Wireless Adapter is plugged in. Turn on a controller to connect one."
            if ((root.pads.drivers || []).length > 0)
                return "Drivers loaded: " + root.pads.drivers.join(", ") + "."
            return "Plug in a controller, or turn one on."
        }
    }

    // --------------------------------------------------------- the pads

    Repeater {
        model: root.padList

        ColumnLayout {
            id: padRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: padRow.modelData.name
                        color: Kirigami.Theme.textColor
                        font: Kirigami.Theme.defaultFont
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.padSubtitle(padRow.modelData)
                        color: Kirigami.Theme.textColor
                        opacity: 0.55
                        font: Kirigami.Theme.smallFont
                    }
                }

                BatterySegments {
                    visible: padRow.modelData.caps.batteryKind !== "none"
                    kind: padRow.modelData.caps.batteryKind
                    level: padRow.modelData.battery && padRow.modelData.battery.level
                        ? padRow.modelData.battery.level : ""
                    percent: padRow.modelData.battery
                        && padRow.modelData.battery.percent !== null
                        ? padRow.modelData.battery.percent : -1
                    status: padRow.modelData.battery && padRow.modelData.battery.status
                        ? padRow.modelData.battery.status : ""
                }

                Text {
                    visible: padRow.modelData.caps.batteryKind === "none"
                    text: padRow.modelData.connection === "usb" ? "wired" : "no battery"
                    color: Kirigami.Theme.textColor
                    opacity: 0.45
                    font: Kirigami.Theme.smallFont
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                GcButton {
                    // Absent rather than dead when the pad cannot rumble or
                    // the node is not writable.
                    visible: padRow.modelData.caps.rumble
                        && padRow.modelData.nodeWritable
                    text: "Test rumble"
                    tap: function() { root.rumbleTap(padRow.modelData.node) }
                }

                Item { Layout.fillWidth: true }

                GcPill {
                    text: root.streamNode === padRow.modelData.node
                        ? "listening — stop"
                        : "live input"
                    glyph: "\uF0208"
                    active: root.streamNode === padRow.modelData.node
                    tap: function() { root.streamTap(padRow.modelData.node) }
                }
            }

            Text {
                // Live input line: the Plasma popup samples the pad for a few
                // seconds per burst (a long-lived streamer process cannot be
                // hosted by the popup, unlike Quickshell's Process).
                Layout.fillWidth: true
                visible: root.streamNode === padRow.modelData.node
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: 0.65
                font: Kirigami.Theme.smallFont
                text: root.liveLine()
            }

            GcDegradedRow {
                Layout.fillWidth: true
                visible: padRow.modelData.virtual === true
                    && padRow.modelData.emulates !== null
                message: {
                    if (!padRow.modelData.emulates) return ""
                    var who = padRow.modelData.emulates.holder || "another program"
                    return who + " has your " + padRow.modelData.emulates.name
                        + " open and is presenting this emulated pad in its place. Close "
                        + who + " to see the real controller."
                }
            }

            GcDegradedRow {
                Layout.fillWidth: true
                visible: padRow.modelData.caps.led && padRow.modelData.led
                    && !padRow.modelData.led.writable
                message: "The guide-button light needs a one-time udev rule before it can be changed."
                actionText: "Show me"
                tap: function() { root.udevTap() }
            }

            GcSeparator { Layout.fillWidth: true }
        }
    }

    // --------------------------------------------------------- dongle

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.dongle !== null
        spacing: Kirigami.Units.smallSpacing

        GcSectionHeader { Layout.fillWidth: true; text: "Xbox Wireless Adapter" }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.textColor
            opacity: 0.55
            font: Kirigami.Theme.smallFont
            text: {
                if (!root.dongle) return ""
                if (root.dongle.pairing)
                    return "Pairing — hold the button on the controller."
                var n = root.dongle.activeClients
                return (n === 0 || n === null ? "No controllers" : n + " connected")
                    + " on the adapter."
            }
        }

        GcDegradedRow {
            Layout.fillWidth: true
            visible: root.dongle && !root.dongle.writable
            message: "Pairing from here needs a one-time udev rule. Without it, pairing still works the usual way: press the button on the adapter, then on the controller."
            actionText: "Show me"
            tap: function() { root.udevTap() }
        }
    }

    // --------------------------------------------------------- footer

    Text {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        color: root.error !== "" ? Kirigami.Theme.negativeTextColor
                                 : Kirigami.Theme.textColor
        opacity: root.error !== "" ? 1.0 : 0.5
        font: Kirigami.Theme.smallFont
        text: {
            if (!root.ready) return "starting…"
            if (root.error !== "") return root.error
            if (root.count === 0) return ""
            return "Stick deadzones are set per game — in Steam Input, or the game's own settings."
        }
    }

    // --------------------------------------------------------- helpers

    function padSubtitle(pad) {
        if (pad.virtual === true) {
            if (pad.emulates && pad.emulates.holder)
                return "emulated by " + pad.emulates.holder
            return "emulated"
        }
        return connectionText(pad) + " · " + pad.driver
    }

    function connectionText(pad) {
        switch (pad.connection) {
            case "usb": return "wired"
            case "dongle": return "wireless adapter"
            case "bluetooth": return "bluetooth"
            case "virtual": return "emulated"
            default: return "connected"
        }
    }

    function liveLine() {
        if (!liveSample) return "listening for input…"
        var parts = []
        if (liveSample.b) {
            var names = []
            for (var k in liveSample.b) if (liveSample.b[k]) names.push(k)
            if (names.length) parts.push("buttons: " + names.join("+"))
        }
        if (liveSample.a) {
            var axes = []
            for (var ax in liveSample.a) {
                var v = Number(liveSample.a[ax])
                if (Math.abs(v) > 0.15) axes.push(ax + " " + v.toFixed(2))
            }
            if (axes.length) parts.push("sticks: " + axes.join("  "))
        }
        return parts.length ? parts.join("   ") : "(nothing pressed)"
    }
}
