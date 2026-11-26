import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasma5support 2.0
import org.kde.kirigami as Kirigami
import "Model.js" as Model

// WeatherPanel — fullRepresentation popup for com.gdeyoung.plasma.weatherx.
// Ported from gdeyoung/omarchy-weather Panel.qml (Quickshell). Tabs: [Here]
// (device location from plasmoid config) + pinned places + [+] geocode search.
// Every tab renders hero, details grid with level bars, remaining-hours strip,
// 7-day forecast, sun times and the keyless radar map (Esri dark basemap +
// RainViewer frame) from its own cached state file in
// ~/.cache/gdeyoung.weatherx/. All clickable chrome lives in TabChip /
// ChipButton / ResultRow / SearchField so this file holds at most one handler
// per signal NAME (Plasma loads the whole applet lazily; a duplicate property
// handler anywhere blocks it). One Timer serves both polls: 2 s tab reads,
// radar frame every 5 min on the same tick stream.
Item {
    id: panel

    // Popup text scale (Settings → Popup text size). Base 1.25× for
    // readability at 4K/120% — the user-adjustable multiplier rides on top.
    readonly property real scaleF: 1.25 * Math.max(0.5, Number(panel.settings_scale) || 1.0)
    property real settings_scale: 1.0   // set by main.qml from configuration

    required property var wx   // the PlasmoidItem root (main.qml)

    // ---- tabs -------------------------------------------------------------
    readonly property var tabs: {
        var t = [{ key: "here",
                   name: Model.locationName(
                       wx.hasCoords || wx.cfgName !== "" ? { name: wx.cfgName } : null,
                       "Here"),
                   pinned: false }]
        for (var i = 0; i < wx.pinned.length; i++)
            t.push({ key: wx.pinned[i].key, name: wx.pinned[i].name,
                     pinned: true, lat: wx.pinned[i].lat, lon: wx.pinned[i].lon })
        return t
    }
    property string activeKey: "here"
    readonly property var activeTab: {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].key === activeKey)
                return tabs[i]
        return tabs[0]
    }
    // First-run: no configured location and nothing pinned → setup hint.
    readonly property bool needsSetup: !wx.hasCoords && wx.cfgName === "" && wx.pinned.length === 0

    // ---- active tab data (its own state file, read back via cat) ----------
    property var tabData: null
    property string readKey: ""

    function switchTab(key) {
        activeKey = key
        tabData = null
        readTab()
    }

    function readTab() {
        var t = activeTab
        if (!t)
            return
        readKey = t.key
        panelExec.connectSource("cat " + wx.stateFile(t.key))
    }

    function maybeFetchActive() {
        var t = activeTab
        if (!t)
            return
        var stale = true
        if (tabData && tabData.fetchedAt) {
            var age = Date.now() - new Date(tabData.fetchedAt).getTime()
            stale = !(age >= 0 && age < 15 * 60000)
        }
        if (stale) {
            if (t.key === "here")
                wx.fetchHere()
            else
                wx.fetchKey(t.key, t.lat, t.lon)
        }
    }

    readonly property var j: tabData && tabData.forecast ? tabData.forecast : null
    readonly property var air: tabData && tabData.air ? tabData.air : null
    readonly property var cur: j ? j.current : null
    readonly property var daily: j && j.daily ? j.daily : null
    readonly property string todayStr: new Date().toISOString().slice(0, 10)
    readonly property var hours: Model.remainingHours(j, 12)
    readonly property string heroIcon: cur
        ? Model.glyph(cur.weather_code, cur.is_day === 0 || cur.is_day === false)
        : "🌡️"

    // ---- geocode search (the [+] tab) ---------------------------------------
    property bool searching: false
    property var searchResults: []

    function runSearch(q) {
        q = String(q || "").trim()
        if (q.length < 2)
            return
        panelExec.connectSource("curl -fsS --max-time 8 "
            + JSON.stringify(Model.buildGeocodeUrl(q))
            + " | jq -c '[.results[]? | {name, admin1, country_code, latitude, longitude}]'")
    }

    function addPinned(place) {
        var list = wx.pinned.slice()
        var name = place.name + (place.admin1 ? " · " + place.admin1 : "")
        list.push({ name: name, lat: place.latitude, lon: place.longitude })
        wx.setPinned(list)
        searching = false
        searchResults = []
        var key = Model.slugify(place.name)
        switchTab(key)
        wx.fetchKey(key, place.latitude, place.longitude)
    }

    function removePinned(key) {
        wx.setPinned(wx.pinned.filter(function(p) { return p.key !== key }))
        if (activeKey === key)
            switchTab("here")
    }

    // ---- inline radar (RainViewer frame + Esri dark basemap tiles) ---------
    // Active-tab coordinates: pinned tab lat/lon, else the configured location.
    readonly property var radarLatLon: {
        var t = activeTab
        if (t && t.lat !== undefined && isFinite(Number(t.lat)))
            return [Number(t.lat), Number(t.lon)]
        if (wx.hasCoords)
            return [wx.cfgLat, wx.cfgLon]
        return null
    }
    // 2×2 tile window at zoom 7 (~500 km square) centered on the point.
    readonly property var radarWin: radarLatLon
        ? Model.radarTileWindow(radarLatLon[0], radarLatLon[1], 7, 2, 2)
        : null

    property string radarHost: "https://tilecache.rainviewer.com"
    property string radarFrame: ""
    property real radarFrameTime: 0
    property real cacheBust: 0

    function fetchRadar() {
        panelExec.connectSource(
            "curl -fsS --max-time 8 https://api.rainviewer.com/public/weather-maps.json"
            + " | jq -c '{host: .host, path: (.radar.past[-1].path // \"\"), "
            + "time: (.radar.past[-1].time // 0)}'")
    }

    function openRadarWeb() {
        var ll = radarLatLon
        if (ll)
            Qt.openUrlExternally(Model.radarUrl(ll[0], ll[1]))
    }

    function parseJsonSafe(txt) {
        try {
            return txt ? JSON.parse(txt) : null
        } catch (e) {
            return null
        }
    }

    // ---- dataengine: one fire-once source, dispatch by command -------------
    DataSource {
        id: panelExec
        engine: "executable"
        interval: 0
        onNewData: (sourceName, data) => {
            var cmd = String(sourceName)
            // One strict JSON line per tick (jq -c upstream of every payload):
            // last stdout line IS the whole document — same convention as
            // main.qml's handler.
            var out = (data["stdout"] || "").trim().split("\n").pop() || ""
            if (cmd.indexOf("weather-maps.json") >= 0) {
                var r = panel.parseJsonSafe(out)
                if (r && r.path) {
                    panel.radarHost = r.host || panel.radarHost
                    panel.radarFrame = r.path
                    panel.radarFrameTime = Number(r.time) || 0
                    panel.cacheBust = panel.radarFrameTime
                }
            } else if (cmd.indexOf("geocoding-api") >= 0) {
                var s = panel.parseJsonSafe(out)
                panel.searchResults = (s && s.length !== undefined) ? s : []
            } else if (cmd.indexOf(".json") >= 0) {
                // cat of an active-tab state file; apply only if that tab is
                // still active (fast tab switches queue stale reads)
                if (cmd.indexOf("/" + panel.readKey + ".json") >= 0) {
                    var obj = panel.parseJsonSafe(out)
                    panel.tabData = obj && obj.forecast ? obj : null
                }
            }
            panelExec.disconnectSource(sourceName)
        }
    }

    // One Timer, two periods: poll the active tab's state file every 2 s while
    // open (the fetch pipeline writes it atomically; stdout return updates the
    // bar chip) and refetch the RainViewer frame index every 5 min (frames
    // update ~10 min; the timestamp param busts the tile cache).
    Timer {
        id: pollTimer
        interval: 2000
        running: panel.visible && !panel.needsSetup
        repeat: true
        triggeredOnStart: true
        property real lastRadarMs: 0
        onTriggered: {
            if (!panel.searching) {
                panel.readTab()
                panel.maybeFetchActive()
            }
            var now = Date.now()
            if (now - lastRadarMs >= 300000) {
                lastRadarMs = now
                panel.fetchRadar()
            }
        }
    }

    Component.onCompleted: readTab()

    // ---- geometry: popup self-sizes to the visible column -------------------
    // Fonts multiply by scaleF, so implicitHeights grow with it — but panel
    // applet popups are hard-capped by Plasma (roughly availableScreenHeight
    // minus panel + margins). Cap our request at 86% of the screen so the
    // popup never gets clipped when text is scaled up: the content column
    // inside is a Flickable, so anything taller scrolls instead of clipping.
    readonly property real maxPopupH: {
        // Screen attached property: desktopAvailableHeight already excludes
        // the panel. Take 94% of it so the popup fills the screen height and
        // nothing needs to scroll at normal scales.
        var avail = Screen.desktopAvailableHeight
        if (!(avail > 0))
            avail = Kirigami.Units.gridUnit * 30
        return Math.min(avail * 0.94, Kirigami.Units.gridUnit * 40)
    }
    // Explicit width — Plasma 6.7's Dialog sizing ignores Layout hints here and
    // falls back to widest intrinsic child (~tab chips = cramped 410px). Pin it.
    width: Kirigami.Units.gridUnit * 46 * Math.min(1.6, panel.scaleF)
    Layout.preferredWidth: Kirigami.Units.gridUnit * 46 * Math.min(1.6, panel.scaleF)
    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
    // contentCol height + Flickable's own +largeSpacing*2 contentHeight pad
    // + the Flickable's largeSpacing*3 vertical margins (top 1 + bottom 2).
    // Anything less and the viewport is shorter than contentHeight by that
    // padding — a perpetual ~2-spacing nudge-scroll at every scale factor.
    Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 10,
        Math.min(maxPopupH,
        (needsSetup ? setupCol.implicitHeight
         : searching ? searchCol.implicitHeight
         : contentCol.implicitHeight)
        + Kirigami.Units.largeSpacing * 5))
    Layout.minimumHeight: Kirigami.Units.gridUnit * 8

    // =========================================================================
    // First-run hint (no location configured, nothing pinned)
    // =========================================================================
    Column {
        id: setupCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.largeSpacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.largeSpacing
        visible: panel.needsSetup

        Text {
            width: parent.width
            text: "🌡️ Set your location to start"
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 1.0 * panel.scaleF
            font.bold: true
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "WeatherX is keyless (Open-Meteo forecast + RainViewer radar). " +
                  "Open the widget settings and enter a latitude, longitude pair " +
                  "(example: 40.7128, -74.0060) plus a place name — or just close " +
                  "this popup and pin cities with the ＋ button."
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
        }
        ChipButton {
            label: "⚙ Configure…"
            trigger: function() { panel.wx.configure() }
        }
    }

    // =========================================================================
    // Search view ([+] tab)
    // =========================================================================
    Column {
        id: searchCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.largeSpacing * 2
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: panel.searching && !panel.needsSetup

        Row {
            spacing: Kirigami.Units.smallSpacing
            width: parent.width

            SearchField {
                id: searchField
                panel: panel
                width: parent.width - closeSearch.implicitWidth - Kirigami.Units.smallSpacing
                onSubmitted: panel.runSearch(searchField.searchText)
            }
            ChipButton {
                id: closeSearch
                label: "✕ close"
                round: false
                trigger: function() {
                    panel.searching = false
                    panel.searchResults = []
                }
            }
        }

        Repeater {
            model: panel.searchResults

            ResultRow {
                ctx: panel
                place: modelData
                onPicked: panel.addPinned(modelData)
            }
        }
    }

    // =========================================================================
    // Main panel content
    // =========================================================================
    Flickable {
        id: contentFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Kirigami.Units.largeSpacing * 2
        anchors.topMargin: Kirigami.Units.largeSpacing
        clip: true
        contentWidth: width
        contentHeight: contentCol.implicitHeight + Kirigami.Units.largeSpacing * 2
        boundsBehavior: Flickable.StopAtBounds
        visible: !panel.searching && !panel.needsSetup

        Column {
            id: contentCol
            width: contentFlick.width
            spacing: Kirigami.Units.largeSpacing

        // ---- tab row -------------------------------------------------------
        Flow {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: panel.tabs

                TabChip {
                    ctx: panel
                    tab: modelData
                    isActive: panel.activeKey === modelData.key
                    onChosen: {
                        if (modelData.pinned && panel.activeKey === modelData.key)
                            panel.removePinned(modelData.key)
                        else
                            panel.switchTab(modelData.key)
                    }
                }
            }
            ChipButton {
                label: "＋"
                trigger: function() { panel.searching = true }
            }
        }

        // ---- header: place · updated · radar · refresh · config ------------
        Item {
            width: parent.width
            implicitHeight: Math.max(headerLeft.implicitHeight, headerRight.implicitHeight)

            Row {
                id: headerLeft
                anchors.left: parent.left
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: panel.activeTab ? panel.activeTab.name : ""
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7 * panel.scaleF
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Weather unavailable — check network"
                    color: Kirigami.Theme.disabledTextColor
                    visible: panel.cur === null
                    font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                id: headerRight
                anchors.right: parent.right
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: panel.tabData && panel.tabData.fetchedAt
                        ? "updated " + Model.relativeAge(panel.tabData.fetchedAt) : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
                    anchors.verticalCenter: parent.verticalCenter
                }
                ChipButton {
                    label: "Radar ↗"
                    round: false
                    trigger: function() { panel.openRadarWeb() }
                    anchors.verticalCenter: parent.verticalCenter
                }
                ChipButton {
                    label: "⟳"
                    round: false
                    trigger: function() {
                        var t = panel.activeTab
                        if (t) {
                            if (t.key === "here")
                                panel.wx.fetchHere()
                            else
                                panel.wx.fetchKey(t.key, t.lat, t.lon)
                        }
                        panel.fetchRadar()
                    }
                    anchors.verticalCenter: parent.verticalCenter
                }
                ChipButton {
                    label: "⚙"
                    round: false
                    trigger: function() { panel.wx.configure() }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ---- hero ------------------------------------------------------------
        Row {
            spacing: Kirigami.Units.largeSpacing * 2

            Text {
                text: panel.heroIcon
                font.pixelSize: Kirigami.Units.gridUnit * 2.3 * panel.scaleF
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: panel.cur ? Model.temp(panel.cur.temperature_2m) : "--°"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 2.1 * panel.scaleF
                    font.bold: true
                }
                Text {
                    text: panel.cur ? Model.condText(panel.cur.weather_code) : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7 * panel.scaleF
                }
            }
            Column {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: panel.cur ? "Feels " + Model.temp(panel.cur.apparent_temperature) : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.62 * panel.scaleF
                }
                Text {
                    text: panel.daily && panel.daily.temperature_2m_max
                        ? "H " + Model.temp(panel.daily.temperature_2m_max[0])
                          + "  L " + Model.temp(panel.daily.temperature_2m_min[0])
                        : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.62 * panel.scaleF
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                           Kirigami.Theme.disabledTextColor.g,
                           Kirigami.Theme.disabledTextColor.b, 0.4)
        }

        // ---- body: radar (40%, widescreen crop) | details + 7-day side-by-side
        Row {
            id: bodyRow
            width: parent.width
            spacing: Kirigami.Units.largeSpacing * 2

            Column {
                id: radarCol
                width: Math.round(parent.width * 0.40)
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: "Radar"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                }

                Item {
                    id: radarMap
                    width: radarCol.width
                    height: Math.round(width * 0.60)   // widescreen crop — square radar ate the height budget
                    visible: panel.radarWin !== null
                    clip: true

                    readonly property real mx: panel.radarWin
                        ? (width / panel.radarWin.cols) * panel.radarWin.px : 0
                    readonly property real my: panel.radarWin
                        ? (height / panel.radarWin.rows) * panel.radarWin.py : 0

                    Repeater {
                        model: panel.radarWin ? panel.radarWin.cols * panel.radarWin.rows : 0

                        Item {
                            id: cellItem
                            required property int index
                            readonly property int col: cellItem.index % 2
                            readonly property int rowIdx: Math.floor(cellItem.index / 2)
                            x: col * radarMap.width / 2
                            y: rowIdx * radarMap.height / 2
                            width: radarMap.width / 2 + (col === 0 ? 1 : 0)
                            height: radarMap.height / 2 + (rowIdx === 0 ? 1 : 0)

                            Image {
                                anchors.fill: parent
                                source: panel.radarWin
                                    ? Model.radarBaseTileUrl(panel.radarWin.z,
                                        panel.radarWin.x0 + col, panel.radarWin.y0 + rowIdx)
                                    : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Image {
                                anchors.fill: parent
                                visible: panel.radarFrame !== ""
                                source: panel.radarFrame !== "" && panel.radarWin
                                    ? Model.radarFrameTileUrl(panel.radarHost, panel.radarFrame,
                                        panel.radarWin.z, panel.radarWin.x0 + col,
                                        panel.radarWin.y0 + rowIdx) + "?t=" + panel.cacheBust
                                    : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                            Image {
                                anchors.fill: parent
                                source: panel.radarWin
                                    ? Model.radarLabelTileUrl(panel.radarWin.z,
                                        panel.radarWin.x0 + col, panel.radarWin.y0 + rowIdx)
                                    : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                    }

                    Rectangle {
                        x: radarMap.mx - 6
                        y: radarMap.my - 6
                        width: 12
                        height: 12
                        radius: 6
                        color: "transparent"
                        border.width: 2
                        border.color: Kirigami.Theme.textColor
                    }
                    Rectangle {
                        x: radarMap.mx - 2
                        y: radarMap.my - 2
                        width: 4
                        height: 4
                        radius: 2
                        color: Kirigami.Theme.textColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.openRadarWeb()
                    }
                }

                Text {
                    visible: panel.radarWin === null
                    text: "no location for radar"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
                }

                Text {
                    text: panel.radarFrame
                        ? (panel.radarFrameTime
                            ? Model.relativeAge(
                                new Date(panel.radarFrameTime * 1000).toISOString()) + " · "
                            : "")
                          + "© Esri · RainViewer"
                        : "radar loading…"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.46 * panel.scaleF
                }
            }


            Row {
                id: dataCols
                width: parent.width - radarCol.width - parent.spacing
                spacing: Kirigami.Units.largeSpacing * 2

                Column {
                    id: detCol
                    width: Math.round((parent.width - dataCols.spacing) * 0.44)
                    spacing: Kirigami.Units.smallSpacing

Text {
    text: "Details"
    color: Kirigami.Theme.disabledTextColor
    font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
    font.bold: true
    font.capitalization: Font.AllUppercase
}


Grid {
    id: detailGrid
    width: parent.width
    columns: 3
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: Kirigami.Units.smallSpacing * 2

    Repeater {
        model: panel.detailCells

        Column {
            id: detailCell
            required property var modelData
            spacing: 1
            width: (detailGrid.width - detailGrid.columnSpacing * 2) / 3

            Text {
                width: parent.width
                text: detailCell.modelData && detailCell.modelData.label
                      ? detailCell.modelData.label : ""
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.52 * panel.scaleF
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: detailCell.modelData && detailCell.modelData.value
                      ? detailCell.modelData.value : ""
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.65 * panel.scaleF
                font.bold: true
                elide: Text.ElideRight
            }
            Rectangle {
                visible: detailCell.modelData
                         && detailCell.modelData.level !== undefined
                         && detailCell.modelData.level >= 0
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                              Kirigami.Theme.disabledTextColor.g,
                              Kirigami.Theme.disabledTextColor.b, 0.25)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1,
                        detailCell.modelData ? Number(detailCell.modelData.level) : 0))
                    radius: 1.5
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }
}

                }
            Column {
                id: dailyCol
                width: parent.width - detCol.width - dataCols.spacing
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: "7-Day Forecast"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                }

                Repeater {
                    model: panel.daily && panel.daily.time ? panel.daily.time : []

                    Row {
                        id: dayRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing

                        Text {
                            width: Kirigami.Units.gridUnit * 2.8
                            text: dayRow.modelData === panel.todayStr
                                  ? "Today" : Model.shortDay(dayRow.modelData)
                            color: Kirigami.Theme.textColor
                            font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
                            font.bold: dayRow.modelData === panel.todayStr
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: Kirigami.Units.gridUnit * 1.3
                            horizontalAlignment: Text.AlignHCenter
                            text: panel.daily && panel.daily.weather_code
                                  ? Model.glyph(panel.daily.weather_code[dayRow.index], false) : ""
                            font.pixelSize: Kirigami.Units.gridUnit * 0.72 * panel.scaleF
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: Kirigami.Units.gridUnit * 1.4
                            horizontalAlignment: Text.AlignRight
                            text: panel.daily && panel.daily.temperature_2m_max
                                  ? Model.temp(panel.daily.temperature_2m_max[dayRow.index]) : ""
                            color: Kirigami.Theme.textColor
                            font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: Kirigami.Units.gridUnit * 1.4
                            horizontalAlignment: Text.AlignRight
                            text: panel.daily && panel.daily.temperature_2m_min
                                  ? Model.temp(panel.daily.temperature_2m_min[dayRow.index]) : ""
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: parent.width - Kirigami.Units.gridUnit * 7.5
                            text: panel.daily && panel.daily.weather_code
                                  ? Model.condText(panel.daily.weather_code[dayRow.index]) : ""
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Units.gridUnit * 0.54 * panel.scaleF
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }


            }
        }  // bodyRow

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                           Kirigami.Theme.disabledTextColor.g,
                           Kirigami.Theme.disabledTextColor.b, 0.4)
        }

        // ---- remaining hours strip --------------------------------------------
        Text {
            text: "Next hours"
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.55 * panel.scaleF
            font.bold: true
            font.capitalization: Font.AllUppercase
        }

        Row {
            id: hoursRow
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: panel.hours

                Column {
                    id: hourCell
                    required property var modelData
                    spacing: 1
                    // flex: divide the row width evenly across the hour cells
                    width: (hoursRow.width
                            - (Math.max(1, panel.hours.length) - 1) * hoursRow.spacing)
                           / Math.max(1, panel.hours.length)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hourCell.modelData && hourCell.modelData.isNow
                              ? "NOW"
                              : Model.hourLabel(hourCell.modelData ? hourCell.modelData.time : "")
                        color: hourCell.modelData && hourCell.modelData.isNow
                               ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.5 * panel.scaleF
                        font.bold: hourCell.modelData && hourCell.modelData.isNow
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hourCell.modelData ? Model.glyph(hourCell.modelData.code, false) : ""
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75 * panel.scaleF
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hourCell.modelData ? Model.temp(hourCell.modelData.temp) : ""
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.57 * panel.scaleF
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hourCell.modelData && Number(hourCell.modelData.pop) >= 20
                              ? "💧" + hourCell.modelData.pop + "%" : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.47 * panel.scaleF
                    }
                }
            }
        }


        // ---- sun + credit -------------------------------------------------------
        Row {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing * 2

            Text {
                text: panel.daily && panel.daily.sunrise
                    ? "🌅 Sunrise " + String(panel.daily.sunrise[0]).slice(11, 16) : "🌅 --"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
            }
            Text {
                text: panel.daily && panel.daily.sunset
                    ? "🌇 Sunset " + String(panel.daily.sunset[0]).slice(11, 16) : "🌇 --"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
            }
            Text {
                text: panel.daily && panel.daily.sunrise
                    ? "☀ " + Model.daylightLength(panel.daily.sunrise[0], panel.daily.sunset[0]) : ""
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.6 * panel.scaleF
            }
        }

            Text {
                text: "Open-Meteo · bar follows this device · click a pinned tab twice to remove it"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.48 * panel.scaleF
            }
        }
    }

    // Details grid data — level bars where a 0..1 ratio exists (as upstream).
    readonly property var detailCells: {
        var c = panel.cur
        var cells = []
        function add(label, value, level) { cells.push({ label: label, value: value, level: level }) }
        if (!c)
            return cells
        add("Wind", Model.windDir(c.wind_direction_10m) + " " + Math.round(Number(c.wind_speed_10m)) + " mph")
        add("Gusts", Number(c.wind_gusts_10m) > 0 ? Math.round(Number(c.wind_gusts_10m)) + " mph" : "—")
        add("Humidity", Math.round(Number(c.relative_humidity_2m)) + "%", Number(c.relative_humidity_2m) / 100)
        add("Pressure", Math.round(Number(c.surface_pressure)) + " hPa")
        add("UV", Math.round(Number(c.uv_index) * 10) / 10 + " " + Model.uvCategory(c.uv_index), Math.min(1, Number(c.uv_index) / 11))
        add("Dew pt", Model.temp(c.dew_point_2m))
        if (panel.air && panel.air.us_aqi !== undefined)
            add("AQI", Math.round(Number(panel.air.us_aqi)) + " " + Model.aqiCategory(panel.air.us_aqi), Math.min(1, Number(panel.air.us_aqi) / 300))
        if (panel.hours.length > 0 && panel.hours[0].pop !== undefined)
            add("Rain now", panel.hours[0].pop + "%", Number(panel.hours[0].pop) / 100)
        return cells
    }
}
