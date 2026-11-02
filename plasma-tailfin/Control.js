// Control layer for plasma-tailfin v0.2 (UX-SPEC-CONTROL.md r2).
// Pure logic only: argv construction, probe parsing, target resolution,
// the two-step confirm machine, op-run state, and error formatting.
// NOTHING here executes a process — the QML layer drives the executable
// engine; tests drive these functions with injected clocks and a stub
// binary in PATH. HARD RULE (spec invariants): automation never runs
// control ops against the real tailscale binary; first real op is the
// user at the desk.

// §T-2 binary resolution — TS_BIN lets tests/harness substitute a stub.
function bin(env) {
  var e = env || {}
  return String(e.TS_BIN || "tailscale")
}

// §T-2 CLOSED ALLOWLIST — the only constructible invocations. Any other
// op name yields null; there is no free-form argv path.
function argv(op, target, env) {
  var b = bin(env)
  if (op === "up") return [b, "up"]
  if (op === "down") return [b, "down"]
  if (op === "exit-set") return [b, "set", "--exit-node=" + String(target || "")]
  if (op === "exit-clear") return [b, "set", "--exit-node="]
  if (op === "probe") return [b, "debug", "prefs"]
  return null
}

// The total op set — tests assert this and nothing else.
function ops() {
  return ["up", "down", "exit-set", "exit-clear", "probe"]
}

// §T-1 operator gate — parse `tailscale debug prefs` stdout.
// states: "enabled" | "disabled" (operator is someone else / absent)
//         | "unavailable" (daemon down, non-zero exit, unparseable)
function parseOperatorPrefs(text, exitCode, user) {
  var unavailable = {
    state: "unavailable",
    hint: "control unavailable — tailscaled not responding",
    operator: ""
  }
  if (exitCode !== 0) return unavailable
  var s = String(text || "")
  if (s === "") return unavailable
  var prefs
  try {
    prefs = JSON.parse(s)
  } catch (e) {
    return unavailable
  }
  var op = String((prefs && prefs.OperatorUser) || "")
  if (op === "" || op === String(user || "")) {
    return op === ""
      ? { state: "disabled",
          hint: "control disabled — run: sudo tailscale set --operator=$USER",
          operator: "" }
      : { state: "enabled", hint: "", operator: op }
  }
  return {
    state: "disabled",
    hint: "control disabled — run: sudo tailscale set --operator=$USER",
    operator: op
  }
}

// §T-4 exit-node target: DNSName sans trailing dot, fallback first IP.
function exitTarget(peer) {
  if (!peer) return ""
  var dns = String(peer.DNSName || "").replace(/\.+$/, "")
  if (dns !== "") return dns
  var ips = (peer && peer.TailscaleIPs) || []
  return ips.length > 0 ? String(ips[0]) : ""
}

// §T-4 candidate: online AND advertises 0.0.0.0/0 (raw peer AllowedIPs —
// the normalized peer does not carry them).
function isExitCandidate(peer, rawPeer) {
  if (!peer || !peer.Online) return false
  var allowed = (rawPeer && rawPeer.AllowedIPs) || []
  for (var i = 0; i < allowed.length; i++) {
    if (String(allowed[i]) === "0.0.0.0/0") return true
  }
  return false
}

// §T-3 two-step inline confirm with an arm dead-zone. Clock injected
// (ms). click() → "arm" (first click), "ignored" (inside the 500 ms
// dead-zone — state stays armed), "fire" (past the dead-zone, inside the
// 4 s window), "arm" again (past the window = a fresh first click).
function Confirm() {
  this.t0 = -1
}
Confirm.prototype.DEADZONE = 500
Confirm.prototype.WINDOW = 4000
Confirm.prototype.armed = function () {
  return this.t0 >= 0
}
Confirm.prototype.click = function (now) {
  if (this.t0 < 0) {
    this.t0 = now
    return "arm"
  }
  var dt = now - this.t0
  if (dt < this.DEADZONE) return "ignored"
  if (dt <= this.WINDOW) {
    this.t0 = -1
    return "fire"
  }
  this.t0 = now
  return "arm"
}
Confirm.prototype.disarm = function () {
  this.t0 = -1
}
Confirm.prototype.expired = function (now) {
  return this.t0 >= 0 && now - this.t0 > this.WINDOW
}

// §T-5 op-run state: exclusivity (no queue), watchdog parameters,
// switching-target, failure row. begin() launches nothing — the caller
// executes argv through the engine and reports back via finish/timeout.
function Ops() {
  this.inFlight = null // op string while running
  this.target = ""     // §T-4 "switching…" row (exit-set only)
  this.lastError = ""  // §T-5 failure row
}
Ops.prototype.TIMEOUTS = { up: 30000 } // up can block on auth/network
Ops.prototype.timeoutFor = function (op) {
  return this.TIMEOUTS[op] || 15000
}
Ops.prototype.begin = function (op, target) {
  if (this.inFlight) return "refused"
  this.inFlight = op
  this.target = op === "exit-set" ? String(target || "") : ""
  this.lastError = ""
  return "accepted"
}
Ops.prototype.finish = function (op, exitCode, stdout, stderr) {
  if (this.inFlight !== op) return "stale"
  this.inFlight = null
  this.target = ""
  if (exitCode !== 0) this.lastError = errorText(op, exitCode, stdout, stderr)
  return exitCode === 0 ? "ok" : "failed"
}
Ops.prototype.timeout = function (op) {
  if (this.inFlight !== op) return "stale"
  this.inFlight = null
  this.target = ""
  this.lastError = "op timed out"
  return "timedout"
}
Ops.prototype.busy = function () {
  return this.inFlight !== null
}

// §T-5 error formatting — the failure row is the only feedback channel,
// so it must carry the actionable message. `up` failing with an auth URL
// is a login problem, not a raw error.
function errorText(op, exitCode, stdout, stderr) {
  if (op === "up") {
    var out = String(stdout || "") + "\n" + String(stderr || "")
    if (/login\.tailscale\.com|(re)?authenticat/i.test(out)) {
      return "login required — run: tailscale login"
    }
  }
  var line = String(stderr || "").split("\n")[0] || ""
  if (line !== "") return "op failed: " + line
  return "op failed: exit " + exitCode
}

module.exports = {
  bin: bin,
  argv: argv,
  ops: ops,
  parseOperatorPrefs: parseOperatorPrefs,
  exitTarget: exitTarget,
  isExitCandidate: isExitCandidate,
  Confirm: Confirm,
  Ops: Ops,
  errorText: errorText
}
