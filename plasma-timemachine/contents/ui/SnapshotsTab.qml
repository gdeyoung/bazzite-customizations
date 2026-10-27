import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// SnapshotsTab — tab 2 of the TimeMachine popup. Ported from the omarchy
// DetailPopup SNAPSHOTS page, with the old BACKUPS page (off-box rsync
// trees) folded in as a REMOTE BACKUPS section below the local snapshot
// sections. Day rows come from DayGroup.qml; retry buttons are ActionPills.
ColumnLayout {
  id: snapTab

  required property var tm

  readonly property var snapper: tm.snapper || ({ status: "idle" })
  readonly property var snap: tm.snap || ({ status: "idle" })
  readonly property var snapRows: Array.isArray(snap.rows) ? snap.rows : []

  Layout.fillWidth: true
  spacing: Kirigami.Units.smallSpacing * 2

  // ---- LOCAL (btrfs/snapper) -----------------------------------------------
  Text {
    visible: snapTab.snapper.status === "ok" || snapTab.snapper.status === "empty"
    Layout.fillWidth: true
    text: "local btrfs snapshots — hourly + on every package install; also bootable from the boot menu"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    wrapMode: Text.WordWrap
  }

  RowLayout {
    visible: snapTab.snapper.status === "ok"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    Text {
      Layout.fillWidth: true
      text: "creates a manual root + home pair now"
      color: Kirigami.Theme.disabledTextColor
      font: Kirigami.Theme.smallFont
    }
    ActionPill { label: "SNAPSHOT NOW"; hue: Kirigami.Theme.positiveTextColor; act: "createSnapshots" }
  }

  Text {
    visible: snapTab.snapper.status === "idle" || snapTab.snapper.status === "loading"
    text: "◌ reading local snapshots…"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    SequentialAnimation on opacity {
      running: visible
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.3; duration: 600 }
      NumberAnimation { from: 0.3; to: 1; duration: 600 }
    }
  }

  RowLayout {
    visible: snapTab.snapper.status === "denied"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    Text {
      Layout.fillWidth: true
      text: "can't list local snapshots — permission denied (root needed)"
      color: Kirigami.Theme.neutralTextColor
      font: Kirigami.Theme.smallFont
      wrapMode: Text.WordWrap
    }
    ActionPill { label: "RETRY"; hue: Kirigami.Theme.neutralTextColor; act: "fetchSnapper" }
  }

  RowLayout {
    visible: snapTab.snapper.status === "unavailable"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    Text {
      Layout.fillWidth: true
      text: "snapper not installed — local snapshots unavailable"
      color: Kirigami.Theme.disabledTextColor
      font: Kirigami.Theme.smallFont
      wrapMode: Text.WordWrap
    }
    ActionPill { label: "RETRY"; act: "fetchSnapper" }
  }

  Text {
    visible: snapTab.snapper.status === "empty"
    Layout.fillWidth: true
    text: "no local snapshots yet — created hourly and on package installs"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    wrapMode: Text.WordWrap
  }

  // one section per snapper config (root = SYSTEM @, home = HOME @HOME)
  Repeater {
    model: snapTab.snapper.status === "ok" ? (snapTab.snapper.configs || []) : []
    delegate: ColumnLayout {
      id: ssect
      required property var modelData
      Layout.fillWidth: true
      spacing: Kirigami.Units.smallSpacing / 2
      Text {
        text: (ssect.modelData.name === "root" ? "SYSTEM @" : "HOME @HOME")
          + " · " + (ssect.modelData.count || 0)
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        font.letterSpacing: 1
      }
      Repeater {
        model: tm.dayGroups(ssect.modelData.rows || [], false)
        delegate: DayGroup {
          tm: snapTab.tm
          kind: "snapshot"
          subvol: ssect.modelData.subvol || "/"
        }
      }
    }
  }

  // ---- REMOTE BACKUPS (off-box rsync trees) ----------------------------------
  Rectangle {
    visible: snapTab.snap.status === "ok"
    Layout.fillWidth: true
    implicitHeight: capCol.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor
    Column {
      id: capCol
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      spacing: Kirigami.Units.smallSpacing / 2
      RowLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing
        Text {
          Layout.fillWidth: true
          text: "REMOTE BACKUPS — " + tm.label
          color: Kirigami.Theme.textColor
          font.bold: true
        }
        Text {
          text: snapTab.snap.total_gb
            ? Math.round((1 - snapTab.snap.free_gb / snapTab.snap.total_gb) * 100) + "% used" : ""
          color: Kirigami.Theme.disabledTextColor
          font: Kirigami.Theme.smallFont
        }
      }
      Text {
        width: parent.width
        text: (snapTab.snap.free_gb !== undefined ? snapTab.snap.free_gb : "—")
          + " GB free of " + (snapTab.snap.total_gb !== undefined ? snapTab.snap.total_gb : "—")
          + " GB · tree " + (snapTab.snap.tree_gb !== undefined && snapTab.snap.tree_gb !== null
            ? snapTab.snap.tree_gb + " GB" : "—")
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
      }
      Rectangle {
        width: parent.width
        height: 4
        radius: 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        Rectangle {
          height: parent.height
          width: snapTab.snap.total_gb
            ? Math.max(0.02, Math.min(1, 1 - snapTab.snap.free_gb / snapTab.snap.total_gb)) * parent.width : 0
          radius: 2
          color: Kirigami.Theme.activeTextColor
          Behavior on width { NumberAnimation { duration: 250 } }
        }
      }
    }
  }

  Text {
    visible: snapTab.snap.status === "loading" || snapTab.snap.status === "idle"
    text: "◌ reading " + tm.label + "…"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    SequentialAnimation on opacity {
      running: visible
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.3; duration: 600 }
      NumberAnimation { from: 0.3; to: 1; duration: 600 }
    }
  }

  RowLayout {
    visible: snapTab.snap.status === "unreachable" || snapTab.snap.status === "error"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    Text {
      Layout.fillWidth: true
      text: snapTab.snap.status === "error"
        ? "backup listing failed — " + (snapTab.snap.detail || "stamp unreadable")
        : tm.label + " unreachable"
      color: Kirigami.Theme.neutralTextColor
      font: Kirigami.Theme.smallFont
      wrapMode: Text.WordWrap
    }
    ActionPill { label: "RETRY"; hue: Kirigami.Theme.neutralTextColor; act: "fetchBackups" }
  }

  Text {
    visible: snapTab.snap.status === "empty" || snapTab.snap.status === "never"
    Layout.fillWidth: true
    text: snapTab.snap.status === "never"
      ? "no backup stamp yet — first backup pending"
      : "no backups on " + tm.label + " yet — first backup pending"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
    wrapMode: Text.WordWrap
  }

  ColumnLayout {
    visible: snapTab.snap.status === "ok"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing
    Repeater {
      model: tm.dayGroups(snapTab.snapRows, true)
      delegate: DayGroup { tm: snapTab.tm; kind: "backup" }
    }
  }
}
