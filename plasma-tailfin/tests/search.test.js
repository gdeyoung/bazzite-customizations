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
    TailscaleIPs: o.ips || ["100.64.10.9"],
    Online: o.online === undefined ? true : o.online,
  }
}

function names(list) {
  return list.map((p) => p.HostName)
}

test("empty query is identity passthrough (sections mode)", () => {
  const peers = [mk("mytower"), mk("laketower")]
  assert.deepEqual(names(Model.searchPeers(peers, "")), ["mytower", "laketower"])
  assert.deepEqual(names(Model.searchPeers(peers, "   ")), ["mytower", "laketower"])
})

test("substring match; equal rank tiebreaks on HostName asc (tow -> laketower then mytower)", () => {
  const peers = [mk("mytower"), mk("laketower"), mk("mediabox")]
  assert.deepEqual(names(Model.searchPeers(peers, "tow")), ["laketower", "mytower"])
})

test("in-order subsequence matches (mtw -> mytower)", () => {
  const peers = [mk("mytower"), mk("laketower"), mk("mediabox")]
  assert.deepEqual(names(Model.searchPeers(peers, "mtw")), ["mytower"])
})

test("multi-token all-must-match (spark node -> both spark nodes; spark zzz -> none)", () => {
  const peers = [mk("spark-node10"), mk("spark-node13"), mk("spark2"), mk("mytower")]
  assert.deepEqual(names(Model.searchPeers(peers, "spark node")), ["spark-node10", "spark-node13"])
  assert.deepEqual(Model.searchPeers(peers, "spark zzz"), [])
})

test("token may match a DIFFERENT field per token (ip + name mix)", () => {
  const peers = [mk("mytower", { ips: ["100.64.7.71"] }), mk("mediabox", { ips: ["100.64.8.81"] })]
  // "my" hits the name, "71" hits the IP string
  assert.deepEqual(names(Model.searchPeers(peers, "my 71")), ["mytower"])
})

test("field weights: DisplayName match outranks a DNS match", () => {
  const peers = [
    mk("nodeA", { display: "tower of power", dns: "plain.ts.net.", ips: ["100.64.28.99"] }),
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
  const peers = [mk("tower"), mk("oldphone", { online: false })]
  assert.deepEqual(names(Model.searchPeers(peers, "phone")), ["oldphone"])
})

test("DNS name field is searchable without the .ts.net suffix", () => {
  const peers = [mk("host-q7", { dns: "querybox.example.ts.net." })]
  assert.deepEqual(names(Model.searchPeers(peers, "querybox")), ["host-q7"])
})

test("no match anywhere returns [] (NO MATCHING PEERS state)", () => {
  const peers = [mk("mytower"), mk("laketower")]
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
