import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "Model.js" as Model

// §V-4 census cell: `● name` — and NOTHING else. Dot 0.35·gu, name 0.62·gu
// elide-right. NON-interactive by design (honest non-affordance: default
// cursor, no hover background — nothing in the census pretends to be
// clickable). Tooltip carries the identity the cell omits.
Item {
    id: cell

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx
    required property var peer
    required property bool online
    // Qt6 Repeater object-array law — see CandidateRow.
    required property var modelData

    readonly property string name: cell.ctx.peerName(cell.peer)
    readonly property string tip: {
        const parts = [String(cell.peer.DNSName || ""), String((cell.peer.TailscaleIPs || [])[0] || "")]
        const routes = cell.ctx.subnetRoutes(cell.peer)
        if (routes.length > 0) parts.push("routes: " + routes.join(", "))
        if (!cell.online) parts.push("last seen " + Model.fmtLastSeen(cell.peer.LastSeen))
        return parts.filter(function (p) { return p !== "" }).join(" · ")
    }

    implicitHeight: Kirigami.Units.gridUnit * 1.4

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.35
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.35
            radius: width / 2
            color: cell.online ? Kirigami.Theme.positiveTextColor
                               : Kirigami.Theme.disabledTextColor
        }

        PC3.Label {
            Layout.fillWidth: true
            text: cell.name
            color: cell.online ? Kirigami.Theme.textColor
                               : Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            elide: Text.ElideRight
            QQC2.ToolTip.text: cell.tip
            QQC2.ToolTip.visible: cellHover.hovered
            HoverHandler { id: cellHover }
        }
    }
}
