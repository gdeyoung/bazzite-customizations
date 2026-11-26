import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// RecoveryTab — tab 4 of the TimeMachine popup. Ported from the omarchy
// DetailPopup RECOVERY page: plaintext emergency card with copyable
// commands, the restore-a-file flow (tm-restore.sh --files '<glob>' via the
// applet's runScript dispatcher), and the backup layout mini-map.
// Non-destructive by design: restore stages to scratch; merging back is a
// deliberate act (merge, never overwrite).
ColumnLayout {
  id: recTab

  required property var tm

  readonly property var probe: tm.probe || ({})
  readonly property var snap: tm.snap || ({ status: "idle" })

  Layout.fillWidth: true
  spacing: Kirigami.Units.smallSpacing * 2

  Text {
    Layout.fillWidth: true
    text: "Files are plaintext on " + tm.label + " — no keys, no tooling"
    color: Kirigami.Theme.textColor
    font.bold: true
    font.pixelSize: Kirigami.Units.gridUnit * 0.7
    wrapMode: Text.WordWrap
  }

  RowLayout {
    visible: tm.recoverSnapshot.length > 0
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2
    Text {
      Layout.fillWidth: true
      text: "recovering from " + tm.recoverSnapshot
      color: Kirigami.Theme.positiveTextColor
      font: Kirigami.Theme.smallFont
    }
    ActionPill { label: "CLEAR"; act: "clearRecover" }
  }

  component CommandRow: Rectangle {
    id: crow
    property string label: ""
    property string cmd: ""
    property string note: ""
    property string runScript: ""   // non-empty → RUN pill calls the engine
    Layout.fillWidth: true
    implicitHeight: crowCol.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor

    Column {
      id: crowCol
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      spacing: Kirigami.Units.smallSpacing / 2

      RowLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing
        Text { text: crow.label; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Item { Layout.fillWidth: true }
        ActionPill { label: "COPY"; act: "copyText"; arg: crow.cmd }
        ActionPill {
          visible: crow.runScript.length > 0
          label: "RUN"
          hue: Kirigami.Theme.positiveTextColor
          act: "runScript"
          arg: crow.runScript
        }
      }
      Text {
        width: parent.width
        text: crow.cmd
        color: Kirigami.Theme.textColor
        wrapMode: Text.WrapAnywhere
      }
      Text {
        visible: crow.note.length > 0
        width: parent.width
        text: crow.note
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
      }
    }
  }

  CommandRow {
    label: "restore-a-file"
    cmd: "tm-restore.sh --files '<path-to-file>'   # stages into the scratch dir"
    note: "swap in your path, then run it from a terminal — stages the newest backup's matching files. Merge, never overwrite."
  }
  CommandRow {
    label: "browse-latest"
    cmd: "sshfs " + (recTab.snap.scp_prefix || "<host>:/…/timemachine/backups/") + "latest ~/tm"
    note: "mount the newest backup as a folder — browse it in any file manager"
  }
  CommandRow {
    label: "fetch-one-file"
    cmd: "scp " + (recTab.snap.scp_prefix || "<host>:/…/timemachine/backups/")
      + (tm.recoverSnapshot || recTab.snap.latest || recTab.probe.backup || "<id>") + "/<path-to-file> ."
    note: tm.recoverSnapshot.length > 0
      ? "backup preselected from the Snapshots tab"
      : "swap in the backup id from the Snapshots tab"
  }
  CommandRow {
    label: "full-restore"
    cmd: "tm-restore.sh --latest"
    note: "stages to a scratch dir — merge, never overwrite; ask before restoring"
    runScript: "--latest"
  }
  CommandRow {
    label: "restore-drill"
    cmd: "tm-restore.sh --drill"
    note: "pull + verify sentinel files (PASS/FAIL) — also on the Status tab"
    runScript: "--drill"
  }

  Text {
    Layout.fillWidth: true
    text: "restore = merge (ask first)"
    color: Kirigami.Theme.disabledTextColor
    font: Kirigami.Theme.smallFont
  }

  // backup layout mini-map
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: mapCol.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor

    Column {
      id: mapCol
      anchors.fill: parent
      anchors.margins: Kirigami.Units.smallSpacing
      spacing: 2

      Text { text: "backup layout"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
      Repeater {
        model: Array.isArray(recTab.snap.rows) ? recTab.snap.rows.slice(0, 3) : []
        delegate: RowLayout {
          id: mapRow
          required property var modelData
          required property int index
          spacing: Kirigami.Units.smallSpacing
          Text { text: mapRow.index === 0 ? "├─" : "│ "; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
          Text {
            text: mapRow.modelData.id + "/"
            color: Kirigami.Theme.textColor
            font.bold: mapRow.modelData.id === recTab.snap.latest
          }
          Text {
            Layout.fillWidth: true
            text: mapRow.index === 0 ? "complete browsable HOME" : ""
            visible: mapRow.index === 0
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideLeft
          }
        }
      }
      RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Text { text: "└─"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        Text {
          text: "latest → " + (recTab.snap.latest || "…")
          color: Kirigami.Theme.textColor
          font.bold: true
        }
      }
    }
  }
}
