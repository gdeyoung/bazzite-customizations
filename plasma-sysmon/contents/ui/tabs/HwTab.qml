import QtQuick
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import ".." as U

// HwTab — v0.8: the 2-column card grid is GONE (user: "bunch of boxes, small
// text, lots of blank space"). One full-width neofetch-style table: section
// headers + label:value rows, everything the system will tell us — board and
// product identity, serials (when not root-gated), BIOS, CPU, memory, GPU
// with driver/module/vBIOS, disks with serials+transport, NICs with drivers,
// audio, I/O counts, and the Plasma/Qt/KF6 stack levels.
//
// ListView (not a ColumnLayout) — ~35 rows cannot clip in the 640px frame.
// Delegates are 14px narrower than the viewport: the attached ScrollBar
// overlays the right edge, so that strip is its lane (same fix as ProcsTab).
// Uptime ticks via sysmon.upS (the 2s probe tick).
Item {
    id: tab
    required property var sysmon

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color muted: Kirigami.Theme.disabledTextColor
    readonly property color accent: Kirigami.Theme.highlightColor

    readonly property string uptime: {
        if (!sysmon.upS) return ""
        const up = sysmon.upS
        const d = Math.floor(up / 86400)
        const h = Math.floor((up % 86400) / 3600)
        const m = Math.floor((up % 3600) / 60)
        return (d > 0 ? d + "d " : "") + h + "h " + m + "m"
    }

    function ghz(mhz) { return mhz > 0 ? (Math.round(mhz / 100) / 10) + "GHz" : "" }

    // ---- row model: [{t:"s",label} | {t:"k",label,value,muted?}] ------------
    readonly property var rows: {
        const w = sysmon.hwinfo
        const r = []
        const sect = (label) => r.push({ t: "s", label: label })
        const kv = (label, value, isMuted) => { if (value !== "" && value !== undefined) r.push({ t: "k", label: label, value: value, muted: !!isMuted }) }
        if (!w) return r

        sect("host")
        kv("hostname", w.os.hostname)
        kv("os", w.os.pretty + " \u00B7 " + w.cpu.arch)
        kv("kernel", w.os.kernel)
        kv("uptime", tab.uptime)
        kv("boot", w.os.boot + (w.os.virt && w.os.virt !== "none" ? " \u00B7 " + w.os.virt + " guest" : " \u00B7 bare metal"))

        sect("desktop")
        kv("plasma", w.os.plasma !== "" ? "KDE Plasma " + w.os.plasma : "")
        kv("toolkit", (w.os.qt !== "" ? "Qt " + w.os.qt : "") + (w.os.kf6 !== "" ? " \u00B7 Frameworks " + w.os.kf6 : ""))

        sect("cpu")
        kv("model", w.cpu.model)
        kv("topology", w.cpu.cores !== null
           ? w.cpu.cores + " cores \u00B7 " + w.cpu.threads + " threads \u00B7 " + ghz(w.cpu.max_mhz)
             + (w.cpu.l3_kb !== null ? " \u00B7 L3 " + Math.round(w.cpu.l3_kb / 1024) + "M" : "")
           : w.cpu.threads + " threads")

        sect("memory")
        kv("installed", sysmon.fmtSizeP(w.mem.total_mb * 1048576)
           + (w.mem.type !== "" ? " \u00B7 " + w.mem.type + (w.mem.speed !== "" ? " @ " + w.mem.speed : "") : "")
           + (w.mem.banks !== null ? " \u00B7 " + w.mem.banks + " DIMM" + (w.mem.banks === 1 ? "" : "s") : ""))
        kv("swap", sysmon.swapTotalKb > 0 ? sysmon.fmtGbB(sysmon.swapTotalKb) + " total" : "none")

        sect("graphics")
        kv("gpu", w.gpu !== "" ? w.gpu : "\u2014")
        kv("driver", (w.gpu_driver !== "" ? w.gpu_driver : "")
           + (w.gpu_module !== "" ? " " + w.gpu_module : "")
           + (w.gpu_vbios !== "" ? " \u00B7 vBIOS " + w.gpu_vbios : ""), w.gpu_driver === "")
        for (let i = 0; i < w.displays.length; i++)
            kv(i === 0 ? "displays" : "", w.displays[i].connector + " \u00B7 " + w.displays[i].mode)

        sect("storage")
        for (let i = 0; i < w.disks.length; i++) {
            const d = w.disks[i]
            kv(i === 0 ? "disks" : "",
               d.dev + " \u00B7 " + d.name + " \u00B7 " + d.size
               + (d.serial !== "" ? " \u00B7 " + d.serial : "")
               + (d.transport !== "" ? " \u00B7 " + d.transport : ""))
        }

        sect("network")
        for (let i = 0; i < w.net.length; i++)
            kv(i === 0 ? "controllers" : "", w.net[i].name + (w.net[i].driver ? " \u00B7 " + w.net[i].driver : ""))

        if (w.audio.length > 0) {
            sect("audio")
            for (let i = 0; i < w.audio.length; i++)
                kv(i === 0 ? "cards" : "", w.audio[i])
        }

        sect("board")
        kv("board", (w.identity.board_vendor !== "" ? w.identity.board_vendor + " " : "")
           + w.identity.board + (w.identity.board_version !== "" ? " \u00B7 " + w.identity.board_version : ""))
        kv("serial", w.identity.board_serial !== "" ? w.identity.board_serial : "root-gated", w.identity.board_serial === "")
        if (w.identity.product !== "" && w.identity.product !== "System Product Name")
            kv("product", w.identity.product + (w.identity.product_version !== "" && w.identity.product_version !== "System Version" ? " \u00B7 " + w.identity.product_version : ""))
        kv("bios", (w.identity.bios_vendor !== "" ? w.identity.bios_vendor + " " : "")
           + w.identity.bios_version + (w.identity.bios_date !== "" ? " \u00B7 " + w.identity.bios_date : ""))

        sect("i/o")
        kv("devices", w.io.usb_devices + " USB \u00B7 " + w.io.pci_devices + " PCI" + (w.bluetooth ? " \u00B7 Bluetooth" : ""))
        if (w.battery)
            kv("battery", w.battery.manufacturer + " " + w.battery.model + " \u00B7 " + w.battery.tech
               + " \u00B7 " + w.battery.health_pct + "% health")
        return r
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: 14   // scrollbar lane — content never covered
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        boundsMovement: Flickable.StopAtBounds
        PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }
        model: tab.rows

        delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width - 14
            height: modelData.t === "s" ? 34 : (valueText.lineCount > 1 ? valueText.implicitHeight + 12 : 27)
            color: "transparent"

            // section header
            Item {
                visible: modelData.t === "s"
                anchors.fill: parent
                U.Hair { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: index > 0 }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.t === "s" ? modelData.label.toUpperCase() : ""
                    color: tab.muted
                    font.pixelSize: 12
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                }
            }

            // key : value row
            Row {
                visible: modelData.t === "k"
                anchors.fill: parent
                Item {
                    width: 150; height: parent.height
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.t === "k" ? modelData.label : ""
                        color: tab.muted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                Text {
                    id: valueText
                    width: parent.width - 150
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.t === "k" ? modelData.value : ""
                    color: modelData.t === "k" && modelData.muted ? tab.muted : tab.fg
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }

        // skeleton until hwinfo lands (one-shot fetch at applet start)
        Column {
            anchors.fill: parent
            anchors.margins: 8
            visible: !sysmon.hwinfo
            spacing: 14
            Repeater {
                model: 14
                U.SkeletonRow { w: 240 + (index % 5) * 120 }
            }
        }
    }
}
