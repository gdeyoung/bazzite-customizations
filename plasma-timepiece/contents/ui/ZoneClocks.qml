import QtQuick
import org.kde.plasma.plasma5support 2.0

// ZoneClocks — world-clock time reader for the popup. The QML engine has no
// timezone support, so each configured zone is one read-only
// `TZ=<zone> date '+%-I:%M %p'` call a minute through the executable
// dataengine (interval re-runs connected commands), with the output
// shape-validated before it is shown — the exact scheme the Omarchy panel
// used (Process + StdioCollector there, DataSource here).
//
// Owns its data source in this file: a popup-side DataSource needs its own
// plasma5support import, and keeping handlers one-per-file is a hard porting
// rule (a second onNewData anywhere in the parent file fails the component).
Item {
    id: zones

    property var applet: null
    property var times: ({})

    // Command list, one per configured zone. Rebuilt when the configuration
    // changes (zones added/removed in the settings dialog), which rebinds
    // connectedSources and reads the new set immediately.
    readonly property var cmds: {
        const out = []
        const list = applet ? applet.worldClocks : []
        for (let i = 0; i < list.length; i++)
            out.push("TZ='" + list[i].zone + "' date '+%-I:%M %p'")
        return out
    }

    readonly property var timeShape: new RegExp("^[0-9]{1,2}:[0-9]{2} (AM|PM)$")

    DataSource {
        id: zoneSource
        engine: "executable"
        interval: 60000
        connectedSources: zones.cmds
        onNewData: (sourceName, data) => {
            const cmd = String(sourceName)
            if (cmd.indexOf("TZ='") !== 0) return
            const zone = cmd.substring(4, cmd.indexOf("'", 4))
            const out = data["exit code"] === 0 ? String(data["stdout"] || "") : ""
            const t = out.trim()
            if (zone === "" || !zones.timeShape.test(t)) return
            const next = {}
            for (const k in zones.times) next[k] = zones.times[k]
            next[zone] = t
            zones.times = next
        }
    }
}
