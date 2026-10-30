import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import ".." as U

// HwTab — v0.7: hardware data re-flowed from one long column into a
// 2-column card grid (456|16|456). Uptime ticks via sysmon.upS (the 2s
// probe tick) — an epoch-math tick here raced component creation
// (hwLoadedAt stayed 0 and rendered Date.now()/1000 = ~20700 days).
Item {
    id: tab
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor

    readonly property string uptime: {
        if (!sysmon.upS) return ""
        const up = sysmon.upS
        const d = Math.floor(up / 86400)
        const h = Math.floor((up % 86400) / 3600)
        const m = Math.floor((up % 3600) / 60)
        return (d > 0 ? d + "d " : "") + h + "h " + m + "m"
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ColumnLayout {
            Layout.preferredWidth: 456
            Layout.fillHeight: true
            spacing: 12

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Identity"
                rightText: sysmon.hwinfo && sysmon.hwinfo.identity ? (sysmon.hwinfo.identity.product || "") : ""
                U.HwRow {
                    label: "board"
                    value: sysmon.hwinfo && sysmon.hwinfo.identity ? (sysmon.hwinfo.identity.board || "\u2014") : "\u2014"
                }
                U.HwRow {
                    label: "bios"
                    value: sysmon.hwinfo && sysmon.hwinfo.identity
                        ? ((sysmon.hwinfo.identity.bios_version || "\u2014") + "  (" + (sysmon.hwinfo.identity.bios_date || "?") + ")")
                        : "\u2014"
                }
                U.HwRow {
                    label: "os"
                    value: sysmon.hwinfo ? ((sysmon.hwinfo.os.pretty || "") + " \u00B7 kernel " + sysmon.hwinfo.os.kernel) : ""
                }
                U.HwRow { label: "uptime"; value: tab.uptime }
            }

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Memory"
                U.HwRow {
                    label: "memory"
                    show: sysmon.hwinfo && !!sysmon.hwinfo.mem
                    value: sysmon.hwinfo
                        ? (sysmon.fmtSizeP(sysmon.hwinfo.mem.total_mb * 1048576)
                           + (sysmon.hwinfo.mem.type ? " \u00B7 " + sysmon.hwinfo.mem.type + " " + sysmon.hwinfo.mem.speed : ""))
                        : ""
                }
                U.HwRow {
                    label: "swap"
                    value: sysmon.fmtGbB(sysmon.swapTotalKb) + " total"
                }
            }

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Devices"
                U.HwRow {
                    label: "bluetooth"
                    value: sysmon.hwinfo ? (sysmon.hwinfo.bluetooth ? "yes" : "no") : ""
                }
                U.HwRow {
                    label: "count"
                    value: sysmon.hwinfo ? (sysmon.hwinfo.io.usb_devices + " USB \u00B7 " + sysmon.hwinfo.io.pci_devices + " PCI") : ""
                }
                Repeater {
                    model: sysmon.hwinfo && sysmon.hwinfo.audio ? sysmon.hwinfo.audio : []
                    U.HwRow {
                        required property string modelData
                        required property int index
                        label: index === 0 ? "audio" : ""
                        value: modelData
                    }
                }
            }
        }

        ColumnLayout {
            Layout.preferredWidth: 456
            Layout.fillHeight: true
            spacing: 12

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "CPU"
                U.HwRow { label: "model"; value: sysmon.hwinfo ? sysmon.hwinfo.cpu.model : "" }
                U.HwRow {
                    label: "cores"
                    show: sysmon.hwinfo && sysmon.hwinfo.cpu.cores !== null
                    value: sysmon.hwinfo
                        ? (sysmon.hwinfo.cpu.cores + "c / " + sysmon.hwinfo.cpu.threads + "t \u00B7 "
                           + Math.round(sysmon.hwinfo.cpu.max_mhz / 100) / 10 + "GHz \u00B7 L3 "
                           + Math.round(sysmon.hwinfo.cpu.l3_kb / 1024) + "M")
                        : ""
                }
            }

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "GPU \u00B7 Displays"
                U.HwRow { label: "gpu"; value: sysmon.hwinfo ? (sysmon.hwinfo.gpu || "\u2014") : "\u2014" }
                Repeater {
                    model: sysmon.hwinfo && sysmon.hwinfo.displays ? sysmon.hwinfo.displays : []
                    U.HwRow {
                        required property var modelData
                        required property int index
                        label: index === 0 ? "display" : ""
                        value: modelData.connector + " \u00B7 " + modelData.mode
                    }
                }
            }

            U.SectionCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Storage \u00B7 Net"
                Repeater {
                    model: sysmon.hwinfo && sysmon.hwinfo.disks ? sysmon.hwinfo.disks : []
                    U.HwRow {
                        required property var modelData
                        required property int index
                        label: index === 0 ? "storage" : ""
                        value: modelData.name + " \u00B7 " + modelData.size
                    }
                }
                Repeater {
                    model: sysmon.hwinfo && sysmon.hwinfo.net ? sysmon.hwinfo.net : []
                    U.HwRow {
                        required property var modelData
                        required property int index
                        label: index === 0 ? "network" : ""
                        value: modelData.name + (modelData.driver ? " \u00B7 " + modelData.driver : "")
                    }
                }
                U.HwRow {
                    label: "battery"
                    show: sysmon.hwinfo && !!sysmon.hwinfo.battery
                    value: sysmon.hwinfo && sysmon.hwinfo.battery
                        ? (sysmon.hwinfo.battery.manufacturer + " " + sysmon.hwinfo.battery.model
                           + " \u00B7 " + sysmon.hwinfo.battery.tech + " \u00B7 " + sysmon.hwinfo.battery.health_pct + "% health")
                        : ""
                }
            }
        }
    }

    // skeleton until hwinfo lands (one-shot fetch at applet start)
    Column {
        anchors.centerIn: parent
        visible: !sysmon.hwinfo
        spacing: 14
        U.SkeletonRow { w: 320 }
        U.SkeletonRow { w: 420 }
        U.SkeletonRow { w: 380 }
        U.SkeletonRow { w: 300 }
    }
}
