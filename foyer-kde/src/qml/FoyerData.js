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
    { alias: "aitower",     ip: "192.168.1.246", note: "" },
    { alias: "aicube",      ip: "192.168.1.243", note: "" },
    { alias: "aibox",       ip: "192.168.1.239", note: "" },
    { alias: "jellyfin",    ip: "192.168.1.238", note: "" },
    { alias: "mediaserver", ip: "192.168.1.250", note: "" },
    { alias: "nas",         ip: "192.168.1.252", note: "nasserver" },
    { alias: "homeserver",  ip: "192.168.1.251", note: "" },
    { alias: "micro",       ip: "192.168.1.240", note: "" },
    { alias: "node",        ip: "192.168.1.248", note: "" },
    { alias: "watertower",  ip: "192.168.1.249", note: "" },
    { alias: "gx10",        ip: "192.168.1.245", note: "spark" },
    { alias: "gx11",        ip: "192.168.1.242", note: "spark2" },
    { alias: "gx12",        ip: "192.168.1.241", note: "spark3" },
    { alias: "gx13",        ip: "192.168.1.244", note: "" }
];

// live ICMP probe 2026-11-07 15:53 CST, 1s timeout — 13 UP, nas DOWN
var fleet = [
    { host: "gdtower",     role: "this host · bazzite · plasma 6.8", ip: "local", up: true },
    { host: "aitower",     role: "GPU node · 3090 + 3090 ti",        ip: ".246",  up: true },
    { host: "aicube",      role: "services · litellm :4000",         ip: ".243",  up: true },
    { host: "aibox",       role: "stt · tts gpus",                   ip: ".239",  up: true },
    { host: "jellyfin",    role: "media server",                     ip: ".238",  up: true },
    { host: "mediaserver", role: "media lane",                       ip: ".250",  up: true },
    { host: "nas",         role: "unraid array · elastic lives here",ip: ".252",  up: false },
    { host: "homeserver",  role: "ns canonical library",             ip: ".251",  up: true },
    { host: "micro",       role: "haos vm host",                     ip: ".240",  up: true },
    { host: "node",        role: "fleet host",                       ip: ".248",  up: true },
    { host: "watertower",  role: "fleet host",                       ip: ".249",  up: true },
    { host: "gx10",        role: "spark node",                       ip: ".245",  up: true },
    { host: "gx11",        role: "spark node",                       ip: ".242",  up: true },
    { host: "gx12",        role: "spark node",                       ip: ".241",  up: true }
];

// hermes-runner config (values only; no keys)
var ai = {
    model: "local-fast",
    via: "aicube :4000",
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
    streamingText: "13 of 14 fleet hosts are up. The only one down is nas (192.168.1.252) — the unraid array box. Everything else answered a ping just now",
    body: [
        "13 of 14 fleet hosts are up. The only one down is nas (192.168.1.252) — the unraid array box. Everything else answered a ping just now: aicube, aitower, aibox, jellyfin, mediaserver, homeserver, micro, node, watertower, gx10, gx11, gx12, gx13.",
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
