import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// Popup frame (spec §A): fixed 960x640 (screen-clamped), ONE header shared
// by all views (breadcrumb replaces page titles), StackLayout drill-down.
// The ONLY sizing hints in the package live on this root.
Item {
    id: popup

    property bool cfgShowDonut: true
    property string cfgHeroAccent: "#58a6ff"

    readonly property int depth: MosaicStore.viewStack.length
    readonly property bool scanning: MosaicStore.scanState === "running"
    readonly property string viewTitle: {
        MosaicStore.viewStack; MosaicStore.snapshot      // notifier guards
        const view = MosaicStore.currentView
        if (view.indexOf("app:") === 0) {
            const app = MosaicStore.findApp(MosaicStore.currentArg)
            return "App: " + (app ? app.name : MosaicStore.currentArg)
        }
        if (view.indexOf("cat:") === 0)
            return "Category: " + MosaicStore.categoryLabel(MosaicStore.currentArg)
        return "Mosaic"
    }

    Layout.minimumWidth: Math.min(960, Screen.width - 96)
    Layout.minimumHeight: Math.min(640, Screen.height - 96)

    Keys.onEscapePressed: function(event) {
        if (popup.depth > 1) { MosaicStore.popView(); event.accepted = true }
        else event.accepted = false     // let Plasma close the popup
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            if (popup.scanning) MosaicStore.cancelScan()
            else MosaicStore.rescan()
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace && popup.depth > 1) {
            MosaicStore.popView()
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ---- header (40): back · title · state · as-of · rescan ----------
        RowLayout {
            Layout.preferredHeight: 40
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.ToolButton {
                visible: popup.depth > 1
                text: "\u2039"
                font.pixelSize: 20
                implicitHeight: 36
                onClicked: MosaicStore.popView()
                Accessible.name: "Back"
            }
            Text {
                text: popup.viewTitle
                color: Kirigami.Theme.textColor
                font.pixelSize: 14
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 120
            }

            RowLayout {
                visible: popup.scanning
                spacing: Kirigami.Units.smallSpacing / 2 + 2
                PC3.BusyIndicator {
                    width: 14
                    height: 14
                    running: popup.scanning
                }
                Text {
                    text: "Measuring\u2026"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                    font.letterSpacing: 0.4
                }
            }
            Rectangle {
                visible: MosaicStore.scanState === "error"
                width: 8; height: 8; radius: 4
                color: "#f4405c"
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: "last scan failed"
            }
            Text {
                visible: MosaicStore.asOfText !== ""
                text: "as of " + MosaicStore.asOfText
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11
                font.letterSpacing: 0.4
            }
            PC3.Button {
                text: popup.scanning ? "Cancel" : "Rescan"
                implicitHeight: 32
                onClicked: popup.scanning ? MosaicStore.cancelScan() : MosaicStore.rescan()
            }
        }

        // ---- pages: one StackLayout, drill-down (no top tab bar) ----------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: MosaicStore.currentView.indexOf("app:") === 0 ? 1
                : MosaicStore.currentView.indexOf("cat:") === 0 ? 2 : 0

            OverviewPage {
                showDonut: popup.cfgShowDonut
                heroAccent: popup.cfgHeroAccent
            }
            AppDetailPage {}
            CategoryPage {}
        }
    }
}
