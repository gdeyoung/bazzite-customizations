import QtQuick
import org.kde.kirigami as Kirigami

// ActionPill — small bordered action pill (BACK UP NOW / RUN DRILL / RETRY /
// COPY / BROWSE / RECOVER / SNAPSHOT NOW / REFRESH). Ported from the
// omarchy-timemachine ActionPill/CursorSurface pair.
//
// Activation routes through the `act` string + this file's ONE onClicked
// dispatcher (repo checker rule: one handler per signal per file). The
// dispatcher targets `tmHost` — a property declared on the applet root
// (main.qml), resolved via QML dynamic scoping from any instantiation site.
//   act: ""                    just emits activated()
//   act + arg                  tmHost[act](arg)
//   act                        tmHost[act]()
//   argMode "path"             tmHost.openPath(arg)      (xdg-open browse)
//   argMode "recoverRemote"    preselect backup id, jump to Recovery tab
Rectangle {
  id: apill

  property string label: ""
  property color hue: Kirigami.Theme.textColor
  property string act: ""
  property var arg: null
  property string argMode: ""
  property bool primary: false

  signal activated()

  implicitWidth: apillText.implicitWidth + Kirigami.Units.smallSpacing * 3
  implicitHeight: Kirigami.Units.gridUnit * 1.3
  radius: Kirigami.Units.smallSpacing / 2
  border.width: apill.primary ? 0 : 1
  border.color: apillArea.containsMouse ? Kirigami.Theme.textColor
    : Qt.alpha(Kirigami.Theme.textColor, 0.3)
  color: apill.primary ? Qt.alpha(Kirigami.Theme.hoverColor, 0.25) : "transparent"

  Text {
    id: apillText
    anchors.centerIn: parent
    text: apill.label
    color: apill.hue
    font: Kirigami.Theme.smallFont
    font.bold: true
  }

  MouseArea {
    id: apillArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      apill.activated()
      if (apill.act === "") return
      if (apill.argMode === "path") { tmHost.openPath(String(apill.arg)); return }
      if (apill.argMode === "recoverRemote") {
        tmHost.recoverSnapshot = String(apill.arg)
        tmHost.currentTab = 3
        return
      }
      if (apill.arg !== null && apill.arg !== undefined) tmHost[apill.act](apill.arg)
      else tmHost[apill.act]()
    }
  }
}
