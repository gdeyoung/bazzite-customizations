import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// One configured share row (Shares tab): scheme glyph, label, live
// mounted/not-mounted state (matched against the lister's network rows by
// mountpoint), mount/unmount. Shares come from Plasmoid.configuration —
// host specifics never live in the repo. Single onActivated in this file
// dispatches on the action key (port law).
RowLayout {
    id: srow
    property var share: null
    property var driveway: null
    property string glyphFont: ""

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor

    function actionSet() {
        const out = []
        if (!srow.share) return out
        if (srow.share.state === "up")
            out.push({ key: "unmount", text: qsTr("Unmount") })
        else if (srow.share.state !== "busy")
            out.push({ key: "mount", text: qsTr("Mount") })
        return out
    }

    function runAction(key) {
        if (!srow.driveway || !srow.share) return
        if (key === "unmount") srow.driveway.shareUnmount(srow.share)
        else if (key === "mount") srow.driveway.shareMount(srow.share)
    }

    spacing: Kirigami.Units.smallSpacing

    Text {
        text: srow.share ? Model.netGlyph(srow.share.scheme) : ""
        color: srow.share && srow.share.state === "up" ? srow.fg : srow.muted
        font.family: srow.glyphFont !== "" ? srow.glyphFont : Kirigami.Theme.defaultFont.family
        font.pixelSize: Kirigami.Units.gridUnit * 0.8
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
            Layout.fillWidth: true
            text: srow.share ? srow.share.label : ""
            color: srow.fg
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text: srow.share
                  ? srow.share.fstype + (srow.share.state === "up"
                        ? " · mounted" : " · not mounted")
                  : ""
            color: srow.muted
            font: Kirigami.Theme.smallFont
            elide: Text.ElideMiddle
        }
    }

    PC3.BusyIndicator {
        visible: srow.share && srow.share.state === "busy"
        implicitWidth: Kirigami.Units.gridUnit
        implicitHeight: Kirigami.Units.gridUnit
    }

    Repeater {
        model: srow.actionSet()
        ActionIconButton {
            required property var modelData
            text: modelData.text || ""
            onActivated: srow.runAction(modelData.key)
        }
    }
}
