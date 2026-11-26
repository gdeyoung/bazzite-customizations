// FoyerData.js — frozen demo snapshot (host-01…host-13, RFC 5737 addresses; the
// shape the design gallery was verified against, gathered from a .desktop scan,
// kcmshell --list, an ssh config and a live ICMP probe). No real host, address or
// account is named here — the daemon replaces this file with live providers.

.pragma library

var meta = {
    totalApps: 250,
    kcmTotal: 83,
    probedAt: "15:53"
};

var categories = [
    { id: "Network",    label: "Internet",       count: 15, sample: "Firefox · Brave · Chromium" },
    { id: "Game",       label: "Games",          count: 14, sample: "Brotato · Avorion · DuckStation" },
    { id: "Utility",    label: "Utilities",      count: 14, sample: "Ark · Bottles · Claude" },
    { id: "System",     label: "System Tools",   count: 14, sample: "Dolphin · Konsole · Bitwarden" },
    { id: "AudioVideo", label: "Audio & Video",  count: 14, sample: "Kdenlive · Haruna · Strawberry" },
    { id: "Office",     label: "Office",         count: 14, sample: "LibreOffice · calibre · Joplin" },
    { id: "Development",label: "Development",    count: 10, sample: "Kate · Antigravity · Goose" },
    { id: "Graphics",   label: "Graphics",       count: 6,  sample: "Blender · Inkscape · Gwenview" },
    { id: "Audio",      label: "Audio",          count: 5,  sample: "Cider · Reco · Chapterize" },
    { id: "Other",      label: "Other",          count: 4,  sample: "OpenGamepadUI · Messages" },
    { id: "Settings",   label: "Config Tools",   count: 4,  sample: "System Settings · Input Remapper" },
    { id: "TextEditor", label: "Text Editors",   count: 4,  sample: "VS Code · Cursor · Void" }
];

var games = [
    { name: "9 Kings",                     detail: "Steam" },
    { name: "Ad Fundum",                   detail: "Steam" },
    { name: "After Inc: Revival",          detail: "Steam" },
    { name: "Age of Mythology: Retold",    detail: "Steam" },
    { name: "Avorion",                     detail: "Steam" },
    { name: "Beyond All Reason",           detail: "RTS" },
    { name: "Boneraiser Minions",          detail: "Steam" },
    { name: "Brotato",                     detail: "Steam" },
    { name: "Cemu AppImage",               detail: "Wii U" },
    { name: "Dolphin Emulator",            detail: "Wii/GameCube Emulator" },
    { name: "DOSVault",                    detail: "eXoDOS via Pegasus" },
    { name: "Driftland: The Magic Revival",detail: "Steam" },
    { name: "DuckStation",                 detail: "PlayStation 1 Emulator" },
    { name: "EmuDeck",                     detail: "Emulation manager" }
];

// 30 of 83 KCMs (alphabetical head)
var kcms = [
    "About this System","Accessibility","Activities","Animations","Application Permissions",
    "Application Style","Audio CDs","Autostart","Background Services","Bluetooth",
    "Breeze Window Decoration","CDDB Retrieval","Cellular Network","Color Management","Colors",
    "Connection Preferences","Date & Time","Day-Night Cycle","Default Applications","Desktop Effects",
    "Default Applications","Display and Monitor","Feedback","Fonts","General Behavior",
    "Icon Theme","Input Devices","Keyboard","Konsole Settings","KRunner"
];

var sshHosts = [
    { alias: "host-01", ip: "192.0.2.11", note: "" },
    { alias: "host-02", ip: "192.0.2.12", note: "" },
    { alias: "host-03", ip: "192.0.2.13", note: "" },
    { alias: "host-04", ip: "192.0.2.14", note: "" },
    { alias: "host-05", ip: "192.0.2.15", note: "" },
    { alias: "host-06", ip: "192.0.2.16", note: "" },
    { alias: "host-07", ip: "192.0.2.17", note: "" },
    { alias: "host-08", ip: "192.0.2.18", note: "" },
    { alias: "host-09", ip: "192.0.2.19", note: "" },
    { alias: "host-10", ip: "192.0.2.20", note: "" },
    { alias: "host-11", ip: "192.0.2.21", note: "" },
    { alias: "host-12", ip: "192.0.2.22", note: "" },
    { alias: "host-13", ip: "192.0.2.23", note: "" }
];

// ICMP probe shape — 13 UP, one DOWN (host-06)
var fleet = [
    { host: "tower",  role: "this host · bazzite · plasma 6", ip: "local", up: true },
    { host: "host-01", role: "gpu node", ip: ".11", up: true },
    { host: "host-02", role: "services", ip: ".12", up: true },
    { host: "host-03", role: "media server", ip: ".13", up: true },
    { host: "host-04", role: "fleet host", ip: ".14", up: true },
    { host: "host-05", role: "media lane", ip: ".15", up: true },
    { host: "host-06", role: "storage array", ip: ".16", up: false },
    { host: "host-07", role: "vm host", ip: ".17", up: true },
    { host: "host-08", role: "fleet host", ip: ".18", up: true },
    { host: "host-09", role: "spark node", ip: ".19", up: true },
    { host: "host-10", role: "spark node", ip: ".20", up: true },
    { host: "host-11", role: "spark node", ip: ".21", up: true },
    { host: "host-12", role: "fleet host", ip: ".22", up: true },
    { host: "host-13", role: "fleet host", ip: ".23", up: true }
];

// hermes-runner config (values only; no keys)
var ai = {
    model: "local-fast",
    via: "host-02 :4000",
    answerPrefix: "ai",
    taskPrefix: "hr",
    copyOnEnter: true,
    maxChars: 700,
    recentQuestions: [
        "which hosts are up right now?",
        "why does krunner cap results at 15?",
        "how do i port foyer to kde plasma?"
    ]
};

var aiAnswer = {
    q: "which hosts are up right now?",
    streamingText: "13 of 14 fleet hosts are up. The only one down is host-06 (192.0.2.16) — the storage array box. Everything else answered a ping just now",
    body: [
        "13 of 14 fleet hosts are up. The only one down is host-06 (192.0.2.16) — the storage array box. Everything else answered a ping just now: host-02, host-01, host-03, host-04, host-05, host-07, host-08, host-09, host-10, host-11, host-12, host-13.",
        "Probe ran 15:53 CST — 1s timeout, ICMP only. Want me to check host-06 properly — wake-on-lan or ssh?"
    ]
};

var systemRows = [
    { name: "Lock Screen", detail: "enter locks now",                      warn: false },
    { name: "Sleep",       detail: "enter sleeps now",                     warn: false },
    { name: "Log Out",     detail: "closes open apps · ends the session",  warn: true },
    { name: "Reboot",      detail: "closes open apps · boots staged deployment if any", warn: true },
    { name: "Shut Down",   detail: "closes open apps · powers off",        warn: true }
];

// typed-search demo: substring over categories + apps (subset semantics)
function search(q) {
    var out = [];
    if (!q) return out;
    var ql = q.toLowerCase();
    for (var i = 0; i < categories.length; i++) {
        var c = categories[i];
        if (c.label.toLowerCase().indexOf(ql) >= 0)
            out.push({ kind: "category", name: c.label, detail: "category · " + c.count + " apps" });
    }
    var pools = { "Games": games };
    for (var k in pools) {
        for (var j = 0; j < pools[k].length; j++) {
            var a = pools[k][j];
            if (a.name.toLowerCase().indexOf(ql) >= 0)
                out.push({ kind: "app", name: a.name, detail: k + " · " + a.detail });
        }
    }
    return out;
}
