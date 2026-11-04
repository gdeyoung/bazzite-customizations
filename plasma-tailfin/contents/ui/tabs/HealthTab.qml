import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".."

// §R-5 Health tab — backend, warnings, operator, provenance. Standing
// content on every path: even when the backend is down, this tab shows
// the backend verdict, the operator gate result, and the stamp.
Item {
    id: tab

    required property var ctx

    // Backend line: normal = polled state CAPS + poll interval; edge
    // states substitute their copy here (§R-8) with a negative dot.
    readonly property bool backendTroubled:
        ctx.edgeState !== "ok" || ctx.needsLogin
    readonly property string backendLine: {
        if (ctx.edgeState === "backdown")
            return "TAILSCALED NOT RESPONDING · RETRY EVERY " + ctx.pollSeconds + " S"
        if (ctx.edgeState === "binmissing")
            return "TAILSCALE BINARY MISSING · INSTALL TAILSCALE"
        if (ctx.edgeState === "parseerror")
            return "STATUS ERROR · RETRYING"
        if (ctx.needsLogin)
            return "NEEDS LOGIN"
        return ctx.status && ctx.status.backendState
               ? ctx.status.backendState.toUpperCase() : "STOPPED"
    }
    readonly property string pollLine:
        "POLL EVERY " + ctx.pollSeconds + " S"

    // Provenance stamp (§R-5): local tick time; goes stale past 3× the
    // poll interval (sysmon stamp semantics).
    readonly property bool stampStale:
        ctx.statusStampMs > 0
        && ctx.clockNow > 0
        && (ctx.clockNow - ctx.statusStampMs) > ctx.pollSeconds * 3000

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        SectionLabel { rawText: "BACKEND" }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.gridUnit * 0.35
                implicitHeight: Kirigami.Units.gridUnit * 0.35
                radius: width / 2
                color: tab.backendTroubled
                       ? Kirigami.Theme.negativeTextColor
                       : (tab.ctx.running
                          ? Kirigami.Theme.positiveTextColor
                          : Kirigami.Theme.negativeTextColor)
            }

            Text {
                Layout.fillWidth: true
                text: tab.backendLine
                      + (tab.ctx.edgeState === "ok" && !tab.ctx.needsLogin
                         ? " · " + tab.pollLine : "")
                color: tab.backendTroubled
                       ? Kirigami.Theme.negativeTextColor
                       : Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.62
                font.bold: true
                elide: Text.ElideRight
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: tab.ctx.needsLogin
            text: "NEEDS LOGIN · RUN: tailscale login"
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }

        SectionLabel { rawText: "WARNINGS" }

        Repeater {
            model: tab.ctx.health

            PC3.Label {
                required property var modelData
                Layout.fillWidth: true
                text: "⚠ " + modelData
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WrapAnywhere
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: tab.ctx.health.length === 0
            text: "NO WARNINGS"
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }

        SectionLabel { rawText: "OPERATOR" }

        Text {
            Layout.fillWidth: true
            text: {
                if (tab.ctx.gateState === "enabled")
                    return "CONTROL ENABLED · " + tab.ctx.gateUser
                if (tab.ctx.gateState === "disabled") {
                    return tab.ctx.gateOperator !== ""
                        ? "CONTROL DISABLED · " + tab.ctx.gateOperator
                        : "CONTROL DISABLED"
                }
                return "CONTROL UNAVAILABLE · TAILSCALED NOT RESPONDING"
            }
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            elide: Text.ElideRight
        }

        // §T-1 hint beneath the verdict when control is off.
        PC3.Label {
            Layout.fillWidth: true
            visible: tab.ctx.gateState !== "enabled"
                     && tab.ctx.gateHint !== ""
            text: tab.ctx.gateHint
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WrapAnywhere
        }

        SectionLabel { rawText: "PROVENANCE" }

        PC3.Label {
            Layout.fillWidth: true
            visible: tab.ctx.statusStampMs > 0
            text: {
                const t = Qt.formatDateTime(
                    new Date(tab.ctx.statusStampMs), "hh:mm:ss")
                return tab.stampStale ? "◐ STALE · " + t : "● AS OF " + t
            }
            color: tab.stampStale
                   ? Kirigami.Theme.neutralTextColor
                   : Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }

        Item { Layout.fillHeight: true }
    }
}
