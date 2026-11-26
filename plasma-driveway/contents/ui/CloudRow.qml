import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// One cloud remote row (Cloud tab): provider glyph, name, type + quota or
// usage text, usage/quota bar, state chip, pending-upload badge, open and
// mount/unmount actions. Single onActivated handler in this file
// dispatches on the action key (port law: one handler name per file).
RowLayout {
    id: crow
    property var remote: null
    property var driveway: null
    property string glyphFont: ""
    property int fullWarnPct: 90

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color urgentC: Kirigami.Theme.negativeTextColor
    readonly property color barTrack: Qt.alpha(Kirigami.Theme.textColor, 0.18)
    readonly property color barFill: Kirigami.Theme.highlightColor
    readonly property bool mounted: remote && (remote.state === "mounted"
                                               || remote.state === "external")

    // quota percentage when known, else usage percentage
    function fillPct() {
        if (!crow.remote) return 0
        if (Model.aboutText(crow.remote.about) !== "")
            return Model.aboutPct(crow.remote.about)
        return crow.remote.pct || 0
    }

    function actionSet() {
        const out = []
        const r = crow.remote
        if (!r) return out
        if (crow.mounted && r.mountpoint !== "")
            out.push({ key: "open", text: qsTr("Open") })
        if (r.state !== "starting")
            out.push({ key: "toggle", text: crow.mounted ? qsTr("Unmount") : qsTr("Mount") })
        return out
    }

    function runAction(key) {
        const r = crow.remote
        if (!r || !crow.driveway) return
        if (key === "open") crow.driveway.openPath(r.mountpoint)
        else if (key === "toggle") {
            if (crow.mounted) crow.driveway.cloudUnmount(r.name)
            else crow.driveway.cloudMount(r.name)
        }
    }

    spacing: Kirigami.Units.smallSpacing

    Text {
        text: crow.remote ? (Model.DEFAULT_ICONS[crow.remote.kind]
                             || Model.DEFAULT_ICONS.cloud) : ""
        color: crow.mounted ? crow.fg : crow.muted
        font.family: crow.glyphFont !== "" ? crow.glyphFont : Kirigami.Theme.defaultFont.family
        font.pixelSize: Kirigami.Units.gridUnit * 0.8
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
            Layout.fillWidth: true
            text: crow.remote ? crow.remote.name : ""
            color: crow.fg
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text: crow.remote
                  ? [crow.remote.type,
                     Model.aboutText(crow.remote.about) || Model.usageText(crow.remote)]
                    .filter(function(s) { return !!s }).join(" · ")
                  : ""
            color: crow.muted
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        // usage / quota bar
        Rectangle {
            Layout.fillWidth: true
            visible: crow.remote
                     && (Model.aboutText(crow.remote.about) !== ""
                         || (crow.mounted && crow.remote.size > 0))
            implicitHeight: 4
            radius: 2
            color: crow.barTrack
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1, crow.fillPct() / 100)
                radius: parent.radius
                color: crow.fillPct() >= crow.fullWarnPct ? crow.urgentC : crow.barFill
            }
        }
    }

    Text {
        visible: crow.remote && crow.remote.pending > 0
        text: crow.remote ? ("↑" + crow.remote.pending) : ""
        color: crow.urgentC
        font: Kirigami.Theme.smallFont
        PC3.ToolTip.text: qsTr("Pending uploads to this remote")
        PC3.ToolTip.visible: hovered
    }

    Text {
        text: crow.remote ? Model.cloudStateLabel(crow.remote.state) : ""
        color: crow.remote && Model.cloudUrgent(crow.remote.state) ? crow.urgentC
              : (crow.mounted ? crow.fg : crow.muted)
        font: Kirigami.Theme.smallFont
    }

    Repeater {
        model: crow.actionSet()
        ActionIconButton {
            required property var modelData
            text: modelData.text || ""
            onActivated: crow.runAction(modelData.key)
        }
    }
}
