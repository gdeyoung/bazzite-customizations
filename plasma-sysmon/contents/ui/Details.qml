import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "tabs" as Tabs

// Details — fullRepresentation shell for com.gdeyoung.plasma.sysmon v0.7.
//
// FIXED 960x640 frame for ALL four tabs (v0.6 self-sized height per tab, so
// the popup jumped on every tab switch — dead). Sizing lives HERE and ONLY
// here: Layout.minimumWidth/Height, the harness-proven single-site rule;
// main.qml adds no hints at the instantiation site.
//
// Header: title + temp pills (the only temps in the popup) + provenance
// stamp (omastocks borrow — replaces v0.6's dead footer help row).
Item {
    id: details
    required property var sysmon

    Layout.minimumWidth: 960
    Layout.minimumHeight: 640
    // no preferred*, no implicit*, no width:/height: literals — minimum-only

    property int currentTab: sysmon.lastTab

    onCurrentTabChanged: {
        sysmon.procTabActive = (currentTab === 2)
        sysmon.saveTab(currentTab)
    }

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color cGreen: "#3fd18b"
    readonly property color cAmber: "#e5c07b"

    // probe fresh >3 missed ticks?
    readonly property bool probeStale:
        sysmon.probeStampMs <= 0 ? false
        : sysmon.clockNow - sysmon.probeStampMs > sysmon.refreshSeconds * 3000
    readonly property string stampText: {
        const d = new Date(sysmon.probeStampMs)
        const p = n => String(n).padStart(2, "0")
        const s = sysmon.probeStampMs <= 0 ? "\u2014"
            : p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
        return probeStale ? "\u25D0 stale \u00B7 " + s : "\u25CF as of " + s
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 12
        spacing: 8

        // ---- header 32 ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 8

            Text {
                text: "SysMon"
                color: details.fg
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [
                    { label: "CPU", temp: sysmon.cpuTempC },
                    { label: "GPU", temp: sysmon.gpuTempC },
                    { label: "NVMe", temp: sysmon.nvmeTempC }
                ]
                TempPill {
                    required property var modelData
                    label: modelData.label
                    temp: modelData.temp
                }
            }
            Text {
                Layout.leftMargin: 4
                text: details.stampText
                color: details.probeStale ? details.cAmber : details.muted
                font.pixelSize: 11
                font.letterSpacing: 0.4
                font.features: ({ "tnum": 1 })
            }
        }

        PC3.TabBar {
            Layout.fillWidth: true
            currentIndex: details.currentTab
            onCurrentIndexChanged: details.currentTab = currentIndex
            PC3.TabButton { text: i18n("Performance") }
            PC3.TabButton { text: i18n("Disks") }
            PC3.TabButton { text: i18n("Processes") }
            PC3.TabButton { text: i18n("Hardware") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: details.currentTab

            Tabs.PerfTab   { sysmon: details.sysmon }
            Tabs.DisksTab  { sysmon: details.sysmon }
            Tabs.ProcsTab  { sysmon: details.sysmon }
            Tabs.HwTab     { sysmon: details.sysmon }
        }
    }

    // ---- harness probes (console.error is the only channel that carries
    // payload from applet QML into the journal) ------------------------------
    Component.onCompleted: {
        sysmon.procTabActive = (currentTab === 2)
        console.error("HARNESSUnits gu=" + Kirigami.Units.gridUnit
            + " ss=" + Kirigami.Units.smallSpacing
            + " ls=" + Kirigami.Units.largeSpacing)
        console.error("HARNESSGeometry " + Math.round(width) + "x" + Math.round(height))
    }
    onWidthChanged: console.error("HARNESSGeometry " + Math.round(width) + "x" + Math.round(height))
    onHeightChanged: console.error("HARNESSGeometry " + Math.round(width) + "x" + Math.round(height))
}
