import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V8-2 preference toggle row — Omarchy `Toggle` pattern (Panel.qml
// 743–782) in fleet-DL control grammar: label + one-line dim
// description left, switch pill on the right rail; full-row click
// target; busy/disabled never zero-opacity (fleet DL states law).
PC3.AbstractButton {
    id: row

    property string label: ""
    property string description: ""
    property bool busy: false
    // `checked` is INHERITED (FINAL on AbstractButton — cannot
    // redeclare); bind it at use sites like any button property.

    signal flipped(bool on)

    Layout.fillWidth: true
    implicitHeight: Math.max(Kirigami.Units.gridUnit * 2.6,
                             col.implicitHeight + Kirigami.Units.smallSpacing)

    hoverEnabled: true
    opacity: enabled ? 1.0 : 0.45

    background: Rectangle {
        color: row.pressed ? Kirigami.Theme.highlightColor
               : row.hovered ? Kirigami.Theme.highlightColor : "transparent"
        opacity: row.pressed ? 0.10 : row.hovered ? 0.05 : 1
        radius: Kirigami.Units.smallSpacing
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            id: col
            Layout.fillWidth: true
            spacing: 0

            PC3.Label {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.75
            }
            PC3.Label {
                Layout.fillWidth: true
                visible: row.description !== ""
                text: row.description
                elide: Text.ElideRight
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }

        // Switch pill — fleet-DL: ~46×26 track, thumb 22px, accent only
        // when checked (one accent meaning). Hand-rolled so LIGHT/DARK
        // resolve from the theme with no hardcoded hex.
        Item {
            id: track
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.55
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.45
            Layout.alignment: Qt.AlignVCenter
            opacity: row.busy ? 0.4 : 1.0

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: row.checked ? Kirigami.Theme.highlightColor
                       : Kirigami.Theme.backgroundColor
                opacity: row.checked ? 0.85 : 1.0
                border.width: 1
                border.color: row.checked ? Kirigami.Theme.highlightColor
                              : Qt.alpha(Kirigami.Theme.textColor, 0.25)
            }
            Rectangle {
                id: thumb
                width: parent.height - Kirigami.Units.smallSpacing * 0.7
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: row.checked
                   ? parent.width - width - Kirigami.Units.smallSpacing * 0.35
                   : Kirigami.Units.smallSpacing * 0.35
                color: row.checked ? Kirigami.Theme.highlightedTextColor
                       : Kirigami.Theme.textColor
                opacity: row.checked ? 1.0 : 0.7
                Behavior on x {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    onClicked: if (!row.busy) row.flipped(!row.checked)

    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.description: description
    Accessible.checked: checked
}
