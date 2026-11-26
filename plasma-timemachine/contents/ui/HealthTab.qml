import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// HealthTab — tab 3 of the TimeMachine popup. Ported from the omarchy
// DetailPopup HEALTH page, plus a target-disk row fed by the remote fetch.
// Pure display: no interactions, no handlers.
ColumnLayout {
  id: healthTab

  required property var tm

  readonly property var probe: tm.probe || ({})
  readonly property var drill: probe.drill || null
  readonly property var verify: probe.verify || null
  readonly property var health: probe.health || null
  readonly property var drift: probe.drift || null
  readonly property var snap: tm.snap || ({ status: "idle" })

  Layout.fillWidth: true
  spacing: Kirigami.Units.smallSpacing

  Text {
    Layout.fillWidth: true
    text: {
      if (healthTab.drill && healthTab.drill.fail > 0)
        return "drill failed " + healthTab.drill.pass + "/"
          + (healthTab.drill.pass + healthTab.drill.fail) + " — inspect sentinels"
      if (healthTab.drift && !healthTab.drift.clean)
        return "drift needs review"
      if (!healthTab.verify && !healthTab.drill)
        return "first drill and verify still pending"
      if (!healthTab.verify)
        return "drill " + healthTab.drill.pass + "/"
          + (healthTab.drill.pass + healthTab.drill.fail) + " · verify first run Sunday"
      return "all checks green — nothing needs attention"
    }
    color: Kirigami.Theme.disabledTextColor
    wrapMode: Text.WordWrap
  }

  component HealthRow: Rectangle {
    id: hrow
    property string name: ""
    property string sub: ""
    property string pillWord: ""
    property color pillHue: Kirigami.Theme.textColor
    property string ts: ""
    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.gridUnit * 2.5
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Kirigami.Units.smallSpacing * 2
      anchors.rightMargin: Kirigami.Units.smallSpacing * 2
      spacing: Kirigami.Units.smallSpacing * 2

      ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        Text { text: hrow.name; color: Kirigami.Theme.textColor }
        Text {
          visible: hrow.sub.length > 0
          text: hrow.sub
          color: Kirigami.Theme.disabledTextColor
          font: Kirigami.Theme.smallFont
        }
      }

      Item { Layout.fillWidth: true }
      StatePill { word: hrow.pillWord; hue: hrow.pillHue }
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: hrow.ts
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
      }
    }
  }

  HealthRow {
    name: "restore drill"
    pillWord: healthTab.drill
      ? (healthTab.drill.pass + "/" + (healthTab.drill.pass + healthTab.drill.fail)
         + (healthTab.drill.fail > 0 ? " FAIL" : " PASS")) : "—"
    pillHue: !healthTab.drill ? Kirigami.Theme.disabledTextColor
      : healthTab.drill.fail === 0 ? Kirigami.Theme.positiveTextColor
      : Kirigami.Theme.negativeTextColor
    ts: healthTab.drill ? tm.fmtTs(healthTab.drill.ts) : "never run"
  }
  HealthRow {
    name: "integrity verify"
    sub: healthTab.verify ? "" : "first verify runs Sunday"
    pillWord: healthTab.verify ? (healthTab.verify.pass + "/" + healthTab.verify.files) : "—"
    pillHue: healthTab.verify
      ? (healthTab.verify.fail === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
      : Kirigami.Theme.disabledTextColor
    ts: healthTab.verify ? tm.fmtTs(healthTab.verify.ts) : "—"
  }
  HealthRow {
    name: "healthcheck"
    sub: healthTab.health ? "" : "healthcheck hasn't run yet"
    pillWord: healthTab.health ? (healthTab.health.ok ? "OK" : "ALERT") : "—"
    pillHue: !healthTab.health ? Kirigami.Theme.disabledTextColor
      : healthTab.health.ok ? Kirigami.Theme.positiveTextColor
      : Kirigami.Theme.negativeTextColor
    ts: healthTab.health ? tm.fmtTs(healthTab.health.ts) : "—"
  }
  HealthRow {
    name: "target disk"
    sub: healthTab.snap.status === "ok" && healthTab.snap.total_gb
      ? (healthTab.snap.free_gb + " GB free of " + healthTab.snap.total_gb + " GB") : ""
    pillWord: healthTab.snap.status === "ok" && healthTab.snap.total_gb
      ? (Math.round((1 - healthTab.snap.free_gb / healthTab.snap.total_gb) * 100) + "%") : "—"
    pillHue: healthTab.snap.status === "ok" && healthTab.snap.total_gb
      ? (healthTab.snap.free_gb / healthTab.snap.total_gb > 0.1
         ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
      : Kirigami.Theme.disabledTextColor
    ts: healthTab.snap.status === "ok" ? "live" : "—"
  }
  HealthRow {
    name: "atlas drift"
    sub: healthTab.drift && !healthTab.drift.clean
      ? ("NEW-UNMANAGED " + healthTab.drift.new_unmanaged
         + " · SIZE-JUMP " + healthTab.drift.size_jump) : ""
    pillWord: healthTab.drift ? (healthTab.drift.clean ? "CLEAN" : "DRIFT") : "—"
    pillHue: !healthTab.drift ? Kirigami.Theme.disabledTextColor
      : healthTab.drift.clean ? Kirigami.Theme.positiveTextColor
      : Kirigami.Theme.neutralTextColor
    ts: tm.fmtTs(healthTab.probe.last_iso)
  }
}
