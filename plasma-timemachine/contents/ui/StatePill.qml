import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// StatePill — stadium pill: colored dot + bold word (color is never the only
// carrier). Ported from omarchy-timemachine DetailPopup.qml.
Rectangle {
  id: pill

  property string word: ""
  property color hue: Kirigami.Theme.textColor
  property bool pulse: false

  height: Kirigami.Units.gridUnit * 1.25
  width: pillRow.implicitWidth + Kirigami.Units.smallSpacing * 2
  radius: height / 2
  color: Qt.alpha(pill.hue, 0.14)

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 7; height: 7; radius: 4
      color: pill.hue
      SequentialAnimation on opacity {
        running: pill.pulse
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.3; duration: 600 }
        NumberAnimation { from: 0.3; to: 1; duration: 600 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: pill.word
      color: pill.hue
      font: Kirigami.Theme.smallFont
      font.bold: true
    }
  }
}
