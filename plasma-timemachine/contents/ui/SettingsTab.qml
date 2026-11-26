import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// SettingsTab — tab 5 of the TimeMachine popup. Ported from the omarchy
// DetailPopup SETTINGS page, reduced to a read-only conf summary + actions:
// engine config stays in the tm engine's conf file (see README) — the
// plasmoid's own settings (refresh interval, thresholds, conf path) live in
// the Plasma config dialog (contents/config/). Interactive buttons are
// ActionPills routed through the applet root.
ColumnLayout {
  id: setTab

  required property var tm

  readonly property var conf: tm.conf || ({})

  Layout.fillWidth: true
  spacing: Kirigami.Units.smallSpacing * 2

  Text {
    Layout.fillWidth: true
    text: "engine configuration — " + tm.confPathDisplay
    color: Kirigami.Theme.textColor
    font.bold: true
    wrapMode: Text.WordWrap
  }

  component ConfRow: RowLayout {
    id: cfrow
    property string key: ""
    property string value: ""
    spacing: Kirigami.Units.smallSpacing * 2
    Layout.fillWidth: true
    Text {
      Layout.preferredWidth: Kirigami.Units.gridUnit * 7
      text: cfrow.key
      color: Kirigami.Theme.disabledTextColor
      font: Kirigami.Theme.smallFont
    }
    Text {
      Layout.fillWidth: true
      text: cfrow.value.length > 0 ? cfrow.value : "—"
      color: Kirigami.Theme.textColor
      font: Kirigami.Theme.smallFont
      elide: Text.ElideMiddle
    }
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: confCol.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor

    Column {
      id: confCol
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      spacing: 2

      ConfRow { key: "configured"; value: setTab.conf.configured ? "yes" : "no" }
      ConfRow { key: "host"; value: setTab.conf.host || "" }
      ConfRow { key: "remote path"; value: setTab.conf.dest || "" }
      ConfRow { key: "port"; value: String(setTab.conf.port || 22) }
      ConfRow { key: "label"; value: setTab.conf.label || "" }
      ConfRow { key: "schedule"; value: setTab.conf.schedule || "" }
      ConfRow {
        key: "retention"
        value: (setTab.conf.retention ? setTab.conf.retention.daily : 14) + "d/"
          + (setTab.conf.retention ? setTab.conf.retention.weekly : 8) + "w/"
          + (setTab.conf.retention ? setTab.conf.retention.monthly : 12) + "m"
      }
      ConfRow { key: "sentinels"; value: (setTab.conf.sentinels || []).length + " files" }
      ConfRow { key: "max age"; value: String(setTab.conf.max_age_h || 30) + " h" }
      ConfRow {
        key: "timer"
        value: setTab.conf.timer_installed
          ? "installed · next " + (setTab.conf.timer_next || "fire pending") : "not installed"
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "engine config is written by the bundled tm-conf.sh (contents/scripts/bin/) — the plasmoid never writes it; see the README for the key list."
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    ActionPill { label: "⟳ BACK UP NOW"; act: "backupNow"; primary: true }
    ActionPill { label: "✓ RUN DRILL"; act: "runDrill" }
    Item { Layout.fillWidth: true }
    ActionPill { label: "⟳ REFRESH"; act: "refreshAll" }
  }
}
