import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

// §V-3/§V-4 EXIT NODES section: `EXIT NODES · <E>` label (hidden when E=0
// and none active), the §T-4 banner (▸ exit node: <name> + ×), and the
// candidate rows. Candidates are the online, exit-capable peers EXCLUDED
// from the census (Trayscale semantics — never duplicated).
ColumnLayout {
    id: section

    // The PlasmoidItem root via ctx — never named "root" here.
    required property var ctx

    readonly property var candidates: ctx.exitNodes
    readonly property string bannerName: ctx.exitBannerText()

    spacing: 2

    SectionLabel {
        // §V-4: renders when E > 0 OR an exit node is active.
        visible: section.candidates.length > 0 || section.bannerName !== ""
        rawText: "Exit Nodes · " + section.candidates.length
    }

    // §T-4 banner — active exit node + clear action, verbatim.
    RowLayout {
        visible: section.bannerName !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            text: "▸ exit node: " + section.bannerName
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.62
            elide: Text.ElideRight
        }

        PC3.ToolButton {
            enabled: !section.ctx.ctlBusy && section.ctx.controlsEnabled
            flat: true
            icon.name: "dialog-close"
            text: i18n("×")
            display: PC3.AbstractButton.IconOnly
            QQC2.ToolTip.text: i18n("stop using exit node")
            QQC2.ToolTip.visible: hovered
            Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
            onClicked: section.ctx.runControlOp("exit-clear", "")
        }
    }

    Repeater {
        model: section.candidates
        CandidateRow {
            Layout.fillWidth: true
            ctx: section.ctx
            peer: modelData
            result: false
        }
    }
}
