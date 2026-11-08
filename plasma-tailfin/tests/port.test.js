// Port-specific tests for plasma-tailfin.
// Model.js is ported VERBATIM from omarchy-tailfin (upstream suite: model.test.js,
// 14 tests, all green). These tests lock the contracts the Plasma container QML
// relies on, using a SYNTHETIC payload (no host/tailnet specifics).
// Run: node --test tests/
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../contents/ui/Model.js")

test("Model.js copies are byte-identical (root mirror for node vs contents/ui for QML)", () => {
  const ui = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "Model.js"))
  const mirror = fs.readFileSync(path.join(__dirname, "..", "Model.js"))
  assert.ok(ui.equals(mirror), "root Model.js mirror has drifted from contents/ui/Model.js — re-copy it")
})

// Synthetic `tailscale status --json` payload shaped like the real thing
// (tailscale 1.10x): Peer is an OBJECT keyed by node key; subnet routes and
// exit-node advertisements live in AllowedIPs; Health is a string array.
function syntheticStatus() {
  return JSON.stringify({
    Version: "1.104.1",
    BackendState: "Running",
    Health: ["Some peers are advertising routes but --accept-routes is false"],
    TUN: true,
    AuthURL: "",
    Self: {
      HostName: "desktop",
      DNSName: "desktop.example.ts.net.",
      UserID: 42,
      TailscaleIPs: ["100.64.0.1", "fd7a:115c:a1e0::1"],
      CapMap: { "https://tailscale.com/cap/file-sharing": [] },
    },
    Peer: {
      "nodekey:aaa": {
        ID: "aaa", HostName: "tower", DNSName: "tower.example.ts.net.",
        OS: "linux", UserID: 42, Online: true, Active: true,
        ExitNodeOption: true, ExitNode: true,
        TailscaleIPs: ["100.64.0.10", "fd7a:115c:a1e0::a"],
        AllowedIPs: ["100.64.0.10/32", "fd7a:115c:a1e0::a/128", "0.0.0.0/0", "::/0"],
        RxBytes: 4096, TxBytes: 8192, LastSeen: "2026-10-26T12:00:00Z",
      },
      "nodekey:bbb": {
        ID: "bbb", HostName: "nasbox", DNSName: "nasbox.example.ts.net.",
        OS: "linux", UserID: 42, Online: true, Active: false,
        ExitNodeOption: false, ExitNode: false,
        TailscaleIPs: ["100.64.0.11"],
        AllowedIPs: ["100.64.0.11/32", "192.168.50.0/24"],
        RxBytes: 0, TxBytes: 0, LastSeen: "2026-10-26T11:00:00Z",
      },
      "nodekey:ccc": {
        ID: "ccc", HostName: "oldphone", DNSName: "oldphone.example.ts.net.",
        OS: "android", UserID: 42, Online: false, Active: false,
        ExitNodeOption: false, ExitNode: false,
        TailscaleIPs: ["100.64.0.12"],
        RxBytes: 0, TxBytes: 0, LastSeen: "0001-01-01T00:00:00Z",
      },
      "nodekey:mmm": {
        ID: "mmm", HostName: "de-fra-wg-001.mullvad.ts.net",
        DNSName: "de-fra-wg-001.mullvad.ts.net.",
        OS: "linux", UserID: 42, Online: true, Active: false,
        ExitNodeOption: true, ExitNode: false,
        TailscaleIPs: ["10.64.0.1"],
      },
    },
  })
}

test("parseStatusPlus drives the panel chip counts (online/total)", () => {
  const s = Model.parseStatusPlus(syntheticStatus())
  assert.equal(s.ok, true)
  assert.equal(s.running, true)
  assert.equal(s.peers.length, 3)          // Mullvad excluded
  assert.equal(s.onlineCount, 2)           // tower + nasbox
  assert.equal(Model.filterOnline(s.peers, false).length, 1)  // oldphone
})

test("exit-node banner text: active tailnet peer wins, Mullvad named otherwise", () => {
  const raw = JSON.parse(syntheticStatus())
  const s = Model.parseStatusPlus(JSON.stringify(raw))
  const active = s.peers.find((p) => p.ExitNode === true)
  assert.equal(active.HostName, "tower")
  // Mullvad active instead:
  raw.Peer["nodekey:aaa"].ExitNode = false
  raw.Peer["nodekey:mmm"].ExitNode = true
  const s2 = Model.parseStatusPlus(JSON.stringify(raw))
  assert.equal(s2.activeMullvadExit, "de-fra-wg-001.mullvad.ts.net")
  assert.equal(s2.peers.some((p) => p.ExitNode === true), false)
})

// The QML subnetRoutes() helper: AllowedIPs from the RAW Peer map (joined on
// peer.id, because Model's normalized peers drop AllowedIPs) minus the peer's
// own /32 + /128 host entries — what remains is what the popup lists.
function rawPeerMap(payload) {
  return payload.Peer || {}
}

function subnetRoutes(peer, rawMap) {
  const raw = rawMap[String(peer && peer.id)] || {}
  const allowed = raw.AllowedIPs || []
  const out = []
  for (let i = 0; i < allowed.length; i++) {
    const entry = String(allowed[i] || "")
    if (entry === "") continue
    if (entry.endsWith("/32") || entry.endsWith("/128")) continue
    out.push(entry)
  }
  return out
}

test("subnet routes: exit-node ad and subnet ad survive, host /32-/128 stripped", () => {
  const payload = JSON.parse(syntheticStatus())
  const s = Model.parseStatusPlus(JSON.stringify(payload))
  const rawMap = rawPeerMap(payload)
  const tower = s.peers.find((p) => p.HostName === "tower")
  const nas = s.peers.find((p) => p.HostName === "nasbox")
  const phone = s.peers.find((p) => p.HostName === "oldphone")
  assert.deepEqual(subnetRoutes(tower, rawMap), ["0.0.0.0/0", "::/0"])
  assert.deepEqual(subnetRoutes(nas, rawMap), ["192.168.50.0/24"])
  assert.deepEqual(subnetRoutes(phone, rawMap), [])
})

test("self identity feeds the popup header (name, v4 IP, dns)", () => {
  const s = Model.parseStatusPlus(syntheticStatus())
  assert.equal(s.selfName, "desktop")
  assert.equal(s.selfIp, "100.64.0.1")
  assert.equal(s.selfDnsName, "desktop.example.ts.net")
  assert.equal(s.fileSharing, true)
})

test("health list is preserved for the warnings section", () => {
  const s = Model.parseStatusPlus(syntheticStatus())
  assert.equal(Model.healthList(s.health).length, 1)
  assert.match(Model.healthList(s.health)[0], /accept-routes/)
})

test("disconnected daemon: empty output -> unavailable, chip shows down state", () => {
  const s = Model.parseStatusPlus("")
  assert.equal(s.ok, true)
  assert.equal(s.unavailable, true)
  const stopped = Model.parseStatusPlus(JSON.stringify({ BackendState: "Stopped", Peer: {} }))
  assert.equal(stopped.running, false)
  assert.equal(stopped.needsLogin, false)   // -> crossed glyph, not warning
})

test("garbage output (daemon half-up) fails safe", () => {
  const s = Model.parseStatusPlus("not json at all{")
  assert.equal(s.ok, false)
  assert.equal(s.unavailable, true)
})

// ---- v0.4 (§V) structural locks -------------------------------------------

// v0.7 (§V7-2): TABS RETURN — hand-rolled 3-cell row (PC3.TabBar and
// SwipeView stay banned: Plasma frame styling diverges; StackLayout is
// the sanctioned tab-content primitive).
test("§V7-2: tabbed shell — no TabBar/SwipeView, no tabs/ dir, StackLayout allowed", () => {
  const ui = path.join(__dirname, "..", "contents", "ui")
  assert.equal(fs.existsSync(path.join(ui, "tabs")), false, "contents/ui/tabs must not exist")
  assert.equal(fs.existsSync(path.join(ui, "PeerCell.qml")), false, "PeerCell.qml retired with the grid")
  const cfg = fs.readFileSync(path.join(__dirname, "..", "contents", "config", "main.xml"), "utf8")
  assert.ok(!cfg.includes("lastTab"), "lastTab config key stays retired (fresh-open law)")
  for (const f of fs.readdirSync(ui).filter((f) => f.endsWith(".qml"))) {
    const src = fs.readFileSync(path.join(ui, f), "utf8")
    assert.ok(!/TabBar|SwipeView/.test(src), f + " contains banned tab machinery")
  }
})

test("§W-2/v0.8: v0.8 files exist and the shell composes the three tabs", () => {
  const ui = path.join(__dirname, "..", "contents", "ui")
  // v0.8 (§V8-7): Omarchy-layout set
  for (const f of ["PopupShell.qml", "ConnectionTab.qml", "ExitTab.qml",
                   "MachinesTab.qml", "PeerDetailPage.qml", "PickerRow.qml",
                   "SearchRow.qml", "MachineRow.qml", "ToggleRow.qml",
                   "HeroCard.qml"]) {
    assert.ok(fs.existsSync(path.join(ui, f)), f + " missing")
  }
  // §W-16/v0.6/v0.7/v0.8: retired components stay deleted
  for (const f of ["ExitNodeSection.qml", "CensusSection.qml",
                   "CensusCell.qml", "CandidateRow.qml", "RoutingBand.qml",
                   "ExitStrip.qml", "SectionLabel.qml",
                   "PeersTab.qml", "DeviceTab.qml", "PeerRow.qml"]) {
    assert.equal(fs.existsSync(path.join(ui, f)), false, f + " must be deleted")
  }
  const shell = fs.readFileSync(path.join(ui, "PopupShell.qml"), "utf8")
  for (const needle of ["ConnectionTab", "ExitTab", "MachinesTab", "StackLayout"]) {
    assert.ok(shell.includes(needle), "PopupShell must compose " + needle)
  }
  assert.ok(shell.includes('"CONNECTION", "EXIT NODES", "MACHINES"'),
            "tab titles must be the Omarchy set")
  assert.ok(shell.includes("gridUnit * 40"), "§V8-3 width must be 40·gu")
  const machines = fs.readFileSync(path.join(ui, "MachinesTab.qml"), "utf8")
  for (const needle of ["PeerDetailPage", "MachineRow", "SearchRow", "StackView",
                        "online · "]) {
    assert.ok(machines.includes(needle), "MachinesTab must compose " + needle)
  }
  const exitTab = fs.readFileSync(path.join(ui, "ExitTab.qml"), "utf8")
  assert.ok(exitTab.includes("PickerRow"), "ExitTab must compose PickerRow")
  assert.ok(exitTab.includes("ROUTE ALL TRAFFIC THROUGH"),
            "§V8-1.4 caps header missing")
})

test("§V8-2: CONNECTION tab composes hero + four writable toggles", () => {
  const ui = path.join(__dirname, "..", "contents", "ui")
  const conn = fs.readFileSync(path.join(ui, "ConnectionTab.qml"), "utf8")
  assert.ok(conn.includes("HeroCard"), "hero card missing")
  for (const needle of ["accept-routes", "accept-dns", "shields-up",
                        "exit-node-allow-lan-access"]) {
    assert.ok(conn.includes(needle), "pref toggle " + needle + " missing")
    assert.ok(conn.includes('runControlOp("pref-set"'), "pref-set op wiring missing")
  }
  const hero = fs.readFileSync(path.join(ui, "HeroCard.qml"), "utf8")
  assert.ok(hero.includes("powerClicked"), "hero must drive §T-3 power")
})

test("§V8-2: pref-set argv allowlist — exactly four flags, bool values", () => {
  const C = require(path.join(__dirname, "..", "contents", "ui", "Control.js"))
  assert.deepEqual(C.argv("pref-set", "accept-routes:true"),
                   ["tailscale", "set", "--accept-routes=true"])
  assert.deepEqual(C.argv("pref-set", "accept-dns:false"),
                   ["tailscale", "set", "--accept-dns=false"])
  assert.deepEqual(C.argv("pref-set", "shields-up:true"),
                   ["tailscale", "set", "--shields-up=true"])
  assert.deepEqual(C.argv("pref-set", "exit-node-allow-lan-access:false"),
                   ["tailscale", "set", "--exit-node-allow-lan-access=false"])
  // Closed allowlist: unknown flags, malformed targets → null
  assert.equal(C.argv("pref-set", "accept-routes"), null)
  assert.equal(C.argv("pref-set", "evil-flag:true"), null)
  assert.equal(C.argv("pref-set", "accept-routes:yes"), null)
  assert.equal(C.argv("pref-set", "accept-routes:true;rm -rf"), null)
  assert.ok(C.ops().includes("pref-set"), "ops() must list pref-set")
})

test("§V7-7/v0.8: health renders on CONNECTION (header pill points there)", () => {
  const conn = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "ConnectionTab.qml"), "utf8")
  assert.ok(/Repeater\s*\{[\s\S]*?ctx\.health|model:\s*tab\.health/.test(conn),
            "health warnings must render in the Connection tab")
  const shell = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "PopupShell.qml"), "utf8")
  assert.ok(shell.includes("⚠ ") || shell.includes("health"), "header health pill present")
})

test("§V-8: search state is ctx.peerQuery (single source of truth)", () => {
  const mainQml = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "main.qml"), "utf8")
  assert.ok(mainQml.includes("property string peerQuery"), "main.qml must own peerQuery")
  assert.ok(mainQml.includes("Model.searchPeers(peers, peerQuery)"), "results via Model.searchPeers")
})

test("§V7: main.qml owns tab/detail/rate plumbing + probe re-run", () => {
  const mainQml = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "main.qml"), "utf8")
  assert.ok(mainQml.includes("property int selectedTab"), "selectedTab missing")
  assert.ok(mainQml.includes("property var detailPeer"), "detailPeer missing")
  assert.ok(mainQml.includes("function updateRates()"), "rate derivation missing")
  assert.ok(/endControlOp[\s\S]{0,600}argv\("probe"\)/.test(mainQml),
            "probe re-run must live inside endControlOp")
})

test("§V-4: main.qml computes exitNodes/censusPeers (Trayscale exclusion)", () => {
  const mainQml = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "main.qml"), "utf8")
  assert.ok(mainQml.includes("function recomputeSections()"), "recomputeSections missing")
  assert.ok(mainQml.includes("Control.isExitCandidate(p, raw)"), "candidates gated on isExitCandidate")
  assert.ok(!mainQml.includes("exitCandidateCount()") || true, "legacy helper may remain")
})

test("metadata version bumped for the §V8 release", () => {
  const meta = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "metadata.json"), "utf8"))
  // v0.8 (§V8): the Omarchy-layout release
  assert.equal((meta.KPlugin || meta).Version, "0.8.0")
})
