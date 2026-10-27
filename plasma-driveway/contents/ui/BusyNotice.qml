import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Busy / pending-upload notice for one drive, with the one remedy that can
// work (from the engine's action JSON: procs -> close-apps-and-retry,
// uploads -> unmount-anyway) plus dismiss. Separate file so its single
// onActivated handler is the only one here (port law: one handler name per
// file).
ColumnLayout {
    id: notice
    property var busyResult: null
    property var drive: null
    property var driveway: null

    readonly property color urgentC: Kirigami.Theme.negativeTextColor

    // Remedy buttons as data; the Repeater's single handler dispatches.
    function remedySet() {
        const out = []
        const b = notice.busyResult
        if (!b) return out
        if (b.procs && b.procs.length > 0)
            out.push({ key: "retry", text: qsTr("Close apps & retry") })
        if (b.uploads > 0)
            out.push({ key: "force", text: qsTr("Unmount anyway") })
        out.push({ key: "dismiss", iconName: "dialog-close", tooltip: qsTr("Dismiss") })
        return out
    }

    function runRemedy(key) {
        if (!notice.driveway || !notice.drive) return
        if (key === "retry") notice.driveway.ejectDrive(notice.drive, true, false)
        else if (key === "force") notice.driveway.ejectDrive(notice.drive, false, true)
        else if (key === "dismiss") notice.driveway.clearBusy(notice.drive)
    }

    spacing: Kirigami.Units.smallSpacing

    Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: notice.busyResult ? notice.busyResult.message : ""
        color: notice.urgentC
        font: Kirigami.Theme.smallFont
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: notice.remedySet()
            ActionIconButton {
                required property var modelData
                iconName: modelData.iconName || ""
                text: modelData.text || ""
                tooltipText: modelData.tooltip || ""
                onActivated: notice.runRemedy(modelData.key)
            }
        }
    }
}
