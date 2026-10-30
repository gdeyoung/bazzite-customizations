import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// KillBar — in-place kill confirmation (popup focus-loss forbids modal
// dialogs). Existing TERM -> Force-9 escalation mechanic, restyled to a
// FIXED 28px height so its appearance never reflows the 960x640 frame.
// v0.7 addition: the executable engine's real exit code is surfaced
// ("\u2717 no permission" on EPERM) instead of failing silently.
Rectangle {
    id: bar
    required property var sysmon

    readonly property color cRed: "#f4405c"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor

    visible: sysmon.killTarget > 0
    height: 28
    radius: 4
    color: Qt.alpha(cRed, 0.12)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: sysmon.killExit !== 0
                  ? i18n("\u2717 no permission \u2014 " + sysmon.killName + " (" + sysmon.killTarget + ")")
                  : i18n("Kill " + sysmon.killName + " (" + sysmon.killTarget + ")?")
            color: sysmon.killExit !== 0 ? bar.cRed : bar.fg
            font.pixelSize: 12
        }
        Rectangle {
            implicitWidth: killBtn.implicitWidth + 12
            implicitHeight: 20
            radius: 3
            color: Qt.alpha(bar.cRed, 0.3)
            Text {
                id: killBtn
                anchors.centerIn: parent
                text: sysmon.killTermed ? "Force kill (9)" : "Kill (TERM)"
                color: bar.cRed
                font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sysmon.doKill(sysmon.killTarget, sysmon.killTermed ? 9 : 15)
            }
        }
        Rectangle {
            implicitWidth: cancelBtn.implicitWidth + 12
            implicitHeight: 20
            radius: 3
            color: Qt.alpha(bar.fg, 0.10)
            Text {
                id: cancelBtn
                anchors.centerIn: parent
                text: "Cancel"
                color: bar.muted
                font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { sysmon.killTarget = 0; sysmon.killTermed = false }
            }
        }
    }
}
