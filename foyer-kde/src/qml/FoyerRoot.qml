/*
 * FoyerRoot.qml — FOYER for KDE, native QML build of converged v4.
 * Atrium body · Threshold grammar · omarchy-foyer DNA.
 * Host-agnostic Item: the daemon hosts this in a LayerShellQt window;
 * the harness hosts it in a plasmawindowed shell for verification.
 * Tokens resolve from Kirigami.Theme (the live color scheme) at runtime.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "FoyerData.js" as Data

Item {
    id: root
    implicitWidth: 920 * u
    implicitHeight: 640 * u
    width: implicitWidth
    height: implicitHeight

    // ---- adaptive scale (host sets; ultrawide: u=1.45, t<=1.18) ----------
    // u = STRUCTURE (header, field, rows, tiles, rail, margins): the
    // interface grows fully — bigger targets, more visible rows.
    // t = TYPE, clamped, so the hierarchy SPREADS at scale instead of a
    // uniform zoom: field > row names > meta > labels. The field (primary
    // surface) gets its own larger factor (fxText).
    property real u: 1.0
    property real t: 1.0
    readonly property real headerH: Math.round(60 * u)
    readonly property real fieldH:  Math.round(44 * u)
    readonly property real rowH:    Math.round(38 * u)
    readonly property real tileS:   Math.round(26 * u)
    readonly property real dotS:    Math.max(8, Math.round(8 * u))
    readonly property real railW:   Math.round(300 * u)
    readonly property int  fxText:  Math.round(17 * Math.min(t * 1.1, 1.35))

    // ---- tokens (runtime-resolved from the active color scheme) ----------
    readonly property color cBg:     Kirigami.Theme.backgroundColor
    readonly property color cRaised: Kirigami.Theme.alternateBackgroundColor
    readonly property color cText:   Kirigami.Theme.textColor
    readonly property color cDim:    Kirigami.Theme.disabledTextColor
    readonly property color cAccent: Kirigami.Theme.highlightColor
    readonly property color cHover:  Kirigami.Theme.hoverColor
    readonly property color cNeg:    Kirigami.Theme.negativeTextColor
    readonly property color cPos:    Kirigami.Theme.positiveTextColor
    readonly property color cWarn:   Kirigami.Theme.neutralTextColor
    readonly property string mono:   "Noto Sans Mono"

    // ---- state ------------------------------------------------------------
    property string state: "boot"
    property int railIndex: 0
    property string fieldText: ""
    property bool fieldHasCaret: true

    // state presets (fork caret-flow; daemon drives these live)
    readonly property var presets: ({
        boot:     { field: "",            rail: 0 },
        games:    { field: "",            rail: 0 },
        typed:    { field: "bro",         rail: -1 },
        nomatch:  { field: "zzz",         rail: -1 },
        ai:       { field: "",            rail: 7 },
        stream:   { field: Data.aiAnswer.q, rail: 7 },
        ready:    { field: Data.aiAnswer.q, rail: 7 },
        system:   { field: "",            rail: 4 },
        fleet:    { field: "",            rail: 8 },
        ssh:      { field: "",            rail: 9 },
        snippets: { field: "",            rail: 10 },
        settings: { field: "",            rail: 3 },
        update:   { field: "",            rail: 5 },
        help:     { field: "",            rail: 11 },
        about:    { field: "",            rail: 6 },
        recents:  { field: "",            rail: 2 },
        favs:     { field: "",            rail: 1 }
    })

    readonly property var railModel: [
        { group: "Launcher" },
        { tag: "AP", label: "Apps",      value: String(Data.meta.totalApps), state: "boot",     slot: 1 },
        { tag: "FA", label: "Favorites", value: "★ 0",                        state: "favs",     slot: 2 },
        { tag: "RE", label: "Recents",   value: "0",                          state: "recents",  slot: 3 },
        { tag: "SE", label: "Settings",  value: String(Data.meta.kcmTotal),   state: "settings", slot: 4 },
        { tag: "SY", label: "System",    value: "5",                          state: "system",   slot: 5 },
        { tag: "UP", label: "Update",    value: "check",                      state: "update",   slot: 6 },
        { tag: "AB", label: "About",     value: "",                           state: "about",    slot: 7 },
        { group: "Fleet" },
        { tag: "AI", label: "AI",        value: Data.ai.model,                state: "ai",       slot: 8 },
        { tag: "FL", label: "Fleet",     value: upCount + "↑",                state: "fleet",    slot: 9 },
        { tag: "SS", label: "SSH",       value: String(Data.sshHosts.length),state: "ssh" },
        { tag: "SN", label: "Snippets",  value: "0",                          state: "snippets" },
        { tag: "HE", label: "Help",      value: "f1",                         state: "help" }
    ]
    readonly property int upCount: {
        var n = 0;
        for (var i = 0; i < Data.fleet.length; i++) if (Data.fleet[i].up) n++;
        return n;
    }

    function gotoState(s) {
        var p = presets[s];
        if (!p) return;
        state = s;
        fieldText = p.field;
        field.text = p.field;
        railIndex = p.rail;
        var lensItem = lensLoader.item;
        if (lensItem && lensItem.forceFocus) lensItem.forceFocus();
        else field.forceActiveFocus();
    }

    // harness diagnostic: rail ListView internals (never called by the daemon)
    function railProbe() {
        var ci = rail.contentItem;
        var kids = ci ? ci.children : [];
        var railAbs = rail.mapToItem(null, 0, 0);
        var d2 = kids.length > 2 ? kids[2] : null;
        var d2abs = d2 ? d2.mapToItem(null, 0, 0) : { x: -1, y: -1 };
        // find the label Text inside delegate [2] (row variant: Rectangle -> RowLayout -> Text)
        var lab = "";
        if (d2) {
            for (var j = 0; j < d2.children.length; j++) {
                var r = d2.children[j];
                for (var m = 0; m < r.children.length; m++) {
                    var rl = r.children[m];
                    if (rl.children) {
                        for (var t = 0; t < rl.children.length; t++) {
                            var c = rl.children[t];
                            if (c.text !== undefined && c.text.length > 0) {
                                lab += "'" + c.text + "' w=" + c.width.toFixed(0) +
                                       " vis=" + c.visible + " col=" + c.color + " @(" +
                                       c.mapToItem(null, 0, 0).x.toFixed(0) + "," +
                                       c.mapToItem(null, 0, 0).y.toFixed(0) + ") ";
                            }
                        }
                    }
                }
            }
        }
        return "count=" + rail.count + " railW=" + rail.width + " railH=" + rail.height +
               " rail@(" + railAbs.x.toFixed(0) + "," + railAbs.y.toFixed(0) + ")" +
               " d2@(" + d2abs.x.toFixed(0) + "," + d2abs.y.toFixed(0) + ") labels: " + lab;
    }

    onStateChanged: {
        streamTimer.stop();
        if (state === "stream") streamTimer.restart();
    }

    // Enter on the Ask row → stream → ready (the demo streaming machine)
    Timer { id: streamTimer; interval: 2600; onTriggered: root.gotoState("ready") }

    // ---- chrome ------------------------------------------------------------
    Rectangle {
        id: card
        anchors.fill: parent
        color: Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.96)
        border.color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ===== header =====
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.headerH
                Layout.leftMargin: Math.round(20 * root.u)
                Layout.rightMargin: Math.round(20 * root.u)
                spacing: Math.round(14 * root.u)

                Rectangle {
                    id: fieldBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldH
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: field.activeFocus ? root.cAccent : Qt.rgba(1, 1, 1, 0.14)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(14 * root.u)
                        anchors.rightMargin: Math.round(14 * root.u)
                        spacing: Math.round(12 * root.u)

                        Text {
                            text: "▸"
                            color: root.cDim
                            font.pixelSize: Math.round(14 * root.t)
                            font.family: root.mono
                        }
                        TextInput {
                            id: field
                            Layout.fillWidth: true
                            font.pixelSize: root.fxText
                            font.family: root.mono
                            color: root.cText
                            cursorVisible: root.fieldHasCaret
                            clip: true
                            onTextEdited: {
                                root.fieldText = text;
                                if (text.length > 0) {
                                    var hits = Data.search(text);
                                    root.state = hits.length > 0 ? "typed" : "nomatch";
                                    root.railIndex = -1;
                                    typedResults.model = hits;
                                } else if (root.state === "typed" || root.state === "nomatch") {
                                    root.gotoState("boot");
                                }
                            }
                            Keys.onDownPressed: {
                                var it = lensLoader.item;
                                if (it && it.forceFocus) it.forceFocus();
                            }
                            Keys.onEscapePressed: function(event) {
                                if (text.length) {
                                    field.remove(0, text.length);
                                } else if (root.state !== "boot") {
                                    root.gotoState("boot");
                                } else {
                                    // At root with empty field: do nothing HERE and
                                    // let the event propagate — the daemon host's
                                    // surface handler closes the window on it.
                                    event.accepted = false;
                                }
                            }
                            Keys.onBackPressed: {
                                if (!text.length && root.state !== "boot") root.gotoState("boot");
                            }
                            Component.onCompleted: forceActiveFocus()
                        }
                        Text {
                            visible: field.length === 0 && root.fieldText.length === 0
                            text: "search " + Data.meta.totalApps + " apps · " +
                                  Data.meta.kcmTotal + " modules · " + Data.sshHosts.length +
                                  " hosts — or just ask"
                            color: root.cDim
                            font.pixelSize: Math.round(15 * root.t)
                            font.family: root.mono
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    text: "ctrl s   ctrl ,   f1"
                    color: root.cDim
                    font.pixelSize: Math.round(10 * root.t)
                    font.family: root.mono
                    opacity: 0.75
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

            // ===== body: rail + lens =====
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ---- rail ----
                Rectangle {
                    Layout.preferredWidth: root.railW
                    Layout.fillHeight: true
                    color: "transparent"

                    ListView {
                        id: rail
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        model: root.railModel
                        spacing: 0
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: rail.width - 20
                            height: modelData.group !== undefined ? 30 : 38

                            // group header
                            Text {
                                visible: modelData.group !== undefined
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.baseline: parent.bottom
                                anchors.baselineOffset: -8
                                text: modelData.group !== undefined ? modelData.group.toUpperCase() : ""
                                color: root.cDim
                                font.pixelSize: Math.round(11 * root.t)
                                font.family: root.mono
                            }

                            Rectangle {
                                visible: modelData.group === undefined
                                anchors.fill: parent
                                radius: 8
                                color: root.railIndex === index ? root.cRaised : "transparent"
                                Rectangle {
                                    visible: root.railIndex === index
                                    width: 2; height: parent.height - 12
                                    anchors.left: parent.left; anchors.leftMargin: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.cAccent
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        visible: modelData.slot !== undefined
                                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                        radius: 5
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.group === undefined ? modelData.tag : ""
                                            color: root.cDim
                                            font.pixelSize: Math.round(9 * root.t)
                                            font.family: root.mono
                                        }
                                    }
                                    Text {
                                        text: modelData.group === undefined ? modelData.label : ""
                                        color: root.railIndex === index ? root.cText : root.cDim
                                        font.pixelSize: Math.round(15 * root.t)
                                        font.bold: root.railIndex === index
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.slot !== undefined && modelData.slot < 10
                                        text: modelData.slot !== undefined ? modelData.slot : ""
                                        color: root.cDim
                                        opacity: 0.45
                                        font.pixelSize: Math.round(10 * root.t)
                                        font.family: root.mono
                                    }
                                    Text {
                                        text: modelData.value !== undefined ? modelData.value : ""
                                        color: modelData.label === "Fleet" ? root.cPos : root.cDim
                                        font.pixelSize: Math.round(12 * root.t)
                                        font.family: root.mono
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { root.railIndex = index; root.gotoState(modelData.state); }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(1, 1, 1, 0.07) }

                // ---- lens ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // scope trail
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            spacing: 9

                            Text {
                                font.pixelSize: Math.round(12 * root.t)
                                font.family: root.mono
                                color: root.cDim
                                text: ({
                                    boot: "FOYER", games: "APPS › GAMES",
                                    typed: "RESULTS", nomatch: "RESULTS", ai: "AI",
                                    stream: "AI", ready: "AI", system: "SYSTEM",
                                    fleet: "FLEET", ssh: "SSH", snippets: "SNIPPETS",
                                    settings: "FOYER SETTINGS", update: "UPDATE",
                                    help: "HELP · F1", about: "ABOUT",
                                    recents: "RECENTS", favs: "FAVORITES"
                                })[root.state]
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                visible: root.state === "fleet"
                                spacing: 8
                                Text { text: root.upCount + " UP";  color: root.cPos; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                                Text { text: "· 1 DOWN · PINGED " + Data.meta.probedAt; color: root.cNeg; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                            }
                        }

                        // lens content
                        Loader {
                            id: lensLoader
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            sourceComponent: {
                                switch (root.state) {
                                case "boot":     return bootComp;
                                case "games":    return gamesComp;
                                case "typed":    return typedComp;
                                case "nomatch":  return nomatchComp;
                                case "ai":       return aiComp;
                                case "stream":   return streamComp;
                                case "ready":    return readyComp;
                                case "system":   return systemComp;
                                case "fleet":    return fleetComp;
                                case "ssh":      return sshComp;
                                case "settings": return settingsComp;
                                case "update":   return updateComp;
                                case "help":     return helpComp;
                                case "about":    return aboutComp;
                                case "recents":  return emptyRecentsComp;
                                case "favs":     return emptyFavsComp;
                                case "snippets": return emptySnipsComp;
                                }
                                return bootComp;
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

            // ===== footer =====
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.leftMargin: Math.round(20 * root.u)
                Layout.rightMargin: Math.round(20 * root.u)
                spacing: Math.round(14 * root.u)

                Text {
                    text: "⏎ open    → drill    ⌫ back    ctrl 1–9 jump    alt⏎ secondary    ctrl s settings"
                    color: root.cDim
                    font.pixelSize: Math.round(10 * root.t)
                    font.family: root.mono
                }
                Item { Layout.fillWidth: true }
                Text { text: "SUPER+SPACE"; color: root.cDim; font.pixelSize: Math.round(10 * root.t); font.family: root.mono }
                Text { text: "FOYER · KDE v4"; color: root.cHover; font.pixelSize: Math.round(10 * root.t); font.family: root.mono }
            }
        }
    }

    // ---- shared lens bits --------------------------------------------------
    component SectionHead: RowLayout {
        id: sh
        property string title: ""
        property string note: ""
        spacing: 10
        Layout.leftMargin: 24
        Layout.rightMargin: 24
        Layout.topMargin: 12
        Text {
            text: sh.title
            color: root.cDim
            font.pixelSize: Math.round(12 * root.t)
            font.family: root.mono
        }
        Text {
            visible: sh.note.length > 0
            text: sh.note
            color: root.cDim
            opacity: 0.75
            font.pixelSize: Math.round(11 * root.t)
        }
    }

    component Tile: Rectangle {
        property string tag: ""
        width: root.tileS; height: root.tileS; radius: 6
        color: root.cRaised
        border.color: Qt.rgba(1, 1, 1, 0.12)
        Text {
            anchors.centerIn: parent
            text: parent.tag
            color: root.cText
            font.pixelSize: Math.round(11 * root.t)
            font.bold: true
            font.family: root.mono
        }
    }

    component ListRow: Rectangle {
        id: lr
        property string name: ""
        property string detail: ""
        property string value: ""
        property bool hasTile: true
        property string tag: ""
        property bool warn: false
        property bool dimmed: false
        property bool focused: false
        property bool monoName: false
        property string dot: ""   // "", "ok", "down"
        height: root.rowH
        radius: 8
        color: "transparent"
        border.width: focused ? 2 : 0
        border.color: root.cAccent
        opacity: dimmed ? 0.5 : 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Math.round(12 * root.u)
            anchors.rightMargin: Math.round(12 * root.u)
            spacing: Math.round(12 * root.u)
            Rectangle {
                visible: lr.dot.length > 0
                Layout.preferredWidth: root.dotS; Layout.preferredHeight: root.dotS
                radius: root.dotS / 2
                color: lr.dot === "ok" ? root.cPos : root.cNeg
            }
            Loader {
                active: lr.hasTile
                sourceComponent: Tile { tag: lr.tag }
            }
            Text {
                text: lr.name
                color: root.cText
                font.pixelSize: lr.monoName ? 14 : 15
                font.family: lr.monoName ? root.mono : Qt.application.font.family
                Layout.preferredWidth: parent.width * 0.42
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: lr.detail
                color: lr.warn ? root.cWarn : root.cDim
                font.pixelSize: Math.round(13 * root.t)
                elide: Text.ElideRight
            }
            Text {
                visible: lr.value.length > 0
                text: lr.value
                color: root.cDim
                font.pixelSize: Math.round(12 * root.t)
                font.family: root.mono
            }
        }
    }

    // ---- lenses --------------------------------------------------------------
    Component {
        id: bootComp
        Flickable {
            clip: true
            contentHeight: bootCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: bootCol
                width: parent.width
                spacing: 0
                SectionHead {
                    title: "ALL CATEGORIES · " + Data.categories.length
                    note: Data.meta.totalApps + " apps · alphabetical within category"
                }
                Repeater {
                    model: Data.categories
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: modelData.label.length > 8 ? modelData.label.substring(0, 2).toUpperCase()
                                                        : modelData.label.substring(0, 1).toUpperCase()
                        name: modelData.label
                        detail: modelData.sample
                        value: String(modelData.count)
                        focused: index === 1
                        MouseArea { anchors.fill: parent; onClicked: root.gotoState("games") }
                    }
                }
            }
        }
    }

    Component {
        id: gamesComp
        Flickable {
            clip: true
            contentHeight: gamesCol.height + 28
            ColumnLayout {
                id: gamesCol
                width: parent.width
                spacing: 0
                SectionHead { title: "GAMES"; note: Data.games.length + " apps · ⏎ launches · alt⏎ pins" }
                GridLayout {
                    columns: 2
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.topMargin: 4
                    columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: Data.games
                        delegate: Rectangle {
                            id: gcell
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 8
                            border.width: index === 0 ? 2 : 0
                            border.color: root.cAccent
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12
                                Rectangle {
                                    width: 30; height: 30; radius: 7
                                    color: root.cRaised
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    Text {
                                        anchors.centerIn: parent
                                        text: gcell.modelData ? gcell.modelData.name.substring(0, 2).toUpperCase() : ""
                                        color: root.cText
                                        font.pixelSize: Math.round(12 * root.t)
                                        font.bold: true
                                        font.family: root.mono
                                    }
                                }
                                ColumnLayout {
                                    spacing: 1
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData ? modelData.name : ""
                                        color: root.cText
                                        font.pixelSize: Math.round(14 * root.t)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData ? modelData.detail : ""
                                        color: root.cDim
                                        font.pixelSize: Math.round(12 * root.t)
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: typedComp
        ColumnLayout {
            spacing: 0
            function forceFocus() {}
            SectionHead { title: "APPLICATIONS · " + typedResults.count }
            Repeater {
                id: typedResults
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                model: []
                delegate: ListRow {
                    id: tr
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    tag: "·"
                    hasTile: modelData.kind === "app"
                    name: modelData.name
                    detail: modelData.detail
                    value: "⏎"
                    focused: index === 0
                }
            }
            SectionHead { title: "HERMES" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "ai"; name: "Ask Hermes"
                detail: root.fieldText + "? — answer lands here"
                value: Data.ai.model
            }
            SectionHead { title: "WEB"; note: "fallback only" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "w"; name: "Search the web"
                detail: "opens in default browser"; value: "↗"
            }
        }
    }

    Component {
        id: nomatchComp
        ColumnLayout {
            spacing: 0
            function forceFocus() {}
            Item { Layout.preferredHeight: 18 }
            Text {
                Layout.leftMargin: 28
                text: "No matches for “" + root.fieldText + "”"
                color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true
            }
            Text {
                Layout.leftMargin: 28
                Layout.topMargin: 6
                text: "The query stays yours — esc clears, typing rewrites."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t)
            }
            SectionHead { title: "HERMES" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "ai"
                name: "Ask Hermes: " + root.fieldText
                detail: "enter asks anyway · answer copied on ⏎"
                value: Data.ai.model
                focused: true
                MouseArea { anchors.fill: parent; onClicked: root.gotoState("stream") }
            }
        }
    }

    Component {
        id: aiComp
        Flickable {
            clip: true
            contentHeight: aiCol.height + 28
            ColumnLayout {
                id: aiCol
                width: parent.width
                spacing: 0
                SectionHead { title: "ASK ANYTHING"; note: "the field above is the ask box" }
                ColumnLayout {
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    spacing: 10
                    Text { text: Data.ai.answerPrefix + "   ask a question — the answer streams here, ⏎ copies it"
                           color: root.cDim; font.pixelSize: Math.round(14 * root.t); font.family: root.mono }
                    Text { text: Data.ai.taskPrefix + "   hand a task to Hermes — it runs, you get notified"
                           color: root.cDim; font.pixelSize: Math.round(14 * root.t); font.family: root.mono }
                }
                SectionHead { title: "MODEL" }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "☉"; name: Data.ai.model
                    detail: "via " + Data.ai.via + " · 45s timeout · " + Data.ai.maxChars + " chars max"
                    value: "✓"
                    MouseArea { anchors.fill: parent; onClicked: root.gotoState("stream") }
                }
                SectionHead { title: "RECENT QUESTIONS"; note: "questions only — answers are never cached" }
                Repeater {
                    model: Data.ai.recentQuestions
                    delegate: ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false
                        name: ""
                        detail: modelData
                    }
                }
            }
        }
    }

    Component {
        id: streamComp
        Flickable {
            clip: true
            contentHeight: streamCol.height + 28
            ColumnLayout {
                id: streamCol
                width: parent.width
                spacing: 0
                SectionHead { title: "" }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.topMargin: 4
                    Layout.preferredHeight: streamInner.height + 36
                    radius: 10
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    ColumnLayout {
                        id: streamInner
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12
                        RowLayout {
                            spacing: 10
                            Text { text: "STREAMING"; color: root.cHover; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: "·"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: Data.ai.model; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Item { Layout.fillWidth: true }
                            Text { text: "4.2s"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Data.aiAnswer.streamingText + " ▌"
                            color: root.cText
                            font.pixelSize: Math.round(15 * root.t)
                            wrapMode: Text.Wrap
                            lineHeight: 1.25
                        }
                        RowLayout {
                            spacing: 8
                            opacity: 0.38
                            Rectangle {
                                width: 90; height: 30; radius: 7
                                border.color: Qt.rgba(1, 1, 1, 0.14); color: "transparent"
                                Text { anchors.centerIn: parent; text: "Copy"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                            }
                            Rectangle {
                                width: 140; height: 30; radius: 7
                                border.color: Qt.rgba(1, 1, 1, 0.14); color: "transparent"
                                Text { anchors.centerIn: parent; text: "Continue in chat"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "COPY ARMED WHEN STREAM ENDS"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: readyComp
        Flickable {
            clip: true
            contentHeight: readyCol.height + 28
            ColumnLayout {
                id: readyCol
                width: parent.width
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.topMargin: 16
                    Layout.preferredHeight: readyInner.height + 36
                    radius: 10
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    ColumnLayout {
                        id: readyInner
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12
                        RowLayout {
                            spacing: 10
                            Text { text: "ANSWERED"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: "·"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: Data.ai.model; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Item { Layout.fillWidth: true }
                            Text { text: "7.8s"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Data.aiAnswer.body[0]
                            color: root.cText
                            font.pixelSize: Math.round(15 * root.t)
                            wrapMode: Text.Wrap
                            lineHeight: 1.25
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Data.aiAnswer.body[1]
                            color: root.cText
                            font.pixelSize: Math.round(15 * root.t)
                            wrapMode: Text.Wrap
                            lineHeight: 1.25
                        }
                        RowLayout {
                            spacing: 8
                            Rectangle {
                                width: 118; height: 30; radius: 7
                                border.color: root.cHover; color: "transparent"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Copy"; color: root.cHover; font.pixelSize: Math.round(13 * root.t) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "alt ⏎"; color: root.cHover; font.pixelSize: Math.round(10 * root.t); font.family: root.mono }
                                }
                            }
                            Rectangle {
                                width: 140; height: 30; radius: 7
                                border.color: Qt.rgba(1, 1, 1, 0.14); color: "transparent"
                                Text { anchors.centerIn: parent; text: "Continue in chat"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "MODEL  " + Data.ai.model; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                        }
                    }
                }
                SectionHead { title: "RECENT QUESTIONS" }
                Repeater {
                    model: Data.ai.recentQuestions.slice(0, 2)
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false; name: ""; detail: modelData
                        value: index === 0 ? "asked " + Data.meta.probedAt : ""
                    }
                }
            }
        }
    }

    Component {
        id: systemComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "POWER & SESSION"; note: "consequences are the confirmation" }
            Repeater {
                model: Data.systemRows
                delegate: ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: modelData.name.substring(0, 2).toUpperCase()
                    name: modelData.name
                    detail: modelData.detail
                    warn: modelData.warn
                    value: "⏎"
                    focused: index === 2
                }
            }
        }
    }

    Component {
        id: fleetComp
        Flickable {
            clip: true
            contentHeight: fleetCol.height + 28
            ColumnLayout {
                id: fleetCol
                width: parent.width
                spacing: 0
                SectionHead { title: "HOSTS · " + Data.fleet.length; note: "live probe · icmp 1s · refreshed on open" }
                Repeater {
                    model: Data.fleet
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false
                        monoName: true
                        dot: modelData.up ? "ok" : "down"
                        dimmed: !modelData.up
                        name: modelData.host
                        detail: (modelData.up ? "" : "down · ") + modelData.role
                        warn: !modelData.up
                        value: modelData.ip
                    }
                }
            }
        }
    }

    Component {
        id: sshComp
        Flickable {
            clip: true
            contentHeight: sshCol.height + 28
            ColumnLayout {
                id: sshCol
                width: parent.width
                spacing: 0
                SectionHead { title: "ALIASES · " + Data.sshHosts.length; note: "⏎ opens a terminal tab · from ~/.ssh/config" }
                Repeater {
                    model: Data.sshHosts
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: "›"
                        monoName: true
                        name: modelData.alias
                        detail: modelData.ip + (modelData.note ? " · " + modelData.note : "")
                        focused: index === 0
                    }
                }
            }
        }
    }

    Component {
        id: updateComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "SYSTEM IMAGE"; note: "bazzite · rpm-ostree" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "↺"; name: "Check for updates"
                detail: "guard runs async · row states itself when done"; value: "⏎"
                focused: true
            }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "⇧"; name: "Apply staged deployment"
                detail: "closes open apps · reboots into new image"; warn: true; value: "⏎"
            }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "i"; name: "Deployment history"
                detail: "rpm-ostree status · last 5"; value: "→"
            }
        }
    }

    Component {
        id: settingsComp
        Flickable {
            clip: true
            contentHeight: setCol.height + 28
            ColumnLayout {
                id: setCol
                width: parent.width
                spacing: 0
                SectionHead { title: "WINDOW" }
                Repeater {
                    model: [
                        { k: "Width", v: "420   680   [920]" },
                        { k: "Compact mode collapses the rail to a caption column", v: "at ≤ 560" },
                        { k: "Row density", v: "24   [28]   34" },
                        { k: "Opacity · Radius", v: "96% · 14" },
                        { k: "Location", v: "↧ top   ◈ [center]   ↥ bottom" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 28; Layout.rightMargin: 28
                        Layout.preferredHeight: 38
                        Text { text: modelData.k; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: modelData.v; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                    }
                }
                SectionHead { title: "SEARCH" }
                Repeater {
                    model: [
                        { k: "Fuzzy matching (≥ 3 chars)", v: "off" },
                        { k: "Category captions", v: "on" },
                        { k: "Menu on start", v: "on" },
                        { k: "Ctrl-number hints", v: "on" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 28; Layout.rightMargin: 28
                        Layout.preferredHeight: 38
                        Text { text: modelData.k; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: modelData.v; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                    }
                }
                SectionHead { title: "SOURCES" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    Layout.preferredHeight: 38
                    Text { text: "Applications · Hermes AI · Fleet · SSH · Snippets"; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: "on"; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    Layout.preferredHeight: 38
                    Text { text: "Web search"; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true }
                    Text { text: "fallback only · off"; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                }
                SectionHead { title: "AI" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    Layout.preferredHeight: 38
                    Text { text: "Endpoint · Model"; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true }
                    Text { text: "192.168.1.243:4000/v1 · " + Data.ai.model; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    Layout.preferredHeight: 38
                    Text { text: "Copy answers on ⏎"; color: root.cText; font.pixelSize: Math.round(14 * root.t); Layout.fillWidth: true }
                    Text { text: "on"; color: root.cDim; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
                }
            }
        }
    }

    Component {
        id: helpComp
        Flickable {
            clip: true
            contentHeight: helpCol.height + 28
            ColumnLayout {
                id: helpCol
                width: parent.width
                spacing: 0
                SectionHead { title: "KEYMAP"; note: "f1 anywhere · this page" }
                Repeater {
                    model: [
                        { k: "type",   d: "filter — the field keeps the caret; ⏎ runs the top hit" },
                        { k: "↓ ↑",    d: "walk results / rail — ↑ from first row returns to the field" },
                        { k: "→ ←",    d: "drill in · back out — ← from rail enters the lens" },
                        { k: "⌫",      d: "pop a level first, then clear the query" },
                        { k: "esc",    d: "clear query → back a level → close at root" },
                        { k: "ctrl 1–9", d: "jump to a branch — numbers are pinned to the rail" },
                        { k: "alt ⏎",  d: "secondary action — copy an answer, pin a row" },
                        { k: "ctrl p", d: "pin / unpin to Favorites" },
                        { k: "ctrl s · ctrl ,", d: "settings · sources" },
                        { k: "del",    d: "uninstall an app — always asks first" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 28; Layout.rightMargin: 28
                        Layout.preferredHeight: 34
                        spacing: 10
                        Text { text: modelData.k; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono; Layout.preferredWidth: 180 }
                        Text { text: modelData.d; color: root.cText; font.pixelSize: Math.round(13 * root.t); Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }
    }

    Component {
        id: aboutComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "FOYER FOR KDE" }
            Item { Layout.preferredHeight: 10 }
            Text {
                Layout.leftMargin: 28; Layout.rightMargin: 28
                Layout.fillWidth: true
                text: "A native Plasma reimagining of omarchy-foyer v0.4.2.\n" +
                      "QML UI · Kirigami theme tokens · layer-shell window in the daemon build.\n\n" +
                      "Tokens resolve from the live color scheme at runtime —\n" +
                      "every pixel derives from it."
                color: root.cText
                font.pixelSize: Math.round(14 * root.t)
                lineHeight: 1.45
                wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: emptyRecentsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "RECENTS" }
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "Nothing recent yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "KDE activity feeds this on first use — files, apps, documents.\nRecents show what and when, never content."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }

    Component {
        id: emptyFavsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "FAVORITES" }
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "No pins yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "ctrl p pins any row — app, host, snippet, question.\nFavorites mirror Kickoff favorites; prune there, this follows. Max 30."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }

    Component {
        id: emptySnipsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "SNIPPETS" }
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "No snippets yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "Type ; in the field to search snippets once they exist.\nSnippets live in ~/.config/foyer/snippets.jsonc — same merge rules\nas the menu tree: your extensions win."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }
}
