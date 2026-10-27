import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// com.gdeyoung.plasma.weatherx — Plasma 6 port of gdeyoung.weather (Omarchy,
// github.com/gdeyoung/omarchy-weather @ 93758c0).
//
// Architecture mirrors the Omarchy widget: one fetch pipeline per location
// writes ~/.cache/gdeyoung.weatherx/<key>.json (Open-Meteo forecast + air
// quality merged by jq, atomic tmp+mv), and the pipeline's stdout carries the
// same merged JSON back so the panel chip updates the moment a fetch lands —
// the bar label and popup read the same files and can never disagree.
//
// "here" resolves from plasmoid configuration (latitude/longitude, or a place
// name that geocodes first). No configured location → placeholder glyph only,
// first-run hint in the popup. This is a public repo: nothing personal ships.
PlasmoidItem {
    id: root

    // ---- Config (KConfig XT; replaces Omarchy's settings/weather.json) -----
    readonly property string units: String(Plasmoid.configuration.units || "imperial")
    readonly property string barExtra: String(Plasmoid.configuration.barExtra || "temp")
    readonly property int refreshMin: Math.max(5, parseInt(Plasmoid.configuration.refreshMin, 10) || 15)
    readonly property real cfgLat: Number(Plasmoid.configuration.latitude) || 0
    readonly property real cfgLon: Number(Plasmoid.configuration.longitude) || 0
    readonly property string cfgName: String(Plasmoid.configuration.locationName || "")
    // Coords count as set only when at least one is non-zero (0,0 = unset).
    readonly property bool hasCoords: isFinite(cfgLat) && isFinite(cfgLon) && (cfgLat !== 0 || cfgLon !== 0)
    // Any change to the home location or units re-resolves "here".
    readonly property string hereSpec: cfgLat + "," + cfgLon + "," + cfgName + "," + units

    readonly property var pinned: Model.parsePinned(Plasmoid.configuration.pinnedLocations || Model.DEFAULT_PINNED)

    function setPinned(list) {
        Plasmoid.configuration.pinnedLocations = JSON.stringify(list)
    }

    function configure() {
        Plasmoid.internalAction("configure").trigger()
    }

    // ---- state ---------------------------------------------------------------
    // wxData is "here"'s merged JSON — drives the panel chip + tooltip.
    property var wxData: null
    property string fetchTarget: ""
    property string pendingGeocodeKey: ""

    readonly property var cur: wxData && wxData.forecast ? wxData.forecast.current : null
    readonly property string barLabel: Model.barLabel(barExtra, wxData && wxData.forecast ? wxData.forecast : null)
    readonly property string iconGlyph: cur
        ? Model.glyph(cur.weather_code, cur.is_day === 0 || cur.is_day === false)
        : "🌡️"
    readonly property string condLine: cur ? Model.condText(cur.weather_code) : ""

    function parseJson(txt) {
        try {
            return txt ? JSON.parse(txt) : null
        } catch (e) {
            return null
        }
    }

    // ---- per-location state files (file bus, verbatim from the Omarchy port)
    function stateFile(key) {
        // $HOME stays literal here — the executable dataengine runs commands
        // through a shell, which expands it. No QML-side HOME needed.
        return "$HOME/" + Model.STATE_DIR + "/" + key + ".json"
    }

    // One bash pipeline per location (same pipeline as BarWidget.qml upstream,
    // plus a trailing `cat` so the merged JSON comes back on stdout). jq runs
    // with -c — the fleet contract is ONE strict JSON line per tick; a
    // pretty-printed state file would parse as garbage on last-line reads.
    function fetchKey(key, lat, lon) {
        if (lat === undefined || lon === undefined || String(lat) === "" || String(lon) === "")
            return
        fetchTarget = key
        pendingGeocodeKey = ""
        var fUrl = Model.buildForecastUrl(lat, lon, units)
        var aUrl = Model.buildAirUrl(lat, lon)
        var file = stateFile(key)
        var stamp = new Date().toISOString()
        execSource.connectSource(
            "mkdir -p " + JSON.stringify("$HOME/" + Model.STATE_DIR)
            + " ; f=$(curl -fsS --max-time 10 " + JSON.stringify(fUrl) + ") || exit 0"
            + " ; a=$(curl -fsS --max-time 10 " + JSON.stringify(aUrl)
            + " | jq -c '.current // {}' 2>/dev/null || echo '{}')"
            + " ; [ -n \"$a\" ] || a='{}'"
            + " ; jq -c -n --argjson f \"$f\" --argjson a \"$a\" --arg s " + JSON.stringify(stamp)
            + " '{forecast: $f, air: $a, fetchedAt: $s}' > " + JSON.stringify(file + ".tmp")
            + " && mv " + JSON.stringify(file + ".tmp") + " " + JSON.stringify(file)
            + " ; cat " + JSON.stringify(file))
    }

    // "here" resolves to configured lat,lon; a stored name geocodes first;
    // with no configured location the widget stays a placeholder (no fake data).
    function fetchHere() {
        if (hasCoords)
            fetchKey("here", cfgLat, cfgLon)
        else if (cfgName !== "")
            geocodeThenFetch(cfgName, "here")
    }

    function geocodeThenFetch(name, key) {
        pendingGeocodeKey = key
        execSource.connectSource("curl -fsS --max-time 8 " + JSON.stringify(Model.buildGeocodeUrl(name))
            + " | jq -c '{lat: .results[0].latitude, lon: .results[0].longitude}'")
    }

    // Heartbeat side-channel (categorized logging hides console.log): if
    // /tmp/plasma-weatherx-hb.json advances, the whole chain works.
    function writeHb(obj) {
        var line = JSON.stringify({
            t: Date.now(),
            key: fetchTarget,
            temp: obj.forecast && obj.forecast.current ? obj.forecast.current.temperature_2m : null
        })
        execSource.connectSource("echo " + JSON.stringify(line) + " > /tmp/plasma-weatherx-hb.json")
    }

    // ---- Data plumbing: one fire-once executable source, dispatch by command
    DataSource {
        id: execSource
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            var cmd = String(sourceName)
            // One strict JSON line per tick: every jq below runs with -c, so
            // the LAST stdout line IS the whole document. Parsing the last
            // line (not whole stdout) everywhere makes a stray multi-line
            // payload fail visibly as a parse drop instead of corrupting UI.
            var out = (data["stdout"] || "").trim().split("\n").pop() || ""
            if (cmd.indexOf("echo ") === 0) {
                // heartbeat write — nothing to apply
            } else if (cmd.indexOf("geocoding-api") >= 0) {
                var p = root.parseJson(out)
                if (p && p.lat !== undefined && root.pendingGeocodeKey !== "")
                    root.fetchKey(root.pendingGeocodeKey, p.lat, p.lon)
            } else {
                // fetch pipeline: stdout is the merged {forecast, air, fetchedAt}
                var obj = root.parseJson(out)
                if (obj && obj.forecast) {
                    if (root.fetchTarget === "here")
                        root.wxData = obj
                    root.writeHb(obj)
                }
            }
            execSource.disconnectSource(sourceName)
        }
    }

    // Periodic refresh of the device location (panel chip stays live even
    // when the popup never opens). Cold start: triggeredOnStart fetches now;
    // stale cache renders meanwhile once the popup reads it.
    Timer {
        id: forecastTimer
        interval: root.refreshMin * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchHere()
    }

    onHereSpecChanged: Qt.callLater(fetchHere)

    onWxDataChanged: {
        Plasmoid.toolTipSubText = barLabel !== "" && condLine !== ""
            ? barLabel + " " + condLine
            : (barLabel !== "" ? barLabel : "Location not set")
    }

    Component.onCompleted: {
        Plasmoid.toolTipMainText = "WeatherX"
        Plasmoid.toolTipSubText = "Location not set"
        Plasmoid.toolTipTextFormat = 0   // plain text
    }

    function cycleBarMode() {
        Plasmoid.configuration.barExtra = Model.nextBarMode(barExtra)
    }

    // ==========================================================================
    // COMPACT representation (panel): weather glyph + temperature, like the
    // Omarchy BarWidget. Left click opens the popup; right click cycles the
    // label mode (temp → temp + condition → icon only).
    // ==========================================================================
    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        implicitWidth: compactRow.implicitWidth + Kirigami.Units.gridUnit * 3
        implicitHeight: parent ? parent.height : Kirigami.Units.gridUnit * 2

        Row {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: root.iconGlyph
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.95
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.barLabel
                visible: root.barLabel !== ""
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.58
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.cycleBarMode()
            else
                root.expanded = !root.expanded
        }
    }

    // ==========================================================================
    // FULL representation (popup): tabbed panel — Here + pinned places + [+]
    // search, hero, details grid, next-hours strip, 7-day, radar, sun.
    // ==========================================================================
    fullRepresentation: WeatherPanel {
        wx: root
    }
}
