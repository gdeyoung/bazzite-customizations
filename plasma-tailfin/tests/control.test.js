// Control-layer tests for plasma-tailfin v0.2 (UX-SPEC-CONTROL.md §T-7).
// Pure logic — no process is ever executed, no real tailscale binary is
// anywhere in scope. Clocks and env are injected.
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const crypto = require("node:crypto")
const Control = require("../Control.js")

// ---- §T-2: closed allowlist ----------------------------------------------

test("op set is exactly the six allowlisted ops", () => {
  assert.deepEqual(Control.ops(),
    ["up", "down", "exit-set", "exit-clear", "probe", "pref-set"])
})

test("argv is byte-exact per the §T-2/V8-2 table", () => {
  assert.deepEqual(Control.argv("up"), ["tailscale", "up"])
  assert.deepEqual(Control.argv("down"), ["tailscale", "down"])
  assert.deepEqual(Control.argv("exit-set", "tower.horse-frog.ts.net"),
    ["tailscale", "set", "--exit-node=tower.horse-frog.ts.net"])
  assert.deepEqual(Control.argv("exit-clear"), ["tailscale", "set", "--exit-node="])
  assert.deepEqual(Control.argv("probe"), ["tailscale", "debug", "prefs"])
  assert.deepEqual(Control.argv("pref-set", "shields-up:false"),
    ["tailscale", "set", "--shields-up=false"])
})

test("unknown ops yield null — no free-form argv path", () => {
  assert.equal(Control.argv("rm"), null)
  assert.equal(Control.argv(""), null)
  assert.equal(Control.argv("up; rm -rf /"), null)
  assert.equal(Control.argv("exit-set; reboot"), null)
  assert.equal(Control.argv("pref-set", "make-me-operator:true"), null)
})

test("no op carries flags beyond the table shapes", () => {
  for (const op of Control.ops()) {
    const target = op === "pref-set" ? "accept-routes:true" : "x"
    const a = Control.argv(op, target).join(" ")
    assert.match(
      a,
      /^tailscale (up|down|debug prefs|set --exit-node=(x)?|set --accept-routes=true)$/,
      "unexpected shape for " + op + ": " + a
    )
  }
})

test("target is ignored for every op except exit-set/pref-set", () => {
  for (const op of ["up", "down", "exit-clear", "probe"]) {
    assert.deepEqual(Control.argv(op, "--evil"), Control.argv(op))
  }
})

test("TS_BIN substitutes the binary for tests/harness", () => {
  assert.deepEqual(Control.argv("up", null, { TS_BIN: "/tmp/stub/tailscale" }),
    ["/tmp/stub/tailscale", "up"])
})

// ---- V8-2: clipboard argv (closed charset) --------------------------------

test("clipboardArg: IPs/IPv6/DNS names pass, everything else null", () => {
  assert.deepEqual(Control.clipboardArg("100.71.87.72"), ["wl-copy", "--", "100.71.87.72"])
  assert.deepEqual(Control.clipboardArg("fd7a:115c:a1e0::1"), ["wl-copy", "--", "fd7a:115c:a1e0::1"])
  assert.deepEqual(Control.clipboardArg("gdtower.horse-frog.ts.net"),
    ["wl-copy", "--", "gdtower.horse-frog.ts.net"])
  assert.equal(Control.clipboardArg(""), null)
  assert.equal(Control.clipboardArg(null), null)
  assert.equal(Control.clipboardArg("a; rm -rf /"), null)
  assert.equal(Control.clipboardArg("back`cmd`tick"), null)
  assert.equal(Control.clipboardArg("with spaces"), null)
  assert.equal(Control.clipboardArg("A".repeat(256)), null)  // CC build-gate: length cap
  assert.deepEqual(Control.clipboardArg("A".repeat(255)), ["wl-copy", "--", "A".repeat(255)])
  assert.equal(Control.clipboardArg("quote'inject"), null)
})

test("clipboardArg: leading-dash strings pass charset and ride behind --", () => {
  // "-x" matches the charset; the "--" separator keeps wl-copy from
  // reading it as a flag. (CC build-gate hardening test.)
  assert.deepEqual(Control.clipboardArg("-x"), ["wl-copy", "--", "-x"])
  assert.deepEqual(Control.clipboardArg("--"), ["wl-copy", "--", "--"])
})

// ---- §T-1: operator-gate probe parser -------------------------------------

test("probe parser: operator match → enabled", () => {
  const prefs = JSON.stringify({ OperatorUser: "gdeyoung", RouteAll: false })
  const r = Control.parseOperatorPrefs(prefs, 0, "gdeyoung")
  assert.equal(r.state, "enabled")
  assert.equal(r.hint, "")
  assert.equal(r.operator, "gdeyoung")
})

test("probe parser: someone else is operator → disabled with hint", () => {
  const prefs = JSON.stringify({ OperatorUser: "root" })
  const r = Control.parseOperatorPrefs(prefs, 0, "gdeyoung")
  assert.equal(r.state, "disabled")
  assert.match(r.hint, /set --operator/)
})

test("probe parser: OperatorUser absent → disabled with hint", () => {
  const r = Control.parseOperatorPrefs(JSON.stringify({ RouteAll: false }), 0, "gdeyoung")
  assert.equal(r.state, "disabled")
  assert.match(r.hint, /set --operator/)
})

test("probe parser: non-zero exit / empty / unparseable → unavailable", () => {
  assert.equal(Control.parseOperatorPrefs("{}", 1, "gdeyoung").state, "unavailable")
  assert.equal(Control.parseOperatorPrefs("", 0, "gdeyoung").state, "unavailable")
  assert.equal(Control.parseOperatorPrefs("not json at all", 0, "gdeyoung").state, "unavailable")
})

// ---- §T-4: exit-node target resolution + candidacy -------------------------

test("exitTarget strips the trailing dot from DNSName", () => {
  assert.equal(Control.exitTarget({ DNSName: "tower.horse-frog.ts.net." }), "tower.horse-frog.ts.net")
})

test("exitTarget falls back to first TailscaleIP when DNS is empty", () => {
  assert.equal(Control.exitTarget({ DNSName: "", TailscaleIPs: ["100.1.2.3", "fd7a::1"] }), "100.1.2.3")
})

test("exitTarget is empty for a peer with neither", () => {
  assert.equal(Control.exitTarget({}), "")
  assert.equal(Control.exitTarget(null), "")
})

test("candidate: online + 0.0.0.0/0 advertised", () => {
  assert.equal(Control.isExitCandidate({ Online: true }, { AllowedIPs: ["100.64.0.1/32", "0.0.0.0/0", "::/0"] }), true)
})

test("non-candidates: offline, subnet-only, ipv6-only, no raw", () => {
  assert.equal(Control.isExitCandidate({ Online: false }, { AllowedIPs: ["0.0.0.0/0"] }), false)
  assert.equal(Control.isExitCandidate({ Online: true }, { AllowedIPs: ["192.168.1.0/24"] }), false)
  assert.equal(Control.isExitCandidate({ Online: true }, { AllowedIPs: ["::/0"] }), false)
  assert.equal(Control.isExitCandidate({ Online: true }, null), false)
})

// ---- §T-3: confirm machine --------------------------------------------------

test("arm → dead-zone re-click ignored → post-zone click fires", () => {
  const c = new Control.Confirm()
  assert.equal(c.click(0), "arm")
  assert.equal(c.click(300), "ignored") // inside 500 ms dead-zone
  assert.ok(c.armed())
  assert.equal(c.click(700), "fire") // past dead-zone, inside 4 s window
  assert.ok(!c.armed())
})

test("double-click at 0/100/200/400 ms never fires", () => {
  const c = new Control.Confirm()
  assert.equal(c.click(0), "arm")
  assert.equal(c.click(100), "ignored")
  assert.equal(c.click(200), "ignored")
  assert.equal(c.click(400), "ignored")
  assert.ok(c.armed(), "still armed after machine-gun clicks")
})

test("4 s window: fire at the edge, fresh arm past it", () => {
  const c = new Control.Confirm()
  assert.equal(c.click(0), "arm")
  assert.equal(c.click(4000), "fire") // <= window fires
  assert.equal(c.click(4600), "arm")  // fresh cycle after a fire
  assert.equal(c.click(4601 + 4000), "arm") // past window = new arm, not fire
  assert.ok(c.armed())
})

test("expired() + disarm() cover timer and popup-close paths", () => {
  const c = new Control.Confirm()
  c.click(0)
  assert.equal(c.expired(4500), true)
  assert.equal(c.expired(3000), false)
  c.disarm()
  assert.ok(!c.armed())
  assert.equal(c.expired(4500), false)
})

// ---- §T-5: op-run state -----------------------------------------------------

test("exclusivity: second begin while in-flight is refused", () => {
  const o = new Control.Ops()
  assert.equal(o.begin("down"), "accepted")
  assert.equal(o.begin("exit-set", "tower"), "refused")
  assert.ok(o.busy())
})

test("finish ok clears state; finish failed records errorText", () => {
  const o = new Control.Ops()
  o.begin("down")
  assert.equal(o.finish("down", 0, "", ""), "ok")
  assert.equal(o.lastError, "")
  assert.ok(!o.busy())

  o.begin("exit-set", "tower")
  assert.equal(o.finish("exit-set", 1, "", "bad exit node"), "failed")
  assert.equal(o.lastError, "op failed: bad exit node")
  assert.equal(o.target, "", "switching target cleared on failure")
})

test("switching target is set for exit-set only", () => {
  const o = new Control.Ops()
  o.begin("exit-set", "tower")
  assert.equal(o.target, "tower")
  o.finish("exit-set", 0, "", "")
  o.begin("down")
  assert.equal(o.target, "")
  o.finish("down", 0, "", "")
})

test("timeout surfaces 'op timed out', clears target, re-enables", () => {
  const o = new Control.Ops()
  o.begin("exit-set", "tower")
  assert.equal(o.timeout("exit-set"), "timedout")
  assert.equal(o.lastError, "op timed out")
  assert.equal(o.target, "")
  assert.ok(!o.busy())
  assert.equal(o.begin("down"), "accepted", "controls re-enabled after timeout")
})

test("stale finish/timeout for a different op are ignored", () => {
  const o = new Control.Ops()
  o.begin("down")
  assert.equal(o.finish("up", 0, "", ""), "stale")
  assert.equal(o.timeout("up"), "stale")
  assert.ok(o.busy(), "still in flight")
})

test("watchdog timeouts: up 30 s, everything else 15 s", () => {
  const o = new Control.Ops()
  assert.equal(o.timeoutFor("up"), 30000)
  assert.equal(o.timeoutFor("down"), 15000)
  assert.equal(o.timeoutFor("exit-set"), 15000)
  assert.equal(o.timeoutFor("exit-clear"), 15000)
})

// ---- §T-5: error formatting -------------------------------------------------

test("up failing with an auth URL → actionable login message", () => {
  assert.equal(
    Control.errorText("up", 1, "To authenticate, visit:\n\n\thttps://login.tailscale.com/a/abc123", ""),
    "login required — run: tailscale login"
  )
  assert.equal(
    Control.errorText("up", 1, "", "failed to reauth: login.tailscale.com/a/x"),
    "login required — run: tailscale login"
  )
})

test("stderr first line only; empty stderr falls back to exit code", () => {
  assert.equal(Control.errorText("exit-set", 1, "", "line one\nline two"), "op failed: line one")
  assert.equal(Control.errorText("down", 2, "", ""), "op failed: exit 2")
})

// ---- mirror drift guard (same pattern as Model.js) ---------------------------

test("contents/ui/Control.js and root Control.js never drift", () => {
  const sha = (p) => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")
  assert.equal(
    sha("contents/ui/Control.js"),
    sha("Control.js"),
    "root mirror drifted from the QML copy — re-copy contents/ui/Control.js"
  )
})
