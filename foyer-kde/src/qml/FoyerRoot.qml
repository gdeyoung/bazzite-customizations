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
    // Pinned v4 palette — LITERAL. Kirigami ambient/attached resolution
    // proved environment-dependent on this host (standalone probe, systemd
    // session, and live session each resolved different colors for the same
    // role). Literal constants render identically everywhere. Change colors
    // HERE and only here. (UI law: fills stay dark; text on cRaised 10.9:1,
    // cDim on cRaised 5.6:1 — WCAG AA with margin.)
    readonly property color cBg:     "#232629"
    readonly property color cRaised: "#31363b"
    readonly property color cText:   "#fcfcfc"
    readonly property color cDim:    "#a1a9b1"
    readonly property color cAccent: "#1e92ff"
    readonly property color cHover:  "#3daee9"
    readonly property color cNeg:    "#da4453"
    readonly property color cPos:    "#27ae60"
    readonly property color cWarn:   "#f67400"
    readonly property string mono:   "Noto Sans Mono"

    // ---- state ------------------------------------------------------------
    property string state: "boot"
    // live launcher data (.desktop scan, pushed by the daemon's appsJson
    // property; null in the applet build → frozen FoyerData fallback)
    property string appsJson: ""
    property var liveCats: null
    // search results live on the ROOT: assigning to a Repeater model inside
    // a not-yet-loaded Component is a write to a null id — silently lost
    // (the exact "typed brave, nothing suggested" failure)
    property var typedModel: []
    // destructive system rows arm a two-row confirm strip (Cancel default).
    // Lock/Sleep stay immediate (reversible) — CC Loop-1 ship gate.
    property bool confirmArmed: false
    property string confirmAction: ""
    property string confirmLabel: ""
    // Loop-2 live lanes: AI + settings (daemon is the source of truth)
    property string aiQuestion: ""
    property string aiStream: ""
    property bool aiDone: true
    property string aiModelName: ""
    property string recentJson: "[]"
    property var recentModel: []
    property bool fuzzyOn: false
    property string cardAnchor: "center"
    onRecentJsonChanged: {
        try { recentModel = JSON.parse(recentJson); }
        catch (e) { recentModel = []; }
    }
    onAiDoneChanged: {
        // stream -> ready when the answer lands (matches the design flow)
        if (aiDone && state === "stream") gotoState("ready");
    }

    function disarmConfirm() {
        if (!confirmArmed) return;
        confirmArmed = false; confirmAction = "";
        var g = navFor("system");
        lensCount = g[0];
        if (lensIndex > lensCount - 1) lensIndex = lensCount - 1;
    }
    // live lanes pushed by the daemon (see foyer.py): ssh aliases from
    // ~/.ssh/config, recents from recently-used.xbel, kickoff favorites,
    // fleet probe results, rpm-ostree output for the UPDATE view
    property string sshJson: ""
    property string recentsJson: ""
    property string favsJson: ""
    property string fleetJson: ""
    property string updateOut: ""
    property var sshModel: []
    property var recentsModel: []
    property var favsModel: []
    property var fleetModel: []
    property string fleetStamp: ""
    onSshJsonChanged:      { try { sshModel = JSON.parse(sshJson) } catch (e) {} }
    onRecentsJsonChanged:  { try { recentsModel = JSON.parse(recentsJson) } catch (e) {} }
    onFavsJsonChanged:     { try { favsModel = JSON.parse(favsJson) } catch (e) {} }
    onFleetJsonChanged: {
        try {
            var f = JSON.parse(fleetJson);
            fleetModel = f.hosts; fleetStamp = f.stamp;
        } catch (e) {}
        if (state === "fleet") {
            var ng = navFor("fleet");
            lensCount = ng[0]; lensCols = ng[1];
            if (lensIndex > lensCount - 1) lensIndex = lensCount - 1;
        }
    }
    onAppsJsonChanged: {
        try { liveCats = JSON.parse(appsJson); }
        catch (e) { liveCats = null; }
    }
    // QA mirrors of the field's caret/query (real-key forensics)
    property int caret: field.cursorPosition
    property int queryLen: field.length
    property string activeCatId: ""
    property string activeCatLabel: ""
    property int railIndex: 0
    property string zone: "field"      // keyboard zone: field | rail | lens
    property int lensIndex: 0
    property int lensCount: 1
    property int lensCols: 1   // lens grid columns (games = 2)
    property int navPulse: -1
    Timer { id: navPulseT; interval: 450; onTriggered: root.navPulse = -1 }
    property string fieldText: ""
    property bool fieldHasCaret: true

    // state presets (fork caret-flow; daemon drives these live)
    readonly property var presets: ({
        boot:     { field: "",            rail: 0 },
        typed:    { field: "bro",         rail: -1 },
        nomatch:  { field: "zzz",         rail: -1 },
        ai:       { field: "",            rail: 7 },
        stream:   { field: root.aiQuestion, rail: 7 },
        ready:    { field: root.aiQuestion, rail: 7 },
        system:   { field: "",            rail: 4 },
        fleet:    { field: "",            rail: 8 },
        ssh:      { field: "",            rail: 9 },
        snippets: { field: "",            rail: 10 },
        settings: { field: "",            rail: 3 },
        update:   { field: "",            rail: 5 },
        help:     { field: "",            rail: 11 },
        about:    { field: "",            rail: 6 },
        recents:  { field: "",            rail: 2 },
        favs:     { field: "",            rail: 1 },
        category: { field: "",            rail: 0 }
    })

    readonly property var railModel: [
        { group: "Launcher" },
        { tag: "FA", label: "Favorites", value: "★ " + root.favsModel.length, state: "favs",     slot: 1 },
        { tag: "AP", label: "Apps",      value: String(root.liveAppCount),   state: "boot",     slot: 2 },
        { tag: "RE", label: "Recents",   value: "0",                          state: "recents",  slot: 3 },
        { tag: "SE", label: "Settings",  value: String(Data.meta.kcmTotal),   state: "settings", slot: 4 },
        { tag: "SY", label: "System",    value: "5",                          state: "system",   slot: 5 },
        { tag: "UP", label: "Update",    value: "check",                      state: "update",   slot: 6 },
        { tag: "AB", label: "About",     value: "",                           state: "about",    slot: 7 },
        { group: "Fleet" },
        { tag: "AI", label: "AI",        value: root.aiModelName,             state: "ai",       slot: 8 },
        { tag: "FL", label: "Fleet",     value: upCount + "↑",                state: "fleet",    slot: 9 },
        { tag: "SS", label: "SSH",       value: String(root.sshModel.length),state: "ssh" },
        { tag: "SN", label: "Snippets",  value: "0",                          state: "snippets" },
        { tag: "HE", label: "Help",      value: "f1",                         state: "help" }
    ]
    readonly property int upCount: {
        var rows = fleetRows(), n = 0;
        for (var i = 0; i < rows.length; i++) if (rows[i].up) n++;
        return rows.length ? n : 0;
    }

    // live-first category model (frozen fallback for the applet build)
    function bootModel() {
        return (liveCats && liveCats.length > 0) ? liveCats : Data.categories;
    }
    function catList() {
        if (!liveCats) return [];
        for (var i = 0; i < liveCats.length; i++)
            if (liveCats[i].id === activeCatId) return liveCats[i].apps;
        return [];
    }
    function catSample(cat) {
        var out = [];
        for (var i = 0; i < Math.min(3, cat.apps.length); i++)
            out.push(cat.apps[i].name);
        return out.join(" · ");
    }

    // Live app search over the SAME scan that feeds the categories — the
    // frozen demo index never knew real app names ("brave" found nothing).
    // Rank: name-starts-with first, then generic/name substring. Cap 12.
    // Space-insensitive compare (strip spaces both sides) so "auto start"
    // hits "Autostart" — Kickoff parity for settings modules.
    function searchLive(q) {
        var ql = q.toLowerCase(), nq = ql.replace(/ /g, "");
        // ranking tiers (CC r63 required item): true prefix > spaceless
        // prefix > true substring > spaceless substring — "visualstudio"
        // must not outrank an app whose real name starts with the query.
        var startsEx = [], startsSp = [], subsEx = [], subsSp = [];
        var cats = bootModel();
        for (var c = 0; c < cats.length; c++) {
            var apps = cats[c].apps || [];
            for (var a = 0; a < apps.length; a++) {
                var it = apps[a];
                var nm = (it.name || "").toLowerCase();
                var gen = (it.generic || "").toLowerCase();
                var kw = (it.keywords || "").toLowerCase();
                var nm2 = nm.replace(/ /g, ""), gen2 = gen.replace(/ /g, "");
                if (nm.indexOf(ql) === 0) startsEx.push(it);
                else if (nq && nm2.indexOf(nq) === 0) startsSp.push(it);
                else if (nm.indexOf(ql) >= 0 || gen.indexOf(ql) >= 0
                         || kw.indexOf(ql) >= 0) subsEx.push(it);
                else if (nq && (nm2.indexOf(nq) >= 0 || gen2.indexOf(nq) >= 0))
                    subsSp.push(it);
            }
        }
        var hits = startsEx.concat(startsSp, subsEx, subsSp).slice(0, 12);
        // stem tier: a DIFFERENT word sharing a stem ("startup" →
        // "Autostart" — Windows calls it Startup). Longest query prefix
        // (min 4) that appears in the spaceless name; name hits only,
        // ranked last, capped at 4 so wording drift never floods results.
        if (nq.length >= 4 && hits.length < 12) {
            var stemHits = [];
            for (var L = nq.length; L >= 4 && stemHits.length === 0; L--) {
                var stem = nq.substring(0, L);
                for (var c3 = 0; c3 < cats.length && stemHits.length < 4;
                     c3++) {
                    var ap3 = cats[c3].apps || [];
                    for (var a3 = 0; a3 < ap3.length; a3++) {
                        var cd = ap3[a3];
                        if (hits.indexOf(cd) >= 0
                                || stemHits.indexOf(cd) >= 0)
                            continue;
                        var nm3 = (cd.name || "").toLowerCase()
                                           .replace(/ /g, "");
                        if (nm3.indexOf(stem) >= 0) stemHits.push(cd);
                    }
                }
            }
            // CC r65 item 2 tiebreak: shorter name = more specific target
            // first ('Autostart' beats 'Startup Disk Creator'), name-asc
            // for determinism. Dedupe happens during collection, so a
            // prefix length whose candidates are all duplicates leaves
            // stemHits empty and the loop tries shorter prefixes (CC r65
            // item 1's early-exit concern is already covered).
            stemHits.sort(function (x, y) {
                var lx = (x.name || "").length, ly = (y.name || "").length;
                if (lx !== ly) return lx - ly;
                return (x.name || "").toLowerCase()
                        < (y.name || "").toLowerCase() ? -1 : 1;
            });
            hits = hits.concat(stemHits.slice(0, 12 - hits.length));
        }
        if (root.fuzzyOn && q.length >= 3 && hits.length < 6) {
            // subsequence match: every query char in order ("kden" → KDEnlive)
            var fz = [];
            for (var c2 = 0; c2 < cats.length && hits.length + fz.length < 12;
                 c2++) {
                var ap2 = cats[c2].apps || [];
                for (var a2 = 0; a2 < ap2.length; a2++) {
                    var cand = ap2[a2];
                    if (hits.indexOf(cand) >= 0 || fz.indexOf(cand) >= 0)
                        continue;
                    var hay = ((cand.name || "") + " "
                               + (cand.generic || "") + " "
                               + (cand.keywords || "")).toLowerCase();
                    var pi = 0;
                    for (var ci = 0; ci < ql.length && pi >= 0; ci++)
                        pi = hay.indexOf(ql[ci], pi);
                    if (pi >= 0) fz.push(cand);
                }
            }
            hits = hits.concat(fz.slice(0, 12 - hits.length));
        }
        return hits.map(function (it) {
            return { kind: "app", name: it.name,
                     detail: it.generic
                             || (it.bucket === "Settings"
                                 ? "SYSTEM SETTINGS" : ""),
                     path: it.path };
        });
    }

    function gotoState(s, fresh) {
        var target = s;
        confirmArmed = false; confirmAction = "";
        if (s.indexOf("category:") === 0) {
            activeCatId = s.substring(9);
            activeCatLabel = activeCatId;
            var bl = bootModel();
            for (var bi = 0; bi < bl.length; bi++)
                if (bl[bi].id === activeCatId) activeCatLabel = bl[bi].label;
            target = "category";
        }
        var ng = navFor(target);
        lensCount = ng[0]; lensCols = ng[1];
        lensIndex = (target === "boot" || target === "typed" ||
                     target === "nomatch" || target === "stream" ||
                     target === "ready") ? 0 : 1;
        if (lensIndex > lensCount - 1) lensIndex = lensCount - 1;   // empty views
        // zone is NOT reset here: rail-walk previews and BackRow returns
        // must keep their zone. Fresh entry (daemon jump / summon) passes
        // fresh=true — the caller owns that decision.
        if (fresh === true) zone = "field";
        navPulse = -1;
        var p = presets[target];
        if (!p) return;
        state = target;
        // presets literals evaluate once; AI views resolve their field text
        // live so the asked question rides along into stream/ready
        var ft = p.field;
        if ((target === "stream" || target === "ready")
            && root.aiQuestion.length > 0) ft = root.aiQuestion;
        fieldText = ft;
        field.text = ft;
        // railIndex must point at the row that OWNS this state — computed
        // from the model, never from hand-maintained preset numbers (they
        // drifted off-by-one against the group-header rows).
        for (var ri = 0; ri < railModel.length; ri++)
            if (railModel[ri].state === target) { railIndex = ri; break; }
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

    // Cold-open init: a fresh summon must have nav geometry BEFORE any
    // state transition — without this, lensCount stays 1 and arrows are
    // dead until the user changes views once. (caught live 2026-11-08)
    Component.onCompleted: {
        var ng = navFor(state);
        lensCount = ng[0]; lensCols = ng[1];
        for (var ri = 0; ri < railModel.length; ri++)
            if (railModel[ri].state === state) { railIndex = ri; break; }
    }

    // Enter on the Ask row → stream → ready (the demo streaming machine)
    Timer { id: streamTimer; interval: 2600; onTriggered: root.gotoState("ready") }

    // ---- keyboard navigation (minimum bar: arrows + enter + back) ---------
    // Nav geometry per view — SINGLE SOURCE OF TRUTH. gotoState reads this
    // on EVERY entry (views used to publish counts only on first load, so
    // re-entering a view kept the clobbered defaults — caught by check-nav).
    readonly property int liveAppCount: {
        var n = 0, cats = bootModel();
        for (var i = 0; i < cats.length; i++)
            if (cats[i].id !== "Settings")   // settings modules count separately
                n += (cats[i].apps || []).length;
        return n;
    }
    function fleetRows() {
        return fleetModel.length > 0 ? fleetModel : Data.fleet;
    }
    function isFav(path) {
        var id = String(path).substring(String(path).lastIndexOf("/") + 1);
        for (var i = 0; i < root.favsModel.length; i++)
            if (root.favsModel[i].path === path ||
                root.favsModel[i].path === undefined && root.favsModel[i].name === id)
                return true;
        return false;
    }

    // ctrl p on a focused app row: pin/unpin (same path the star click takes)
    // row offset per view: typed rows have NO back row (slot 0 = first app);
    // category/favs/recents put the Back row at slot 0, apps from slot 1
    function pinFocusedRow() {
        var p = null;
        if (root.zone === "lens" && root.lensIndex >= 0) {
            var i = root.lensIndex;
            if (root.state === "category") {
                var lst = catList();
                if (i >= 1 && i - 1 < lst.length) p = lst[i - 1].path;
            } else if (root.state === "typed") {
                var tm = root.typedModel;
                if (i < tm.length && tm[i].kind === "app")
                    p = tm[i].path;
            } else if (root.state === "favs") {
                if (i >= 1 && i - 1 < root.favsModel.length)
                    p = root.favsModel[i - 1].path;
            } else if (root.state === "recents") {
                if (i >= 1 && i - 1 < root.recentsModel.length)
                    p = root.recentsModel[i - 1].path;
            }
        }
        if (p) root.favoriteToggle(p);
    }

    // ctrl+arrows on a focused favorites row move it; the focus follows
    // the row so repeated presses keep walking it in that direction
    function moveFocusedRow(delta) {
        if (root.state !== "favs" || root.zone !== "lens" ||
                root.lensIndex < 1) return false;
        var i = root.lensIndex - 1;               // row 0 = Back row
        if (i + delta < 0 || i + delta >= root.favsModel.length)
            return true;                          // clamped: swallow the key
        root.favoriteMove(i, delta);
        root.lensIndex = i + delta + 1;           // follow the moved row
        return true;
    }

    // every summon opens on Favorites — even when empty, so the empty
    // state (and its pin instructions) is the first thing seen; an
    // in-flight or finished answer keeps its view (stream/ready stay)
    function summonReset() {
        if (root.state === "stream" || root.state === "ready") return;
        gotoState("favs", true);
    }

    function navFor(s) {
        switch (s) {
        case "boot":     return [bootModel().length, 1];
        case "category": return [1 + catList().length, 1];
        case "typed":    return [2, 1];   // apps added live via onCountChanged
        case "nomatch":  return [1, 1];
        case "ai":       return [2 + recentModel.length, 1];
        case "stream":   return [3, 1];
        case "ready":    return [3 + Math.min(2, recentModel.length), 1];
        case "system":   return root.confirmArmed
                              ? [2, 1]
                              : [1 + Data.systemRows.length, 1];
        case "fleet":    return [1 + fleetRows().length, 1];
        case "ssh":      return [1 + sshModel.length, 1];
        case "update":   return [3, 1];   // back · check · history
        case "settings": return [6, 1];   // back · 4 levers · reset
        case "help":     return [11, 1];
        case "recents":  return [1 + recentsModel.length, 1];
        case "favs":     return [1 + favsModel.length, 1];
        default:         return [1, 1];   // about, snippets
        }
    }
    function moveRail(d) {
        var step = railIndex + d;
        while (step >= 0 && step < root.railModel.length) {
            if (root.railModel[step].state !== undefined) break;
            step += d;
        }
        if (step >= 0 && step < root.railModel.length &&
                root.railModel[step].state !== undefined) {
            railIndex = step;
            gotoState(root.railModel[step].state);
        }
    }
    function navKey(k) {
        if (k === "down") {
            if (zone === "field") { zone = "lens"; lensIndex = 0; }
            else if (zone === "rail") moveRail(1);
            else {
                // spatial: one grid ROW down (cols=1 in lists)
                var ni = lensIndex + lensCols;
                if (ni < lensCount) lensIndex = ni;
                else if (lensCount - 1 > lensIndex) lensIndex = lensCount - 1;
                else {
                    var it = lensLoader.item;
                    if (it && it.contentY !== undefined && it.contentHeight > it.height)
                        it.contentY = Math.min(it.contentY + root.rowH,
                                               it.contentHeight - it.height);
                }
            }
        } else if (k === "up") {
            if (zone === "lens") {
                var pi = lensIndex - lensCols;
                if (pi >= 0) lensIndex = pi; else zone = "field";
            }
            else if (zone === "rail") moveRail(-1);
            else zone = "rail";
        } else if (k === "left") {
            // ← ALWAYS escapes to the far-left rail — from ANY option,
            // ANY zone. It never scrolls through the options (user
            // directive 2026-11-08: "arrow over to it", "not just
            // scroll through the submenu options"). Option-walking is
            // → (next) plus ↑/↓ (rows).
            if (zone === "lens" || zone === "field") zone = "rail";
        } else if (k === "right") {
            // → walks options FORWARD in reading order (any column,
            // crossing rows); from field/rail it enters the options.
            if (zone === "field" || zone === "rail") zone = "lens";
            else if (lensIndex < lensCount - 1) lensIndex++;
        } else if (k === "enter") {
            if (zone === "field") {
                if (state === "typed" || state === "nomatch") activateLens(state, lensIndex);
                else { zone = "lens"; if (state === "boot") lensIndex = 0; }
            } else if (zone === "rail") {
                zone = "lens";
            } else {
                activateLens(state, lensIndex);
            }
        }
        ensureLensVisible();
    }
    function ensureLensVisible() {
        var it = lensLoader.item;
        if (!it || it.contentY === undefined) return;
        var rowY = 46 + lensIndex * (root.rowH + 6);
        if (rowY < it.contentY) it.contentY = rowY;
        else if (rowY + root.rowH > it.contentY + it.height)
            it.contentY = Math.min(rowY + root.rowH - it.height,
                                   it.contentHeight - it.height);
    }
    function activateLens(st, i) {
        if (st === "system" && root.confirmArmed) {
            // confirm strip: slot 0 = Cancel (default), slot 1 = Confirm
            if (i === 1) {
                var act = root.confirmAction;
                disarmConfirm();
                root.systemAction(act);
            } else {
                disarmConfirm();
            }
            return;
        }
        // slot 0 is the BackRow in every drill view (incl. stream/ready)
        if (i === 0 && st !== "boot" && st !== "typed" && st !== "nomatch") {
            gotoState("boot"); return;
        }
        if (st === "boot") {
            // every category opens ITS OWN contents — never a stand-in
            var cs = bootModel();
            if (i < cs.length) { gotoState("category:" + cs[i].id); return; }
        }
        if (st === "category") {
            // app rows launch for real (gio launch via the daemon;
            // harness records the desktop-file path instead)
            var lst = catList();
            if (i - 1 >= 0 && i - 1 < lst.length) { launchApp(lst[i - 1].path); return; }
        }
        if (st === "typed") {
            // app rows launch for real; Ask Hermes streams; WEB opens browser
            // NOTE: use root.typedModel — the typedResults id is Component-
            // scoped and does NOT resolve from this root-scope function
            // (a ReferenceError here dies silently: enter did nothing)
            var tmodel = root.typedModel;
            if (i < tmodel.length) { launchApp(tmodel[i].path); return; }
            if (i === tmodel.length) {
                if (root.fieldText.trim().length > 0) {
                    askHermes(root.fieldText.trim());
                    gotoState("stream");
                }
                return;
            }
            launchApp("https://duckduckgo.com/?q=" + encodeURIComponent(root.fieldText));
            return;
        }
        if (st === "update") {
            root.runUpdate(i === 1 ? "check" : "status");
            return;
        }
        if (st === "settings") {
            // slots: 1 scale · 2 opacity · 3 location · 4 fuzzy · 5 reset
            var levers = ["scale", "opacity", "anchor", "fuzzy", "reset"];
            if (i - 1 >= 0 && i - 1 < levers.length)
                settingLever(levers[i - 1]);
            return;
        }
        if (st === "nomatch") {
            if (fieldText.trim().length > 0) {
                askHermes(fieldText.trim());
                gotoState("stream");
            } else gotoState("ai");
            return;
        }
        if (st === "stream" || st === "ready") {
            // slot 1 = Copy (armed when done), slot 2 = Continue in chat
            if (i === 1) { if (root.aiDone && root.aiStream.length > 0)
                               copyText(root.aiStream); }
            else if (i === 2) { if (root.aiDone)
                                    continueChat(root.aiQuestion); }
            return;
        }
        if (st === "ai") {
            // slot 1 = model row (info); recent questions re-ask for real
            if (i >= 2 && i - 2 < recentModel.length) {
                askHermes(recentModel[i - 2]);
                gotoState("stream");
            }
            return;
        }
        if (st === "system") {
            // rows: Lock · Sleep · Log Out · Reboot · Shut Down. Reversible
            // two fire immediately; destructive three arm the confirm strip.
            var sys = ["lock", "sleep", "logout", "reboot", "poweroff"];
            if (i - 1 >= 0 && i - 1 < sys.length) {
                var nm = sys[i - 1];
                if (nm === "logout" || nm === "reboot" || nm === "poweroff") {
                    root.confirmAction = nm;
                    root.confirmLabel = nm === "logout" ? "Log out"
                                      : nm === "reboot" ? "Reboot"
                                      : "Shut down";
                    root.confirmArmed = true;
                    var g = navFor("system");
                    lensCount = g[0]; lensCols = g[1];
                    root.zone = "lens"; root.lensIndex = 0;
                    root.navPulse = -1;
                } else {
                    root.systemAction(nm);
                }
            }
            return;
        }
        if (st === "ssh") {
            if (i - 1 >= 0 && i - 1 < root.sshModel.length)
                root.openSsh(root.sshModel[i - 1].alias);
            return;
        }
        if (st === "recents") {
            if (i - 1 >= 0 && i - 1 < root.recentsModel.length)
                root.launchApp(root.recentsModel[i - 1].path);   // xdg-open
            return;
        }
        if (st === "favs") {
            if (i - 1 >= 0 && i - 1 < root.favsModel.length)
                root.launchApp(root.favsModel[i - 1].path);
            return;
        }
        // remaining rows: action wiring is the live-data phase — pulse ⏎ feedback
        navPulse = i; navPulseT.restart();
    }
    signal launchApp(string exec)
    signal systemAction(string name)
    signal openSsh(string alias)
    signal runUpdate(string which)
    signal probeFleet()
    signal askHermes(string question)
    signal askCancel()
    signal favoriteToggle(string path)
    signal favoriteMove(int index, int delta)
    signal copyText(string text)
    signal continueChat(string question)
    signal settingLever(string name)
    component BackRow: ListRow {
        Layout.fillWidth: true
        Layout.leftMargin: 24; Layout.rightMargin: 24
        tag: "◂"; name: "Back to menu"
        detail: "⏎ returns up a level · esc closes"
        focused: root.zone === "lens" && root.lensIndex === 0
        MouseArea { anchors.fill: parent; onClicked: root.gotoState("boot") }
    }

    // Focusable row for plain label rows (settings, help): accent-tinted
    // DARK fill when active — never a light box (contrast law).
    component NavRow: Rectangle {
        id: nr
        property int slot: 0
        readonly property bool active:
            (root.zone === "lens" && root.lensIndex === slot) || root.navPulse === slot
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.rightMargin: 28
        Layout.preferredHeight: 38
        radius: 8
        color: active ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.10) : "transparent"
        border.width: active ? 2 : 0
        border.color: root.cAccent
        default property alias content: nrl.children
        RowLayout { id: nrl; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10 }
        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, nr.slot) }
    }

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
                    border.color: (field.activeFocus && root.zone === "field") ? root.cAccent : Qt.rgba(1, 1, 1, 0.14)
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
                                root.zone = "field";
                                root.fieldText = text;
                                if (text.length > 0) {
                                    var hits = root.liveCats
                                        ? root.searchLive(text)
                                        : Data.search(text);
                                    root.state = hits.length > 0 ? "typed" : "nomatch";
                                    root.railIndex = -1;
                                    root.typedModel = hits;
                                } else if (root.state === "typed" || root.state === "nomatch") {
                                    root.gotoState("boot");
                                }
                            }
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_P &&
                                        (event.modifiers & Qt.ControlModifier)) {
                                    root.pinFocusedRow();
                                    event.accepted = true;
                                }
                            }
                            Keys.onDownPressed: function(event) {
                                if ((event.modifiers & Qt.ControlModifier) &&
                                        root.moveFocusedRow(1)) return;
                                root.navKey("down");
                            }
                            Keys.onUpPressed: function(event) {
                                if ((event.modifiers & Qt.ControlModifier) &&
                                        root.moveFocusedRow(-1)) return;
                                root.navKey("up");
                            }
                            Keys.onLeftPressed: function(event) {
                                // While browsing options (lens/rail) arrows
                                // are ALWAYS nav keys. In the field, ←
                                // escapes to the rail only once the caret
                                // is at the start of the query.
                                if (root.zone !== "field" ||
                                        field.cursorPosition === 0)
                                    root.navKey("left");
                                else event.accepted = false;
                            }
                            Keys.onRightPressed: function(event) {
                                if (root.zone !== "field" ||
                                        field.cursorPosition >= field.length)
                                    root.navKey("right");
                                else event.accepted = false;
                            }
                            Keys.onReturnPressed: root.navKey("enter")
                            Keys.onEnterPressed: root.navKey("enter")
                            Keys.onEscapePressed: function(event) {
                                if (root.confirmArmed) {
                                    root.disarmConfirm();
                                    event.accepted = true;
                                    return;
                                }
                                if (root.state === "stream" && !root.aiDone) {
                                    root.askCancel();   // keep what arrived
                                    event.accepted = true;
                                    return;
                                }
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
                            text: "search " + root.liveAppCount + " apps · " +
                                  root.sshModel.length + " hosts — or just ask"
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
                                border.width: (root.zone === "rail" && root.railIndex === index) ? 2 : 0
                                border.color: root.cAccent
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
                                Text { visible: root.fleetModel.length > 0; text: "· " + (root.fleetModel.length - root.upCount) + " DOWN · PINGED " + root.fleetStamp; color: root.cNeg; font.pixelSize: Math.round(12 * root.t); font.family: root.mono }
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
                                case "category": return categoryComp;
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
                                case "recents":  return root.recentsModel.length > 0 ? recentsComp : emptyRecentsComp;
                                case "favs":     return root.favsModel.length > 0 ? favsComp : emptyFavsComp;
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
                    text: "⏎ open    ← menu    ⌫ back    ctrl 1–9 jump    alt⏎ secondary    ctrl s settings"
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
        property bool starred: false    // show the pin affordance at all
        property string starPath: ""    // desktop-file path this row pins
        property bool moveArrows: false // favorites: show reorder arrows
        property int moveIndex: 0
        property bool canMoveUp: false
        property bool canMoveDown: false
        signal starClicked()
        signal moveClicked(int index, int delta)
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
                visible: lr.moveArrows
                text: "↑"
                color: lr.canMoveUp ? root.cDim : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                font.pixelSize: Math.round(14 * root.t)
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    enabled: lr.canMoveUp
                    onClicked: lr.moveClicked(lr.moveIndex, -1)
                }
            }
            Text {
                visible: lr.moveArrows
                text: "↓"
                color: lr.canMoveDown ? root.cDim : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                font.pixelSize: Math.round(14 * root.t)
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    enabled: lr.canMoveDown
                    onClicked: lr.moveClicked(lr.moveIndex, 1)
                }
            }
            Text {
                visible: lr.starred
                text: lr.starPath !== "" && root.isFav(lr.starPath) ? "★" : "☆"
                color: lr.starPath !== "" && root.isFav(lr.starPath)
                       ? root.cAccent : root.cDim
                font.pixelSize: Math.round(14 * root.t)
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    onClicked: lr.starClicked()
                }
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
                    title: "ALL CATEGORIES · " + root.bootModel().length
                    note: root.liveCats ? "from installed applications · alphabetical"
                                       : Data.meta.totalApps + " apps · alphabetical within category"
                }
                Repeater {
                    model: root.bootModel()
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: modelData.label.length > 8 ? modelData.label.substring(0, 2).toUpperCase()
                                                        : modelData.label.substring(0, 1).toUpperCase()
                        name: modelData.label
                        detail: modelData.apps ? root.catSample(modelData) : modelData.sample
                        value: String(modelData.apps ? modelData.apps.length : modelData.count)
                        focused: (root.zone === "lens" && root.lensIndex === index) || root.navPulse === index
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens("boot", index) }
                    }
                }
            }
        }
    }

    Component {
        id: categoryComp
        Flickable {
            clip: true
            contentHeight: catCol.height + 28
            ColumnLayout {
                id: catCol
                width: parent.width
                spacing: 0
                SectionHead {
                    title: root.activeCatLabel.toUpperCase() + " · " + root.catList().length
                    note: "installed apps · ⏎ launches"
                }
                BackRow {}
                Repeater {
                    model: root.catList()
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false
                        name: modelData.name
                        detail: modelData.generic
                        value: ""
                        starred: true; starPath: modelData.path
                        onStarClicked: root.favoriteToggle(modelData.path)
                        focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
                    }
                }
            }
        }
    }


    Component {
        id: typedComp
        Flickable {
            clip: true
            contentHeight: typedCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: typedCol
                width: parent.width
                spacing: 0
            SectionHead { title: "APPLICATIONS · " + typedResults.count }
            Repeater {
                id: typedResults
                onCountChanged: root.lensCount = count + 2
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                model: root.typedModel
                delegate: ListRow {
                    id: tr
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    tag: "·"
                    hasTile: modelData.kind === "app"
                    starred: modelData.kind === "app"
                    starPath: modelData.kind === "app" ? modelData.path : ""
                    onStarClicked: if (modelData.kind === "app") root.favoriteToggle(modelData.path)
                    name: modelData.name
                    detail: modelData.detail
                    value: "⏎"
                    focused: (root.zone !== "rail" && root.lensIndex === index) || root.navPulse === index
                }
            }
            SectionHead { title: "HERMES" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "ai"; name: "Ask Hermes"
                detail: root.fieldText + "? — answer lands here"
                value: root.aiModelName
                focused: (root.zone !== "rail" && root.lensIndex === typedResults.count) || root.navPulse === typedResults.count
                MouseArea { anchors.fill: parent; onClicked: root.gotoState("stream") }
            }
            SectionHead { title: "WEB"; note: "fallback only" }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "w"; name: "Search the web"
                detail: "opens in default browser"; value: "↗"
                focused: (root.zone !== "rail" && root.lensIndex === typedResults.count + 1) || root.navPulse === typedResults.count + 1
                MouseArea { anchors.fill: parent; onClicked: root.activateLens("typed", typedResults.count + 1) }
            }
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
                value: root.aiModelName
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
                BackRow {}
                ColumnLayout {
                    Layout.leftMargin: 28; Layout.rightMargin: 28
                    spacing: 10
                    Text { text: "qh?   ask a question — the answer streams here, ⏎ copies it"
                           color: root.cDim; font.pixelSize: Math.round(14 * root.t); font.family: root.mono }
                    Text { text: "hr    hand a task to Hermes — it runs, you get notified"
                           color: root.cDim; font.pixelSize: Math.round(14 * root.t); font.family: root.mono }
                }
                SectionHead { title: "MODEL" }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "☉"; name: root.aiModelName
                    detail: "live · streams via the fleet LLM proxy"
                    value: "✓"
                    focused: (root.zone === "lens" && root.lensIndex === 1) || root.navPulse === 1
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("ai", 1) }
                }
                SectionHead { title: "RECENT QUESTIONS"; note: "questions only — answers are never cached" }
                Repeater {
                    model: root.recentModel
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false
                        name: ""
                        detail: modelData
                        value: "⏎"
                        focused: (root.zone === "lens" && root.lensIndex === index + 2) || root.navPulse === index + 2
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens("ai", index + 2) }
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
                BackRow {}
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
                            Text { text: root.aiDone ? "DONE" : "STREAMING"; color: root.aiDone ? root.cDim : root.cHover; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: "·"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Text { text: root.aiModelName; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Item { Layout.fillWidth: true }
                            Text { text: root.aiQuestion.length > 42 ? root.aiQuestion.substring(0, 42) + "…" : root.aiQuestion; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono; elide: Text.ElideRight }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (root.aiStream || "asking…") + (root.aiDone ? "" : " ▌")
                            color: root.cText
                            font.pixelSize: Math.round(15 * root.t)
                            wrapMode: Text.Wrap
                            lineHeight: 1.25
                        }
                        RowLayout {
                            spacing: 8
                            opacity: root.aiDone ? 1.0 : 0.38
                            Rectangle {
                                width: 90; height: 30; radius: 7
                                border.color: (root.zone === "lens" && root.lensIndex === 1) || root.navPulse === 1 ? root.cAccent : Qt.rgba(1, 1, 1, 0.14)
                                color: "transparent"
                                Text { anchors.centerIn: parent; text: "Copy"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                                MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, 1) }
                            }
                            Rectangle {
                                width: 140; height: 30; radius: 7
                                border.color: (root.zone === "lens" && root.lensIndex === 2) || root.navPulse === 2 ? root.cAccent : Qt.rgba(1, 1, 1, 0.14)
                                color: "transparent"
                                Text { anchors.centerIn: parent; text: "Continue in chat"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                                MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, 2) }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: root.aiDone ? "⏎ COPIES THE ANSWER" : "COPY ARMS WHEN STREAM ENDS"; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
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
                BackRow {}
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
                            Text { text: root.aiModelName; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                            Item { Layout.fillWidth: true }
                            Text { text: root.aiQuestion.length > 42 ? root.aiQuestion.substring(0, 42) + "…" : root.aiQuestion; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono; elide: Text.ElideRight }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.aiStream || "(no answer)"
                            color: root.cText
                            font.pixelSize: Math.round(15 * root.t)
                            wrapMode: Text.Wrap
                            lineHeight: 1.25
                        }
                        RowLayout {
                            spacing: 8
                            Rectangle {
                                width: 118; height: 30; radius: 7
                                border.color: (root.zone === "lens" && root.lensIndex === 1) || root.navPulse === 1 ? root.cAccent : root.cHover
                                color: "transparent"
                                MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, 1) }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Copy"; color: root.cHover; font.pixelSize: Math.round(13 * root.t) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "alt ⏎"; color: root.cHover; font.pixelSize: Math.round(10 * root.t); font.family: root.mono }
                                }
                            }
                            Rectangle {
                                width: 140; height: 30; radius: 7
                                border.color: (root.zone === "lens" && root.lensIndex === 2) || root.navPulse === 2 ? root.cAccent : Qt.rgba(1, 1, 1, 0.14)
                                color: "transparent"
                                Text { anchors.centerIn: parent; text: "Continue in chat"; color: root.cDim; font.pixelSize: Math.round(13 * root.t) }
                                MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, 2) }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "MODEL  " + root.aiModelName; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono }
                        }
                    }
                }
                SectionHead { title: "RECENT QUESTIONS" }
                Repeater {
                    model: root.recentModel.slice(0, 2)
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false; name: ""; detail: modelData
                        value: index === 0 ? "asked " + Data.meta.probedAt : ""
                        focused: (root.zone === "lens" && root.lensIndex === index + 3) || root.navPulse === index + 3
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 3) }
                    }
                }
            }
        }
    }

    Component {
        id: systemComp
        Flickable {
            clip: true
            contentHeight: systemCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: systemCol
                width: parent.width
                spacing: 0
            SectionHead { visible: !root.confirmArmed; title: "POWER & SESSION"; note: "reversible rows act at once" }
            BackRow { visible: !root.confirmArmed }
            Repeater {
                visible: !root.confirmArmed
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
                    focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
                }
            }
            SectionHead { visible: root.confirmArmed; title: "CONFIRM · " + root.confirmLabel.toUpperCase(); note: "Esc or ⏎ on Cancel aborts" }
            ListRow {
                visible: root.confirmArmed
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "NO"; name: "Cancel"; detail: "stay as you are"
                value: "⏎"
                focused: root.zone === "lens" && root.lensIndex === 0
                MouseArea { anchors.fill: parent; onClicked: root.activateLens("system", 0) }
            }
            ListRow {
                visible: root.confirmArmed
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "GO"; name: root.confirmLabel + " now"; detail: "immediate · unsaved work is lost"
                warn: true
                value: "⏎"
                focused: root.zone === "lens" && root.lensIndex === 1
                MouseArea { anchors.fill: parent; onClicked: root.activateLens("system", 1) }
            }
            }
        }
    }

    Component {
        id: fleetComp
        Flickable {
            clip: true
            contentHeight: fleetCol.height + 28
            Component.onCompleted: root.probeFleet()
            ColumnLayout {
                id: fleetCol
                width: parent.width
                spacing: 0
                SectionHead { title: "HOSTS · " + root.fleetRows().length
                          note: root.fleetStamp ? "tcp/22 probe · pinged " + root.fleetStamp
                                                : "probing hosts…" }
                BackRow {}
                Repeater {
                    model: root.fleetRows()
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        hasTile: false
                        monoName: true
                        dot: modelData.up ? "ok" : "down"
                        dimmed: !modelData.up
                        name: modelData.alias || modelData.host
                        detail: modelData.up
                               ? ((modelData.ms !== undefined ? modelData.ms : "") + " ms · ") + (modelData.ip || modelData.role || "")
                               : "down · " + (modelData.ip || modelData.role || "")
                        warn: !modelData.up
                        value: modelData.ip
                        focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
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
                SectionHead { title: "ALIASES · " + root.sshModel.length; note: "⏎ opens a terminal tab · from ~/.ssh/config" }
                BackRow {}
                Repeater {
                    model: root.sshModel
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: "›"
                        monoName: true
                        name: modelData.alias
                        detail: modelData.ip + (modelData.note ? " · " + modelData.note : "")
                        focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
                    }
                }
            }
        }
    }

    Component {
        id: updateComp
        Flickable {
            clip: true
            contentHeight: updateCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: updateCol
                width: parent.width
                spacing: 0
            SectionHead { title: "SYSTEM IMAGE"; note: "bazzite · rpm-ostree" }
            BackRow {}
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "↺"; name: "Check for updates"
                detail: "rpm-ostree upgrade --check · read-only"; value: "⏎"
                focused: (root.zone === "lens" && root.lensIndex === 1) || root.navPulse === 1
                MouseArea { anchors.fill: parent; onClicked: root.runUpdate("check") }
            }
            ListRow {
                Layout.fillWidth: true
                Layout.leftMargin: 24; Layout.rightMargin: 24
                tag: "i"; name: "Deployment history"
                detail: "rpm-ostree status · read-only"; value: "⏎"
                focused: (root.zone === "lens" && root.lensIndex === 2) || root.navPulse === 2
                MouseArea { anchors.fill: parent; onClicked: root.runUpdate("status") }
            }
            // live output of the last run (daemon property, async QProcess)
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 28; Layout.rightMargin: 28
                Layout.topMargin: 14
                visible: root.updateOut.length > 0
                text: root.updateOut
                color: root.cDim
                font.family: root.mono
                font.pixelSize: Math.round(12 * root.t)
                wrapMode: Text.WrapAnywhere
                lineHeight: 1.35
            }
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
                SectionHead { title: "WINDOW & SEARCH"
                              ; note: "⏎ cycles a lever · applies live · persists" }
                BackRow {}
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "SC"; name: "Card scale"
                    detail: "whole-card size · auto fits this display"
                    value: bridge.cardScale.toFixed(2) + "×"
                    focused: (root.zone === "lens" && root.lensIndex === 1) || root.navPulse === 1
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("settings", 1) }
                }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "OP"; name: "Opacity"
                    detail: "card translucency · text stays readable"
                    value: Math.round(bridge.cardOpacity) + "%"
                    focused: (root.zone === "lens" && root.lensIndex === 2) || root.navPulse === 2
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("settings", 2) }
                }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "LO"; name: "Location"
                    detail: "where the card opens on screen"
                    value: bridge.cardAnchor
                    focused: (root.zone === "lens" && root.lensIndex === 3) || root.navPulse === 3
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("settings", 3) }
                }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "FZ"; name: "Fuzzy search"
                    detail: "subsequence match for 3+ chars"
                    value: bridge.fuzzy ? "on" : "off"
                    focused: (root.zone === "lens" && root.lensIndex === 4) || root.navPulse === 4
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("settings", 4) }
                }
                SectionHead { title: "DEFAULTS"; note: "levers live in ~/.config/foyer/config.json" }
                ListRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    tag: "RS"; name: "Reset to defaults"
                    detail: "window + search levers back to stock (AI config kept)"
                    value: "⏎"
                    focused: (root.zone === "lens" && root.lensIndex === 5) || root.navPulse === 5
                    MouseArea { anchors.fill: parent; onClicked: root.activateLens("settings", 5) }
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
                BackRow {}
                Repeater {
                    model: [
                        { k: "type",   d: "filter — the field keeps the caret; ⏎ runs the top hit" },
                        { k: "↓ ↑",    d: "walk rows — ↑ from the first row returns to the field" },
                        { k: "→ ←",    d: "→ next option · ← jumps to the menu rail" },
                        { k: "⌫",      d: "pop a level first, then clear the query" },
                        { k: "esc",    d: "clear query → back a level → close at root" },
                        { k: "ctrl 1–9", d: "jump to a branch — numbers are pinned to the rail" },
                        { k: "alt ⏎",  d: "secondary action — copy an answer, pin a row" },
                        { k: "ctrl p", d: "pin / unpin to Favorites" },
                        { k: "ctrl s · ctrl ,", d: "settings · sources" },
                        { k: "del",    d: "uninstall an app — always asks first" }
                    ]
                    delegate: NavRow {
                        required property var modelData
                        required property int index
                        slot: index + 1
                        Text { text: modelData.k; color: root.cDim; font.pixelSize: Math.round(11 * root.t); font.family: root.mono; Layout.preferredWidth: 180 }
                        Text { text: modelData.d; color: root.cText; font.pixelSize: Math.round(13 * root.t); Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }
    }

    Component {
        id: aboutComp
        Flickable {
            clip: true
            contentHeight: aboutCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: aboutCol
                width: parent.width
                spacing: 0
            SectionHead { title: "FOYER FOR KDE" }
            BackRow {}
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
    }

    Component {
        id: recentsComp
        Flickable {
            clip: true
            contentHeight: recentsCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: recentsCol
                width: parent.width
                spacing: 0
                SectionHead { title: "RECENTS · " + root.recentsModel.length; note: "recently-used.xbel · files, never content" }
                BackRow {}
                Repeater {
                    model: root.recentsModel
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: "·"; name: modelData.name
                        detail: modelData.detail; value: "⏎"
                        starred: true; starPath: modelData.path
                        onStarClicked: root.favoriteToggle(modelData.path)
                        focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
                    }
                }
            }
        }
    }

    Component {
        id: favsComp
        Flickable {
            clip: true
            contentHeight: favsCol.height + 28
            boundsBehavior: Flickable.StopAtBounds
            function forceFocus() {}
            ColumnLayout {
                id: favsCol
                width: parent.width
                spacing: 0
                SectionHead { title: "FAVORITES · " + root.favsModel.length; note: "your first screen · seeded once from Kickoff" }
                BackRow {}
                Repeater {
                    model: root.favsModel
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 24; Layout.rightMargin: 24
                        tag: "·"; name: modelData.name
                        detail: modelData.generic || ""; value: "⏎"
                        starred: true; starPath: modelData.path
                        onStarClicked: root.favoriteToggle(modelData.path)
                        focused: (root.zone === "lens" && root.lensIndex === index + 1) || root.navPulse === index + 1
                        moveArrows: true
                        moveIndex: index
                        canMoveUp: index > 0
                        canMoveDown: index < root.favsModel.length - 1
                        onMoveClicked: function(index, delta) {
                            root.favoriteMove(index, delta)
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.activateLens(root.state, index + 1) }
                    }
                }
            }
        }
    }

    Component {
        id: emptyRecentsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "RECENTS" }
            BackRow {}
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "Nothing recent yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "Recently-used is empty on this machine.\nFiles and documents land here as you open them."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }

    Component {
        id: emptyFavsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "FAVORITES" }
            BackRow {}
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "No pins yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "★ click or ctrl p on any app row pins it here.\nFavorites live in ~/.local/share/foyer/favorites.json. Max 30."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }

    Component {
        id: emptySnipsComp
        ColumnLayout {
            spacing: 0
            SectionHead { title: "SNIPPETS" }
            BackRow {}
            Item { Layout.preferredHeight: 12 }
            Text { Layout.leftMargin: 28; text: "No snippets yet"; color: root.cText; font.pixelSize: Math.round(15 * root.t); font.bold: true }
            Text {
                Layout.leftMargin: 28; Layout.topMargin: 6
                text: "No snippet source is configured yet.\nThe lane lights up the day one is wired — it will not pretend otherwise."
                color: root.cDim; font.pixelSize: Math.round(13 * root.t); lineHeight: 1.5
            }
        }
    }
}
