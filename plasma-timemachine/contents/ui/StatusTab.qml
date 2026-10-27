import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// StatusTab — tab 1 of the TimeMachine popup. Ported from the omarchy
// DetailPopup STATUS page: verdict pill + stat cards + backup-size chart +
// local-snapshot freshness + BACK UP NOW / RUN DRILL actions. Interactive
// elements are ActionPills (their own file owns the click dispatcher).
ColumnLayout {
  id: statusTab

  required property var tm

  readonly property var probe: tm.probe || ({})
  readonly property var drill: probe.drill || null
  readonly property var hist: Array.isArray(probe.history) ? probe.history : []
  readonly property var sizes: hist.map(function(h) { return h.v || 0 })
  readonly property real sizeMax: sizes.length ? Math.max.apply(null, sizes) : 0
  readonly property real sizeAvg: sizes.length
    ? sizes.reduce(function(a, b) { return a + b }, 0) / sizes.length : 0

  Layout.fillWidth: true
  spacing: Kirigami.Units.smallSpacing * 2

  RowLayout {
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    StatePill {
      word: tm.stateWord()
      hue: tm.state === "never" ? Kirigami.Theme.disabledTextColor : tm.stateColor
      pulse: tm.state === "running"
    }
    Text {
      Layout.fillWidth: true
      text: tm.verdictLine()
      color: Kirigami.Theme.disabledTextColor
      elide: Text.ElideRight
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Kirigami.Units.gridUnit * 3.4
      radius: Kirigami.Units.smallSpacing
      color: Kirigami.Theme.backgroundColor
      Column {
        anchors.centerIn: parent
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "last backup"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: tm.ageText; color: tm.stateColor; font.bold: true; font.pixelSize: Kirigami.Units.gridUnit * 0.8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: statusTab.probe.last_iso; text: tm.fmtTs(statusTab.probe.last_iso); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
      }
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Kirigami.Units.gridUnit * 3.4
      radius: Kirigami.Units.smallSpacing
      color: Kirigami.Theme.backgroundColor
      Column {
        anchors.centerIn: parent
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "backup"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusTab.probe.backup || "—"; color: Kirigami.Theme.textColor; font.bold: true; font.pixelSize: Kirigami.Units.gridUnit * 0.8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: (statusTab.probe.size_mb || 0) + " MB · " + (statusTab.probe.dur_s || 0) + "s"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
      }
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Kirigami.Units.gridUnit * 3.4
      radius: Kirigami.Units.smallSpacing
      color: Kirigami.Theme.backgroundColor
      Column {
        anchors.centerIn: parent
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "history"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: (statusTab.probe.backups_n || 0) + " in repo"; color: Kirigami.Theme.textColor; font.bold: true; font.pixelSize: Kirigami.Units.gridUnit * 0.8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: statusTab.sizes.length; text: "avg " + Math.round(statusTab.sizeAvg) + " MB"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
      }
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Kirigami.Units.gridUnit * 3.4
      radius: Kirigami.Units.smallSpacing
      color: Kirigami.Theme.backgroundColor
      Column {
        anchors.centerIn: parent
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "drill"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusTab.drill ? (statusTab.drill.pass + "/" + (statusTab.drill.pass + statusTab.drill.fail)) : "—"; color: Kirigami.Theme.textColor; font.bold: true; font.pixelSize: Kirigami.Units.gridUnit * 0.8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusTab.drill ? tm.fmtTs(statusTab.drill.ts) : "never run"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: statusTab.drill; text: statusTab.drill && statusTab.drill.fail === 0 ? "PASS" : "FAIL"; color: statusTab.drill && statusTab.drill.fail === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor; font: Kirigami.Theme.smallFont; font.bold: true }
      }
    }
  }

  Text {
    visible: tm.snapper.status === "ok"
    Layout.fillWidth: true
    text: tm.snapFreshText()
    color: tm.snapFresh() ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
    font: Kirigami.Theme.smallFont
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: chartCol.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor
    Column {
      id: chartCol
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      spacing: Kirigami.Units.smallSpacing / 2
      RowLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing
        Text { text: "BACKUP SIZE — LAST " + statusTab.hist.length; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Item { Layout.fillWidth: true }
        Text { visible: statusTab.sizes.length; text: "max " + Math.round(statusTab.sizeMax) + " MB · avg " + Math.round(statusTab.sizeAvg) + " MB"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
      }
      SizeBars {
        width: parent.width
        barHeight: statusTab.hist.length ? Kirigami.Units.gridUnit * 3.2 : Kirigami.Units.gridUnit * 1.6
        values: statusTab.sizes
        barColor: Kirigami.Theme.activeTextColor
        lastColor: Kirigami.Theme.positiveTextColor
      }
      Text {
        visible: statusTab.hist.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "no history yet — first backup will chart here"
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
      }
      Text {
        width: parent.width
        property var ret: statusTab.probe.retention || { daily: 14, weekly: 8, monthly: 12 }
        text: "rsync → " + tm.label + " (plaintext) · schedule " + (statusTab.probe.schedule || "")
          + " · retention " + ret.daily + "d/" + ret.weekly + "w/" + ret.monthly + "m"
          + " · sentinel verify weekly · restore = merge (ask first)"
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    ActionPill { label: tm.busy === "backup" ? "⟳ starting…" : "⟳ BACK UP NOW"; act: "backupNow"; primary: true }
    ActionPill { label: tm.busy === "drill" ? "◌ drilling…" : "✓ RUN DRILL"; act: "runDrill" }
    Item { Layout.fillWidth: true }
    Text {
      visible: tm.busy.length > 0
      text: tm.busy === "drill" ? "restore drill running (~30–60s)" : ""
      color: Kirigami.Theme.disabledTextColor
      font: Kirigami.Theme.smallFont
    }
  }

  Rectangle {
    visible: tm.output.length > 0
    Layout.fillWidth: true
    implicitHeight: outText.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
    Text {
      id: outText
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      text: tm.output
      color: Kirigami.Theme.disabledTextColor
      font: Kirigami.Theme.smallFont
      wrapMode: Text.WrapAnywhere
    }
  }
}
