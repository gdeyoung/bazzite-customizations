// Pins for the plasma-timemachine port (KDE Plasma 6). Adapted from the
// omarchy-timemachine tests/pin.test.mjs @ 519df33 — the engine-contract,
// source-pin and scratch-fixture tests port as-is (the engine is byte
// identical); the Quickshell QML/IPC pins are replaced by Plasma-port pins
// (PlasmoidItem structure, plasma5support import law, tab set, no private
// endpoints). Run: node --test tests/
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync, existsSync, mkdirSync, rmSync, writeFileSync,
  chmodSync, readdirSync, readlinkSync, symlinkSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { tmpdir } from "node:os"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const read = (f) => readFileSync(join(root, f), "utf8")
const bin = (f) => join(root, "contents/scripts/bin", f)
const scr = (f) => join(root, "contents/scripts", f)

const main = read("contents/ui/main.qml")
const details = read("contents/ui/Details.qml")

// ---- Plasma port structure pins -------------------------------------------

test("plasma port: PlasmoidItem root with compact/full direct children", () => {
  assert.match(main, /PlasmoidItem \{/)
  assert.match(main, /compactRepresentation:/)
  assert.match(main, /fullRepresentation: Details \{/)
})

test("plasma port: plasma5support imported unaliased + versioned, formal onNewData params", () => {
  assert.match(main, /import org\.kde\.plasma\.plasma5support 2\.0/)
  assert.ok(!/plasma5support 2\.0 as /.test(main), "no alias on plasma5support")
  assert.match(main, /onNewData: \(sourceName, data\) =>/)
  assert.ok(!main.includes("in connectedSources"), "never gate on 'in connectedSources'")
})

test("plasma port: Qt.resolvedUrl (not the Quickshell typo), scripts under ../scripts", () => {
  assert.match(main, /Qt\.resolvedUrl\("\.\.\/scripts\//)
  assert.ok(!main.includes("Qt.resolveUrl"))
})

test("plasma port: five-tab popup, StackLayout height bound to the visible page", () => {
  for (const t of ["StatusTab", "SnapshotsTab", "HealthTab", "RecoveryTab", "SettingsTab"]) {
    assert.match(details, new RegExp(t + " \\{ tm:"), `${t} instantiated`)
    assert.ok(existsSync(join(root, "contents/ui", t + ".qml")), `${t}.qml exists`)
  }
  assert.match(details, /height: children\[currentTab\]\.implicitHeight/,
    "tallest-child trap overridden")
})

test("plasma port: engine actions delegate through bundled scripts, never inline logic", () => {
  assert.match(main, /systemctl", "--user|systemctl --user/)
  assert.match(main, /tm-restore\.sh/)
  assert.match(main, /"--drill"/)
  assert.match(main, /function backupNow\(\)/)
  assert.match(main, /function runDrill\(\)/)
  assert.match(main, /tm-backups\.sh/)
  assert.match(main, /tm-snapper\.sh/)
})

test("plasma port: conf path is a parameter (no LAN specifics anywhere)", () => {
  assert.match(main, /configuration\.confPath/)
  assert.match(read("contents/config/main.xml"), /confPath/)
  const files = ["contents/ui/main.qml", "contents/ui/Details.qml",
    "contents/ui/SizeBars.qml", "install.sh", "README.md",
    "contents/config/config.qml", "contents/config/main.xml"]
  for (const f of files) {
    const t = read(f)
    assert.ok(!t.includes("192.168."), `${f} free of LAN endpoints`)
    assert.ok(!t.includes("watertower"), `${f} free of fleet hostnames`)
  }
})

test("plasma port: engine ported verbatim (sha256 vs recorded upstream pin)", async () => {
  // upstream omarchy-timemachine @ 519df33 (2026-10-19), engine files copied
  // byte-identical; only this checksum ledger is new.
  const pin = JSON.parse(read("tests/engine-sha256.json"))
  const { createHash } = await import("node:crypto")
  for (const [rel, want] of Object.entries(pin)) {
    const got = createHash("sha256").update(readFileSync(join(root, rel))).digest("hex")
    assert.equal(got, want, `${rel} byte-identical to upstream 519df33`)
  }
})

// ---- engine scripts parse + live JSON contracts (read-only) -----------------

test("engine scripts parse (bash -n)", () => {
  for (const f of ["tm-common.sh", "tm-conf.sh", "tm-backup.sh", "tm-restore.sh",
                   "tm-health.sh"]) {
    execFileSync("bash", ["-n", bin(f)], { timeout: 10000 })
  }
  for (const f of ["tm-probe.sh", "tm-backups.sh", "tm-snapper.sh", "tm-snapshots.sh"]) {
    execFileSync("bash", ["-n", scr(f)], { timeout: 10000 })
  }
})

test("probe script emits a parseable JSON status line (live contract)", () => {
  const out = execFileSync(scr("tm-probe.sh"), ["26", "72"], { timeout: 15000 }).toString()
  const j = JSON.parse(out.trim())
  assert.equal(j.engine, "ok")
  assert.ok(["ok", "stale", "fail", "never", "running"].includes(j.state))
  assert.ok(Array.isArray(j.history))
  assert.ok(typeof j.label === "string" && typeof j.repo === "string")
  assert.ok(j.thresholds && j.thresholds.stale_h === 26 && j.thresholds.fail_h === 72)
  assert.ok("drift" in j && typeof j.drift.clean === "boolean")
  if ("verify" in j) assert.ok(j.verify.ts && j.verify.pass + j.verify.fail === j.verify.files)
  if ("health" in j) assert.ok("ok" in j.health && "ts" in j.health)
  assert.ok(!out.includes("192.168"), "no LAN endpoints leak")
  assert.ok(!out.includes("sftp:"), "no repo URL leaks")
})

test("conf bridge json answers on an unconfigured host (read-only)", () => {
  const j = JSON.parse(execFileSync(bin("tm-conf.sh"), ["json"], { timeout: 15000 }).toString())
  assert.equal(j.configured, false)
  assert.equal(j.host, "")
  assert.ok(typeof j.schedule === "string")
})

test("backups bridge emits a parseable status line (never-configured host)", () => {
  const out = execFileSync(scr("tm-backups.sh"), { timeout: 60000 }).toString()
  const j = JSON.parse(out.trim())
  assert.ok(["ok", "empty", "never", "unreachable", "error"].includes(j.status))
})

test("snapper bridge emits a parseable status line (no snapper here)", () => {
  const out = execFileSync(scr("tm-snapper.sh"), { timeout: 30000 }).toString()
  const j = JSON.parse(out.trim())
  assert.ok(["ok", "empty", "denied", "unavailable"].includes(j.status))
})

test("legacy tm-snapshots.sh shim still answers (one-release compat)", () => {
  const out = execFileSync(scr("tm-snapshots.sh"), { timeout: 60000 })
  assert.ok(JSON.parse(out.toString().trim()).status, "shim execs tm-backups.sh")
})

// ---- engine source pins (upstream hardening, must survive the port) ---------

test("v0.5 terminology: engine addresses the remote tree as backups/ only", () => {
  for (const f of ["bin/tm-backup.sh", "bin/tm-restore.sh", "bin/tm-health.sh",
                   "bin/tm-conf.sh", "tm-backups.sh", "bin/timemachine.conf.example"]) {
    const path = f.startsWith("bin/") ? bin(f.slice(4)) : scr(f)
    const t = readFileSync(path, "utf8")
    assert.ok(!t.includes("TM_DEST/snapshots"), `${f} free of snapshots/ paths`)
  }
  const rb = readFileSync(bin("tm-restore.sh"), "utf8")
  assert.match(rb, /--backup/)
  assert.match(rb, /--snapshot/)
})

test("v0.5.3 engine hardening: rsync passes --no-D right after -aH", () => {
  const t = readFileSync(bin("tm-backup.sh"), "utf8")
  assert.ok(t.includes("rsync -aH --no-D --stats"), "--no-D follows -aH")
  assert.ok(t.indexOf("-aH --no-D") < t.indexOf("--stats"))
})

test("v0.5.3 unit template: TimeoutStartSec=6h, never 2h", () => {
  const t = readFileSync(bin("tm-conf.sh"), "utf8")
  assert.ok(t.includes("TimeoutStartSec=6h"))
  assert.ok(!t.includes("TimeoutStartSec=2h"))
})

test("v0.4.1/v0.5.2 source pin: rc discipline, staging, publish-by-rename", () => {
  const s = readFileSync(bin("tm-backup.sh"), "utf8")
  assert.match(s, /\[ "\$RC" != 0 \] && \[ "\$RC" != 24 \]/)
  assert.ok(!s.includes('"$RC" != 23'), "rc 23 must never be tolerated")
  assert.match(s, /rm -rf '\$TM_DEST\/backups\/\$STG'/)
  assert.ok(!s.includes("rm -rf '$TM_DEST/backups/$SNAP'"),
    "failure path must never remove the published name")
  assert.match(s, /test -e '\$TM_DEST\/backups\/\$SNAP'/)
  assert.match(s, /SKIP: backup \$SNAP already completed and published/)
  assert.match(s, /FATAL: backups\/\$SNAP already exists but latest is/)
  assert.match(s, /STG="\.staging\.\$SNAP\.\$\$"/)
  assert.match(s, /mv -T '\$STG' '\$SNAP'/)
  assert.match(s, /ln -sfn 'backups\/\$SNAP' latest\.tmp/)
  assert.match(s, /-name '\.staging\.\*' -mtime \+1/)
})

// ---- conf bridge round-trip (scratch conf; writes confined to tmpdir) -------

test("conf bridge round-trip + validation (scratch conf)", () => {
  const scratch = `${tmpdir()}/tm-conf-test-${process.pid}`
  mkdirSync(scratch, { recursive: true })
  const env = { ...process.env, TM_CONF_FILE: `${scratch}/timemachine.conf` }
  const run = (args) => execFileSync(bin("tm-conf.sh"), args, { env, timeout: 15000 })
  run(["set", "TM_HOST", "root@192.0.2.99"])
  run(["set", "TM_DEST", "/mnt/pool/tm"])
  run(["set", "TM_SCHEDULE", "10:00,22:30"])
  const j = JSON.parse(run(["json"]).toString())
  assert.equal(j.configured, true)
  assert.equal(j.host, "root@192.0.2.99")
  assert.equal(j.dest, "/mnt/pool/tm")
  assert.equal(j.schedule, "10:00,22:30")
  assert.deepEqual(j.retention, { daily: 14, weekly: 8, monthly: 12 })
  assert.equal(j.timer_installed, false)
  for (const [k, v] of [["TM_SSH_PORT", "abc"], ["TM_SCHEDULE", "9:20"], ["TM_BOGUS", "x"]]) {
    let refused = false
    try { run(["set", k, v]) } catch { refused = true }
    assert.ok(refused, `set ${k}=${v} must be rejected`)
  }
  rmSync(scratch, { recursive: true, force: true })
})

test("unconfigured conf → configured:false; probe reports never", () => {
  const scratch = `${tmpdir()}/tm-empty-${process.pid}`
  mkdirSync(scratch, { recursive: true })
  const env = { ...process.env, TM_CONF_FILE: `${scratch}/nope.conf` }
  const j = JSON.parse(execFileSync(bin("tm-conf.sh"), ["json"], { env, timeout: 15000 }).toString())
  assert.equal(j.configured, false)
  assert.equal(j.host, "")
  const probe = JSON.parse(execFileSync(scr("tm-probe.sh"), [], { env, timeout: 15000 }).toString())
  assert.equal(probe.state, "never")
  assert.equal(probe.configured, false)
  rmSync(scratch, { recursive: true, force: true })
})

// ---- engine behavior fixtures (ssh/rsync STUBS; scratch dirs in tmpdir) -----

function engineFixture(rsyncRc, vanished) {
  const scratch = `${tmpdir()}/tm-rc${rsyncRc}-${process.pid}`
  const home = `${scratch}/home`, dest = `${scratch}/dest`
  const state = `${scratch}/state`, sbin = `${scratch}/bin`
  for (const d of [home, dest, state, sbin]) mkdirSync(d, { recursive: true })
  writeFileSync(`${home}/a.txt`, "fixture\n")
  writeFileSync(`${scratch}/excludes.txt`, "")
  writeFileSync(`${scratch}/timemachine.conf`, [
    "TM_HOST=user@fakehost",
    `TM_DEST=${dest}`,
    `TM_STATE_DIR=${state}`,
    `TM_EXCLUDES=${scratch}/excludes.txt`,
    "TM_VERIFY_DOW=7",
  ].join("\n") + "\n")
  writeFileSync(`${sbin}/ssh`, [
    "#!/usr/bin/env bash",
    "while [ $# -gt 1 ]; do case \"$1\" in -p|-o) shift 2 ;; *) break ;; esac; done",
    "shift  # host",
    "eval \"$*\"",
  ].join("\n") + "\n")
  const stderrLine = vanished ? "rsync stub: simulated vanished-source notice" : ""
  writeFileSync(`${sbin}/rsync`, [
    "#!/usr/bin/env bash",
    "tgt=\"${@: -1}\"; mkdir -p \"${tgt#*:}\"; printf x > \"${tgt#*:}/a.txt\"",
    "printf 'Number of files: 3 (reg: 2)\\nTotal file size: 1,234\\n'",
    `[ -n "${stderrLine}" ] && printf '%s\\n' "${stderrLine}" >&2`,
    `exit ${rsyncRc}`,
  ].join("\n") + "\n")
  for (const f of ["ssh", "rsync"]) chmodSync(`${sbin}/${f}`, 0o755)
  const opts = {
    env: { ...process.env, PATH: `${sbin}:${process.env.PATH}`, HOME: home,
           TM_CONF_FILE: `${scratch}/timemachine.conf` },
    timeout: 30000,
  }
  return { scratch, home, dest, state, opts }
}

test("engine: rsync rc 23 discards the partial — no latest, no stamp, no history", () => {
  const t = engineFixture(23)
  let err = null
  try { execFileSync(bin("tm-backup.sh"), t.opts) } catch (e) { err = e }
  assert.ok(err, "rc 23 run must fail")
  assert.equal(err.status, 23)
  assert.match(String(err.stdout), /FATAL: rsync exited 23/)
  assert.match(String(err.stdout), /discarded/)
  assert.ok(!existsSync(`${t.dest}/latest`), "latest must not advance")
  assert.deepEqual(readdirSync(`${t.dest}/backups`), [], "partial backup removed")
  assert.ok(!existsSync(`${t.state}/last-backup.json`), "no success stamp")
  assert.ok(!existsSync(`${t.state}/history.jsonl`), "no healthy history row")
  rmSync(t.scratch, { recursive: true, force: true })
})

test("engine: rsync rc 24 (vanished sources) tolerated — snapshot completes", () => {
  const t = engineFixture(24, true)
  const out = execFileSync(bin("tm-backup.sh"), t.opts).toString()
  assert.match(out, /WARN: rsync: rsync stub: simulated vanished-source notice/)
  assert.match(out, /OK — backup /)
  assert.ok(existsSync(`${t.dest}/latest`), "latest advanced")
  assert.ok(existsSync(`${t.state}/last-backup.json`), "success stamp written")
  rmSync(t.scratch, { recursive: true, force: true })
})

test("engine: same-minute rerun refuses the published destination (SKIP, tree untouched)", () => {
  for (let attempt = 0; attempt < 3; attempt++) {
    const t = engineFixture(23)   // rsync WOULD fail rc 23 — it must never run
    const now = new Date()
    const p2 = (n) => String(n).padStart(2, "0")
    const snap = `${now.getFullYear()}${p2(now.getMonth() + 1)}${p2(now.getDate())}`
      + `-${p2(now.getHours())}${p2(now.getMinutes())}`
    mkdirSync(`${t.dest}/backups/${snap}`, { recursive: true })
    writeFileSync(`${t.dest}/backups/${snap}/completed.txt`, "done\n")
    symlinkSync(`backups/${snap}`, `${t.dest}/latest`)
    let out = ""
    try { out = execFileSync(bin("tm-backup.sh"), t.opts).toString() }
    catch (e) { out = String(e.stdout || "") + String(e.stderr || "") }
    if (!out.includes(snap)) {   // minute flipped mid-run — clean and retry
      rmSync(t.scratch, { recursive: true, force: true })
      continue
    }
    assert.match(out, new RegExp(`SKIP: backup ${snap} already completed and published`))
    assert.ok(!existsSync(`${t.dest}/backups/${snap}/a.txt`),
      "rsync never wrote into the completed backup")
    assert.equal(readFileSync(`${t.dest}/backups/${snap}/completed.txt`, "utf8"), "done\n",
      "completed backup byte-identical")
    assert.equal(readlinkSync(`${t.dest}/latest`), `backups/${snap}`)
    assert.deepEqual(readdirSync(`${t.dest}/backups`), [snap], "no staging leftovers")
    rmSync(t.scratch, { recursive: true, force: true })
    return
  }
  assert.fail("minute boundary flipped three times — rerun the suite")
})

test("engine: existing non-published dir refused loudly, never written into", () => {
  for (let attempt = 0; attempt < 3; attempt++) {
    const t = engineFixture(23)
    const now = new Date()
    const p2 = (n) => String(n).padStart(2, "0")
    const snap = `${now.getFullYear()}${p2(now.getMonth() + 1)}${p2(now.getDate())}`
      + `-${p2(now.getHours())}${p2(now.getMinutes())}`
    mkdirSync(`${t.dest}/backups/${snap}`, { recursive: true })
    writeFileSync(`${t.dest}/backups/${snap}/orphan.txt`, "partial\n")
    mkdirSync(`${t.dest}/backups/20260101-0000`, { recursive: true })
    symlinkSync(`backups/20260101-0000`, `${t.dest}/latest`)
    let err = null
    try { execFileSync(bin("tm-backup.sh"), t.opts) } catch (e) { err = e }
    const out = String(err ? err.stdout : "")
    if (!out.includes(snap)) {
      rmSync(t.scratch, { recursive: true, force: true })
      continue
    }
    assert.ok(err, "refusal must exit non-zero")
    assert.equal(err.status, 1)
    assert.match(out, new RegExp(`FATAL: backups/${snap} already exists but latest is '20260101-0000'`))
    assert.equal(readFileSync(`${t.dest}/backups/${snap}/orphan.txt`, "utf8"), "partial\n",
      "existing tree untouched")
    rmSync(t.scratch, { recursive: true, force: true })
    return
  }
  assert.fail("minute boundary flipped three times — rerun the suite")
})

test("engine: clean run (rc 0) advances latest + stamps success", () => {
  const t = engineFixture(0)
  const out = execFileSync(bin("tm-backup.sh"), t.opts).toString()
  assert.match(out, /OK — backup /)
  assert.ok(existsSync(`${t.dest}/latest`), "latest advanced")
  assert.ok(existsSync(`${t.state}/last-backup.json`), "success stamp written")
  assert.ok(existsSync(`${t.state}/history.jsonl`), "history row written")
  const snap = readFileSync(`${t.state}/last-backup.json`, "utf8")
  assert.match(snap, /"backup":"\d{8}-\d{4}"/)
  rmSync(t.scratch, { recursive: true, force: true })
})
