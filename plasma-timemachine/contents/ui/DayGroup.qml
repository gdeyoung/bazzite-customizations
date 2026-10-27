import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// DayGroup — collapsible day section for the Snapshots tab (whole-row header
// target; caret is the icon, not the target). Ported from the omarchy
// DetailPopup DayGroup. kind: "backup" → remote rsync-tree rows,
// "snapshot" → local snapper rows. This file owns the ONE onClicked used by
// every day header (repo checker rule).
Item {
  id: dgroup

  required property var tm
  required property var modelData
  property string kind: "backup"
  property string subvol: "/"

  readonly property var rows: dgroup.modelData ? dgroup.modelData.rows : []
  readonly property bool expanded: tm.isExpanded(dgroup.modelData ? dgroup.modelData.key : "")

  implicitHeight: dgCol.implicitHeight

  Column {
    id: dgCol
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: Kirigami.Units.smallSpacing / 2

    Rectangle {
      width: parent.width
      height: Kirigami.Units.gridUnit * 2
      radius: Kirigami.Units.smallSpacing
      color: dgMa.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.06) : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Text {
          Layout.alignment: Qt.AlignVCenter
          text: "▸"
          color: Kirigami.Theme.textColor
          rotation: dgroup.expanded ? 90 : 0
          Behavior on rotation { NumberAnimation { duration: 120 } }
        }
        Text {
          Layout.alignment: Qt.AlignVCenter
          text: dgroup.modelData ? dgroup.modelData.label : ""
          color: Kirigami.Theme.textColor
          font.bold: true
        }
        Text {
          visible: dgroup.modelData
            && (dgroup.modelData.label === "Today" || dgroup.modelData.label === "Yesterday")
          Layout.alignment: Qt.AlignVCenter
          text: dgroup.modelData ? dgroup.modelData.sub : ""
          color: Kirigami.Theme.disabledTextColor
          font: Kirigami.Theme.smallFont
        }
        Item { Layout.fillWidth: true }
        Text {
          Layout.alignment: Qt.AlignVCenter
          text: dgroup.rows.length + " " + (dgroup.modelData ? dgroup.modelData.noun : "")
          color: Kirigami.Theme.disabledTextColor
          font: Kirigami.Theme.smallFont
        }
        Text {
          visible: dgroup.kind === "backup" && dgroup.modelData && dgroup.modelData.bucket
          Layout.alignment: Qt.AlignVCenter
          text: dgroup.modelData && dgroup.modelData.bucket ? tm.bucketLetter(dgroup.modelData.bucket) : ""
          color: tm.bucketColor(dgroup.modelData.bucket)
          font: Kirigami.Theme.smallFont
          font.bold: true
        }
      }

      MouseArea {
        id: dgMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tm.toggleDay(dgroup.modelData.key)
      }
    }

    Item {
      visible: dgroup.expanded
      anchors { left: parent.left; right: parent.right; leftMargin: Kirigami.Units.smallSpacing * 2 }
      implicitHeight: dgRows.implicitHeight

      Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
      }

      Column {
        id: dgRows
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Kirigami.Units.smallSpacing / 2

        Repeater {
          id: dgRepeater
          model: dgroup.rows.length > tm.snapshotRows
            ? dgroup.rows.slice(0, tm.snapshotRows) : dgroup.rows

          delegate: Item {
            id: drow
            required property var modelData
            width: parent ? parent.width : 0
            implicitHeight: dgroup.kind === "backup"
              ? Kirigami.Units.gridUnit * 2.8 : Kirigami.Units.gridUnit * 2

            RowLayout {
              anchors.fill: parent
              spacing: Kirigami.Units.smallSpacing

              // remote backup row: id + latest badge / meta line
              ColumnLayout {
                visible: dgroup.kind === "backup"
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Kirigami.Units.smallSpacing
                  Text {
                    Layout.fillWidth: true
                    text: drow.modelData.id
                    color: Kirigami.Theme.textColor
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Rectangle {
                    visible: drow.modelData.id === tm.snap.latest
                    implicitWidth: latestTxt.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: latestTxt.implicitHeight + 2
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.activeTextColor, 0.18)
                    Text {
                      id: latestTxt
                      anchors.centerIn: parent
                      text: "latest"
                      color: Kirigami.Theme.textColor
                      font: Kirigami.Theme.smallFont
                      font.bold: true
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: tm.fmtAgo(drow.modelData.t) + " · " + tm.fmtIdDate(drow.modelData.id)
                    + " · " + tm.fmtSize(drow.modelData.mb)
                    + (drow.modelData.dur_s ? " · " + drow.modelData.dur_s + "s" : "")
                  color: Kirigami.Theme.disabledTextColor
                  font: Kirigami.Theme.smallFont
                  elide: Text.ElideRight
                }
              }

              // local snapshot row: time + type badge + description
              RowLayout {
                visible: dgroup.kind === "snapshot"
                Layout.alignment: Qt.AlignVCenter
                spacing: Kirigami.Units.smallSpacing
                Text {
                  text: (drow.modelData.iso && drow.modelData.iso.length >= 16)
                    ? drow.modelData.iso.substring(11, 16) : "—"
                  color: Kirigami.Theme.textColor
                  font.bold: true
                }
                Rectangle {
                  implicitWidth: tbTxt.implicitWidth + Kirigami.Units.smallSpacing * 2
                  implicitHeight: tbTxt.implicitHeight + 2
                  radius: height / 2
                  color: Qt.alpha(drow.modelData.type === "pre" ? Kirigami.Theme.neutralTextColor
                    : drow.modelData.type === "post" ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.activeTextColor, 0.14)
                  Text {
                    id: tbTxt
                    anchors.centerIn: parent
                    text: drow.modelData.desc === "manual" ? "manual"
                      : drow.modelData.type === "pre" ? "pre"
                      : drow.modelData.type === "post" ? "post" : "timeline"
                    color: drow.modelData.type === "pre" ? Kirigami.Theme.neutralTextColor
                      : drow.modelData.type === "post" ? Kirigami.Theme.positiveTextColor
                      : Kirigami.Theme.activeTextColor
                    font: Kirigami.Theme.smallFont
                    font.bold: true
                  }
                }
                Text {
                  Layout.fillWidth: true
                  text: (drow.modelData.desc === "timeline" || drow.modelData.desc === "snap-pac")
                    ? "" : (drow.modelData.desc || "")
                  color: Kirigami.Theme.disabledTextColor
                  font: Kirigami.Theme.smallFont
                  elide: Text.ElideRight
                }
              }

              Item { Layout.fillWidth: true }

              ActionPill {
                visible: dgroup.kind === "backup"
                label: "BROWSE"
                act: "copyText"
                arg: "sshfs " + (tm.snap.scp_prefix || "<host>:/…/timemachine/backups/")
                  + drow.modelData.id + " ~/tm"
              }
              ActionPill {
                visible: dgroup.kind === "backup"
                label: "RECOVER"
                hue: Kirigami.Theme.positiveTextColor
                act: "preselect"
                argMode: "recoverRemote"
                arg: drow.modelData.id
              }
              ActionPill {
                visible: dgroup.kind === "snapshot"
                label: "BROWSE"
                act: "openPath"
                argMode: "path"
                arg: tm.localSnapPath(dgroup.subvol, drow.modelData.id)
              }
              ActionPill {
                visible: dgroup.kind === "snapshot"
                label: "COPY PATH"
                act: "copyText"
                arg: tm.localSnapPath(dgroup.subvol, drow.modelData.id)
              }
            }
          }
        }

        Text {
          visible: dgroup.rows.length > tm.snapshotRows
          text: "showing first " + tm.snapshotRows + " of " + dgroup.rows.length + " this day"
          color: Kirigami.Theme.disabledTextColor
          font: Kirigami.Theme.smallFont
        }
      }
    }
  }
}
