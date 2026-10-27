import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// One drive row: kind glyph, name, usage bar, action buttons, busy notice.
// Ported from the Omarchy plugin's DriveRow.qml (CursorSurface card) to a
// RowLayout with PC3 controls (port law); information architecture from
// jgarza9788/drives DriveCard.qml @ 255609e (MIT) — see NOTICE.md.
//
// Actions dispatch through a Repeater of ActionIconButton with an `action`
// key — the file declares exactly one onActivated handler (port law: a
// handler name may appear at most once per file).
RowLayout {
    id: row
    property var drive: null
    property var busyResult: null
    property string glyphFont: ""
    property int fullWarnPct: 90

    // The plasmoid root (drives actions + busy bookkeeping live there).
    property var driveway: null

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color urgentC: Kirigami.Theme.negativeTextColor
    readonly property bool isSystem: drive && drive.kind === "system"
    readonly property bool mounted: drive && drive.mounted
    readonly property bool full: drive && drive.mounted && drive.size > 0 && drive.pct >= fullWarnPct
    readonly property string caption: drive
        ? [Model.kindName(drive), Model.usageText(drive), drive.fstype]
            .filter(function(s) { return !!s }).join(" · ")
        : ""

    // Visible action set for this drive: {action, iconName|text, tooltip}
    function actionSet() {
        const out = []
        const d = row.drive
        if (!d) return out
        if (!row.isSystem && !row.mounted && !d.locked)
            out.push({ action: "mount", iconName: "media-mount", tooltip: qsTr("Mount") })
        if (!row.isSystem && d.locked)
            out.push({ action: "unlock", iconName: "object-unlock",
                       tooltip: qsTr("Unlock — LUKS passphrase is typed in a terminal") })
        if (row.mounted)
            out.push({ action: "open", iconName: "document-open-folder",
                       tooltip: qsTr("Open in file manager") })
        if (!row.isSystem && row.mounted && !!d.eject)
            out.push({ action: "eject", iconName: "media-eject",
                       tooltip: d.removable ? qsTr("Eject (power off)") : qsTr("Unmount") })
        return out
    }

    function runAction(key) {
        const d = row.drive
        if (!d || !row.driveway) return
        if (key === "mount") row.driveway.mountDrive(d)
        else if (key === "unlock") row.driveway.unlockDrive(d)
        else if (key === "open")
            row.driveway.openPath(d.mounted ? d.mountpoint : "/")
        else if (key === "eject") row.driveway.ejectDrive(d, false, false)
    }

    spacing: Kirigami.Units.smallSpacing

    Text {
        visible: !!row.drive
        text: row.drive ? Model.kindIcon(row.drive, null) : ""
        color: row.mounted ? row.fg : row.muted
        font.family: row.glyphFont !== "" ? row.glyphFont : Kirigami.Theme.defaultFont.family
        font.pixelSize: Kirigami.Units.gridUnit * 0.8
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.drive ? (row.drive.label || row.drive.name || Model.kindName(row.drive)) : ""
            color: row.fg
            font: Kirigami.Theme.smallFont
            font.bold: row.isSystem
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            text: row.caption
            color: row.muted
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        // Usage bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            visible: row.drive && row.drive.size > 0
            color: Qt.alpha(row.muted, 0.35)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1, (row.drive ? row.drive.pct : 0) / 100)
                radius: parent.radius
                color: row.full ? row.urgentC : Qt.alpha(row.fg, 0.75)
            }
        }
    }

    RowLayout {
        spacing: 0

        Repeater {
            model: row.actionSet()
            ActionIconButton {
                required property var modelData
                iconName: modelData.iconName || ""
                text: modelData.text || ""
                tooltipText: modelData.tooltip || ""
                onActivated: row.runAction(modelData.action)
            }
        }
    }
}
