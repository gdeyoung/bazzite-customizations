import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Details — fullRepresentation popup root for com.gdeyoung.plasma.timemachine.
// Ported from gdeyoung/omarchy-timemachine DetailPopup.qml (Quickshell,
// v0.5.4). Five tabs: Status / Snapshots / Health / Recovery / Settings.
// The Omarchy "Backups" tab (off-box rsync trees) is folded into Snapshots
// as a REMOTE BACKUPS section (same data, one fewer tab). Tab pages live in
// their own files; DayGroup/ActionPill/StatePill/SizeBars are shared.
//
// Popup geometry: SELF-SIZING height bound to the visible page plus chrome
// (a plain StackLayout sizes to its tallest child — the tallest-child trap).
Item {
  id: details

  required property var tm   // the applet root (main.qml)

  readonly property color stateColor: tm.stateColor

  property int currentTab: 0

  Layout.preferredWidth: Kirigami.Units.gridUnit * 34
  Layout.preferredHeight: headerRow.implicitHeight + tabBar.implicitHeight
    + pages.children[currentTab].implicitHeight + Kirigami.Units.smallSpacing * 4
  Layout.minimumWidth: Kirigami.Units.gridUnit * 28
  Layout.minimumHeight: Kirigami.Units.gridUnit * 18

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      id: headerRow
      Layout.margins: Kirigami.Units.smallSpacing * 2
      Layout.fillWidth: true
      spacing: Kirigami.Units.smallSpacing * 2

      Text {
        text: "⟲"
        color: details.stateColor
        font.pixelSize: Kirigami.Units.gridUnit
        SequentialAnimation on opacity {
          running: details.tm.state === "running"
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.25; duration: 600 }
          NumberAnimation { from: 0.3; to: 1; duration: 600 }
        }
      }
      Text {
        text: "TIME MACHINE"
        color: Kirigami.Theme.textColor
        font.bold: true
        font.pixelSize: Kirigami.Units.gridUnit * 0.8
      }
      Item { Layout.fillWidth: true }
      Text {
        text: !details.tm.conf.configured ? "not set up"
          : (details.tm.probe.next_run ? "next " + details.tm.probe.next_run : "timer unknown")
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
      }
    }

    PC3.TabBar {
      id: tabBar
      Layout.fillWidth: true
      Layout.margins: Kirigami.Units.smallSpacing
      currentIndex: details.currentTab
      onCurrentIndexChanged: details.currentTab = tabBar.currentIndex
      PC3.TabButton { text: i18n("Status") }
      PC3.TabButton { text: i18n("Snapshots") }
      PC3.TabButton { text: i18n("Health") }
      PC3.TabButton { text: i18n("Recovery") }
      PC3.TabButton { text: i18n("Settings") }
    }

    PC3.ScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true

      StackLayout {
        id: pages
        width: scroll.availableWidth
        // Track ONLY the visible page (tallest-child trap)
        height: children[currentTab].implicitHeight
        currentIndex: details.currentTab

        StatusTab { tm: details.tm }
        SnapshotsTab { tm: details.tm }
        HealthTab { tm: details.tm }
        RecoveryTab { tm: details.tm }
        SettingsTab { tm: details.tm }
      }
    }
  }
}
