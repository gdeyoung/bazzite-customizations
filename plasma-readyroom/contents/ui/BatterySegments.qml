import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Five-segment battery, or a real percentage when the driver has one — the
// honest rendering of what xone (5 buckets) vs hid_playstation (percent)
// actually report. Port of controllers/BatterySegments.qml.
Row {
    id: root

    // "level" (5 buckets), "percent", or "none"
    property string kind: "none"
    property string level: ""
    property int percent: -1
    property string status: ""
    property color urgent: Kirigami.Theme.negativeTextColor

    spacing: Kirigami.Units.smallSpacing / 2

    readonly property int filled: {
        if (kind === "percent" && percent >= 0)
            return Math.max(1, Math.ceil(percent / 20))
        switch (level) {
            case "Full": return 5
            case "High": return 4
            case "Normal": return 3
            case "Low": return 1
            default: return 0
        }
    }

    readonly property bool low: filled === 1
        || (kind === "percent" && percent >= 0 && percent <= 15)
    readonly property bool charging: status === "Charging"

    Repeater {
        model: root.kind === "level" ? 5 : 0

        Rectangle {
            width: Kirigami.Units.smallSpacing * 1.4
            height: Kirigami.Units.smallSpacing * 2.4
            radius: Kirigami.Units.smallSpacing / 2
            color: index < root.filled
                ? (root.low ? root.urgent : Kirigami.Theme.textColor)
                : Qt.alpha(Kirigami.Theme.textColor, 0.18)
        }
    }

    Text {
        visible: root.kind === "percent" && root.percent >= 0
        text: root.percent + "%"
        color: root.low ? root.urgent : Kirigami.Theme.textColor
        font: Kirigami.Theme.smallFont
    }

    Text {
        // "Unknown" is a real answer from the driver, not a failure.
        visible: root.kind === "level" && root.filled === 0
        text: "unknown"
        color: Kirigami.Theme.textColor
        opacity: 0.5
        font: Kirigami.Theme.smallFont
    }

    Text {
        visible: root.charging
        text: "\uF0084"
        font.family: "Symbols Nerd Font"
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    }
}
