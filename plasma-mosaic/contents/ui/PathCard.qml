import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "lib/ViewModel.js" as ViewModel

// Path card (spec §E): collapsed 56px evidence-forward row; expands in place
// (<=220px) into Why here / Skipped / Breakdown. Confidence honesty:
// possible/shared cards render dimmed at 60% and never sum into totals.
Item {
    id: card

    property var entry: null
    property bool expanded: false
    readonly property bool excluded: entry && entry.confidence
        && entry.confidence !== "known"
    property bool justCopied: false
    Connections {
        target: MosaicStore
        function onCopiedAtChanged() {
            if (card.entry && MosaicStore.copiedPath === card.entry.path) {
                card.justCopied = true
                copyFade.restart()
            }
        }
    }
    Timer { id: copyFade; interval: 1500; onTriggered: card.justCopied = false }
    readonly property string label: entry ? (entry.label && entry.label !== ""
        ? entry.label : String(entry.path).split("/").pop()) : ""

    width: parent ? parent.width : (ListView.view ? ListView.view.width : 0)
    implicitHeight: expanded ? expandedBody.implicitHeight + 56 : 56
    height: implicitHeight

    signal toggleRequested()
    onToggleRequested: card.forceActiveFocus()

    opacity: excluded ? 0.6 : 1.0

    Accessible.role: Accessible.ListItem
    Accessible.name: label + ", " + (entry ? MosaicStore.formatBytes(entry.bytes, false) : "")
        + ", " + (entry ? MosaicStore.statusLabel(entry.status || entry.confidence) : "")

    MouseArea {
        id: cardTap
        anchors.top: parent.top
        height: 56
        width: parent.width
        hoverEnabled: true
        onClicked: { card.forceActiveFocus(); card.toggle() }
    }
    function toggle() { toggleRequested() }   // page owns one-open accordion

    Rectangle {
        visible: cardTap.containsMouse || card.activeFocus
        y: 0
        width: parent.width
        height: 56
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.06)
        border.color: card.activeFocus ? Kirigami.Theme.highlightColor : "transparent"
        border.width: 1
        radius: Kirigami.Units.smallSpacing / 2
    }
    Rectangle {
        y: 55
        width: parent.width
        height: 1
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.12)
    }

    // ---- collapsed row (56px) --------------------------------------------
    RowLayout {
        id: collapsed
        x: 0
        width: parent.width
        height: 56
        spacing: Kirigami.Units.smallSpacing

        Item { Layout.preferredWidth: Kirigami.Units.smallSpacing; Layout.fillHeight: true }
        Rectangle {
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            radius: 5
            color: MosaicStore.categoryColor(card.entry ? card.entry.category : "config")
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: card.label
                color: Kirigami.Theme.textColor
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                // elide-LEFT: the path TAIL stays visible (fleet table rule)
                text: card.entry ? card.entry.path : ""
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11
                elide: Text.ElideLeft
            }
        }
        Text {
            Layout.preferredWidth: 76
            horizontalAlignment: Text.AlignRight
            text: card.entry ? (card.entry.bytes === null || card.entry.bytes === undefined
                ? "unknown" : MosaicStore.formatBytes(card.entry.bytes, false)) : ""
            color: Kirigami.Theme.textColor
            font.pixelSize: 13
        }
        StatChip {
            dotColor: card.entry && card.entry.status === "failed" ? "#f4405c"
                : card.excluded ? "#9aa4b2"
                : MosaicStore.statusColor(card.entry ? card.entry.status : "")
            text: card.entry
                ? MosaicStore.statusLabel(card.entry.status || card.entry.confidence) : ""
        }
        Text {
            Layout.preferredWidth: 16
            horizontalAlignment: Text.AlignHCenter
            text: card.expanded ? "\u25be" : "\u25b8"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 12
        }
        Item { Layout.preferredWidth: Kirigami.Units.smallSpacing; Layout.fillHeight: true }
    }

    // ---- expanded body (accordion; page enforces one-open) ----------------
    ColumnLayout {
        id: expandedBody
        visible: card.expanded
        y: 56
        width: parent.width
        spacing: Kirigami.Units.smallSpacing / 2

        Item { Layout.preferredHeight: 0 }

        // (1) WHY HERE — evidence string verbatim
        Text {
            Layout.leftMargin: Kirigami.Units.smallSpacing * 3
            Layout.fillWidth: true
            visible: card.entry && card.entry.evidence
            text: card.entry ? (card.entry.evidence || "") : ""
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.leftMargin: Kirigami.Units.smallSpacing * 3
            visible: card.entry && (card.entry.reason || card.entry.source)
            text: card.entry
                ? ((card.entry.reason ? String(card.entry.reason).toUpperCase() : "")
                   + (card.entry.reason && card.entry.source ? " \u00b7 " : "")
                   + (card.entry.source ? String(card.entry.source).toUpperCase() : "")) : ""
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
            font.letterSpacing: 0.4
        }

        // (2) SKIPPED — micro-chips
        RowLayout {
            Layout.leftMargin: Kirigami.Units.smallSpacing * 3
            visible: !!(card.entry && card.entry.skippedCounts)
            spacing: Kirigami.Units.smallSpacing / 2 + 2
            Repeater {
                model: {
                    const counts = card.entry && card.entry.skippedCounts ? card.entry.skippedCounts : {}
                    const out = []
                    for (const k in counts)
                        if (counts[k] > 0) out.push({ reason: k, count: counts[k] })
                    return out
                }
                delegate: StatChip {
                    required property var modelData
                    showDot: false
                    text: modelData.reason + " \u00d7" + modelData.count
                }
            }
        }

        // (3) BREAKDOWN — top-12 subdirectories (after a deep scan)
        ColumnLayout {
            Layout.leftMargin: Kirigami.Units.smallSpacing * 3
            Layout.rightMargin: Kirigami.Units.smallSpacing * 2
            Layout.fillWidth: true
            visible: !!(card.entry && card.entry.breakdown && card.entry.breakdown.length > 0)
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "TOP SUBDIRECTORIES"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                    font.letterSpacing: 0.4
                }
                Text {
                    visible: card.entry && (card.entry.directBytes !== undefined
                                            || card.entry.directFiles !== undefined)
                    text: card.entry
                        ? ("direct: " + MosaicStore.formatBytes(card.entry.directBytes || 0, false)
                           + " \u00b7 " + (card.entry.directFiles || 0).toLocaleString() + " files") : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                }
                PC3.ToolButton {
                    icon.name: card.justCopied ? "" : "edit-copy"
                    text: card.justCopied ? "Copied \u2713" : ""
                    font.pixelSize: 12
                    onClicked: if (card.entry) MosaicStore.copyToClipboard(card.entry.path)
                    Accessible.name: "Copy path"
                }
            }
            Repeater {
                model: card.entry && card.entry.breakdown
                    ? card.entry.breakdown.slice(0, 12) : []
                delegate: RowLayout {
                    id: subRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 100
                        text: subRow.modelData.name || subRow.modelData.path || ""
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 12
                        elide: Text.ElideLeft
                    }
                    Text {
                        Layout.preferredWidth: 76
                        horizontalAlignment: Text.AlignRight
                        text: MosaicStore.formatBytes(subRow.modelData.bytes, false)
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 12
                    }
                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: MosaicStore.statusColor(subRow.modelData.status || "complete")
                    }
                }
            }
        }
        Text {
            Layout.leftMargin: Kirigami.Units.smallSpacing * 3
            visible: card.expanded && (!card.entry.breakdown || card.entry.breakdown.length === 0)
            text: "Run a deeper scan to break this path down."
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: 11
        }
    }

    Keys.onReturnPressed: card.toggle()
    Keys.onEnterPressed: card.toggle()
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_E) { card.toggle(); event.accepted = true }
    }
}
