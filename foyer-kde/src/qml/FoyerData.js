// FoyerData.js — REAL fleet data snapshot, gathered 2026-11-07 (~15:53 CST)
// Sources: ~/.cache/hermes-runner/apps.json (.desktop scan), kcmshell --list,
// ~/.ssh/config, live ICMP probe, ~/.config/hermes-runner/config.json.
// The daemon replaces this with live providers; values here are the frozen set
// the design gallery was verified against.

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
    { alias: "host-01",     ip: "192.0.2.246", note: "" },
    { alias: "host-02",      ip: "192.0.2.243", note: "" },
    { alias: "host-03",       ip: "192.0.2.239", note: "" },
    { alias: "jellyfin",    ip: "192.0.2.238", note: "" },
    { alias: "host-05", ip: "192.0.2.250", note: "" },
    { alias: "nas",         ip: "192.0.2.252", note: "nasserver" },
    { alias: "host-06",  ip: "192.0.2.251", note: "" },
    { alias: "micro",       ip: "192.0.2.240", note: "" },
    { alias: "node",        ip: "192.0.2.248", note: "" },
    { alias: "host-04",  ip: "192.0.2.249", note: "" },
    { alias: "host-07",        ip: "192.0.2.245", note: "spark" },
    { alias: "host-08",        ip: "192.0.2.242", note: "host-13" },
    { alias: "host-09",        ip: "192.0.2.241", note: "host-14" },
    { alias: "host-10",        ip: "192.0.2.244", note: "" }
];

// live ICMP probe 2026-11-07 15:53 CST, 1s timeout — 13 UP, nas DOWN
var fleet = [
    { host: "tower",     role: "this host · bazzite · plasma 6.8", ip: "local", up: true },
    { host: "host-01",     role: "GPU node · 3090 + 3090 ti",        ip: ".246",  up: true },
    { host: "host-02",      role: "services · litellm :4000",         ip: ".243",  up: true },
    { host: "host-03",       role: "stt · tts gpus",                   ip: ".239",  up: true },
    { host: "jellyfin",    role: "media server",                     ip: ".238",  up: true },
    { host: "host-05", role: "media lane",                       ip: ".250",  up: true },
    { host: "nas",         role: "unraid array · elastic lives here",ip: ".252",  up: false },
    { host: "host-06",  role: "ns canonical library",             ip: ".251",  up: true },
    { host: "micro",       role: "haos vm host",                     ip: ".240",  up: true },
    { host: "node",        role: "fleet host",                       ip: ".248",  up: true },
    { host: "host-04",  role: "fleet host",                       ip: ".249",  up: true },
    { host: "host-07",        role: "spark node",                       ip: ".245",  up: true },
    { host: "host-08",        role: "spark node",                       ip: ".242",  up: true },
    { host: "host-09",        role: "spark node",                       ip: ".241",  up: true }
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
    streamingText: "13 of 14 fleet hosts are up. The only one down is nas (192.0.2.252) — the unraid array box. Everything else answered a ping just now",
    body: [
        "13 of 14 fleet hosts are up. The only one down is nas (192.0.2.252) — the unraid array box. Everything else answered a ping just now: host-02, host-01, host-03, jellyfin, host-05, host-06, micro, node, host-04, host-07, host-08, host-09, host-10.",
        "Probe ran 15:53 CST — 1s timeout, ICMP only. Want me to check nas properly — wake-on-lan or ssh?"
    ]
};

var systemRows = [
    { name: "Lock Screen", detail: "enter locks now",                      warn: false },
    { name: "Sleep",       detail: "enter sleeps now",                     warn: false },
    { name: "Log Out",     detail: "closes open apps · session gdeyoung",  warn: true },
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
