// §V-8/§V-11 searchPeers tests — the Trayscale peersearch port.
// Semantics: multi-token ALL-must-match; per token-vs-field prefix(3) >
// substring(2) > in-order subsequence(1); field weights DisplayName 4,
// HostName 3, DNSName 2, IPs 1; score desc, then HostName asc.
// Empty query = identity passthrough (sections mode).
const test = require("node:test")
const assert = require("node:assert")
const Model = require("../contents/ui/Model.js")

function mk(name, opts) {
  const o = opts || {}
  return {
    HostName: name,
    DNSName: o.dns === undefined ? name + ".ts.net." : o.dns,
    DisplayName: o.display === undefined ? name : o.display,
    TailscaleIPs: o.ips || ["100.64.0.9"],
    Online: o.online === undefined ? true : o.online,
  }
}

function names(list) {
  return list.map((p) => p.HostName)
}

test("empty query is identity passthrough (sections mode)", () => {
  const peers = [mk("gdtower"), mk("watertower")]
  assert.deepEqual(names(Model.searchPeers(peers, "")), ["gdtower", "watertower"])
  assert.deepEqual(names(Model.searchPeers(peers, "   ")), ["gdtower", "watertower"])
})

test("substring match, prefix outranks substring (tow -> gdtower then watertower)", () => {
  const peers = [mk("watertower"), mk("gdtower"), mk("aibox")]
  assert.deepEqual(names(Model.searchPeers(peers, "tow")), ["gdtower", "watertower"])
})

test("in-order subsequence matches (gdt -> gdtower)", () => {
  const peers = [mk("gdtower"), mk("aibox")]
  assert.deepEqual(names(Model.searchPeers(peers, "gdt")), ["gdtower"])
})

test("multi-token all-must-match (spark gx -> both sparks; spark zzz -> none)", () => {
  const peers = [mk("spark-gx10"), mk("spark-gx13"), mk("spark2"), mk("gdtower")]
  assert.deepEqual(names(Model.searchPeers(peers, "spark gx")), ["spark-gx10", "spark-gx13"])
  assert.deepEqual(Model.searchPeers(peers, "spark zzz"), [])
})

test("token may match a DIFFERENT field per token (ip + name mix)", () => {
  const peers = [mk("gdtower", { ips: ["100.71.87.72"] }), mk("aibox", { ips: ["100.1.1.1"] })]
  // "gd" hits name, "71" hits the IP string
  assert.deepEqual(names(Model.searchPeers(peers, "gd 71")), ["gdtower"])
})

test("field weights: DisplayName match outranks a DNS match", () => {
  const peers = [
    mk("nodeA", { display: "tower of power", dns: "plain.ts.net.", ips: ["100.99.99.99"] }),
    mk("boxIP", { dns: "towerbox.ts.net.", ips: ["100.22.22.22"] }), // name has no "tower"
  ]
  // nodeA: DisplayName substring 2*4=8; boxIP: DNS substring 2*2=4 — both
  // match, but the weighted score puts nodeA first.
  assert.deepEqual(names(Model.searchPeers(peers, "tower")), ["nodeA", "boxIP"])
})

test("equal scores tiebreak on HostName asc", () => {
  const peers = [mk("zeta-spark"), mk("alpha-spark"), mk("mid-spark")]
  assert.deepEqual(names(Model.searchPeers(peers, "spark")), ["alpha-spark", "mid-spark", "zeta-spark"])
})

test("offline peers are searched too (§V-8: muted rows, not excluded)", () => {
  const peers = [mk("gdtower"), mk("oldphone", { online: false })]
  assert.deepEqual(names(Model.searchPeers(peers, "phone")), ["oldphone"])
})

test("DNS name field is searchable without the .ts.net suffix", () => {
  const peers = [mk("host-q7", { dns: "querybox.example.ts.net." })]
  assert.deepEqual(names(Model.searchPeers(peers, "querybox")), ["host-q7"])
})

test("no match anywhere returns [] (NO MATCHING PEERS state)", () => {
  const peers = [mk("gdtower"), mk("watertower")]
  assert.deepEqual(Model.searchPeers(peers, "zzz q"), [])
})

test("missing fields do not throw (empty DNSName / no IPs)", () => {
  const bare = [{ HostName: "bare", DisplayName: "bare" }]
  assert.deepEqual(names(Model.searchPeers(bare, "bare")), ["bare"])
  assert.deepEqual(Model.searchPeers(bare, "x"), [])
})

test("non-array input tolerated (returns [])", () => {
  assert.deepEqual(Model.searchPeers(null, "tow"), [])
  assert.deepEqual(Model.searchPeers(undefined, ""), [])
})
