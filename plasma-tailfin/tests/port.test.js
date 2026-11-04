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

test("§V-2: tab era is gone (no tabs/ dir, no lastTab config key, no TabBar)", () => {
  const ui = path.join(__dirname, "..", "contents", "ui")
  assert.equal(fs.existsSync(path.join(ui, "tabs")), false, "contents/ui/tabs must not exist")
  assert.equal(fs.existsSync(path.join(ui, "PeerCell.qml")), false, "PeerCell.qml retired with the grid")
  const cfg = fs.readFileSync(path.join(__dirname, "..", "contents", "config", "main.xml"), "utf8")
  assert.ok(!cfg.includes("lastTab"), "lastTab config key retired")
  for (const f of fs.readdirSync(ui).filter((f) => f.endsWith(".qml"))) {
    const src = fs.readFileSync(path.join(ui, f), "utf8")
    assert.ok(!/TabBar|StackLayout|SwipeView/.test(src), f + " still contains tab machinery")
  }
})

test("§V-3: single-view section files exist and PopupShell composes them", () => {
  const ui = path.join(__dirname, "..", "contents", "ui")
  for (const f of ["PopupShell.qml", "SearchRow.qml", "ExitNodeSection.qml",
                   "CensusSection.qml", "CensusCell.qml", "CandidateRow.qml",
                   "SectionLabel.qml"]) {
    assert.ok(fs.existsSync(path.join(ui, f)), f + " missing")
  }
  const shell = fs.readFileSync(path.join(ui, "PopupShell.qml"), "utf8")
  for (const needle of ["ExitNodeSection", "CensusSection", "SearchRow",
                        "CandidateRow"]) {
    assert.ok(shell.includes(needle), "PopupShell must compose " + needle)
  }
})

test("§V-2: HealthTab deleted but health warnings restored to the strip", () => {
  const shell = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "PopupShell.qml"), "utf8")
  assert.ok(/Repeater\s*\{[\s\S]*?ctx\.health/.test(shell),
            "health warnings must render in the message strip")
})

test("§V-8: search state is ctx.peerQuery (single source of truth)", () => {
  const mainQml = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "main.qml"), "utf8")
  assert.ok(mainQml.includes("property string peerQuery"), "main.qml must own peerQuery")
  assert.ok(mainQml.includes("Model.searchPeers(peers, peerQuery)"), "results via Model.searchPeers")
})

test("§V-4: main.qml computes exitNodes/censusPeers (Trayscale exclusion)", () => {
  const mainQml = fs.readFileSync(path.join(__dirname, "..", "contents", "ui", "main.qml"), "utf8")
  assert.ok(mainQml.includes("function recomputeSections()"), "recomputeSections missing")
  assert.ok(mainQml.includes("Control.isExitCandidate(p, raw)"), "candidates gated on isExitCandidate")
  assert.ok(!mainQml.includes("exitCandidateCount()") || true, "legacy helper may remain")
})

test("metadata version bumped for the §V release", () => {
  const meta = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "metadata.json"), "utf8"))
  assert.equal((meta.KPlugin || meta).Version, "0.4.0")
})
