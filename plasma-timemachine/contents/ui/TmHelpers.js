// TmHelpers.js — pure formatting / grouping helpers for the TimeMachine
// plasmoid. Ported from omarchy-timemachine DetailPopup.qml (v0.5.4); no
// Quickshell or Plasma dependencies — plain QML-importable JavaScript.
// (Not a .pragma library: fmtTs/dayLabelOf need Qt.locale() from the
// importing QML context.)

var STALE_DEFAULT = 26
var FAIL_DEFAULT = 72

function fmtAge(h) {
  if (h === null || h === undefined) return "--"
  if (h < 1) return Math.max(1, Math.round(h * 60)) + "m"
  if (h < 48) return Math.round(h) + "h"
  return Math.round(h / 24) + "d"
}

function fmtTs(iso) {
  if (!iso) return "—"
  var d = new Date(iso)
  return isNaN(d.getTime()) ? iso
    : d.toLocaleDateString(Qt.locale(), "MM/dd") + " " + d.toLocaleTimeString(Qt.locale(), "HH:mm")
}

function fmtAgo(t) {
  if (!t) return "—"
  var s = Math.max(0, Math.floor(Date.now() / 1000 - t))
  if (s < 3600) return Math.max(1, Math.round(s / 60)) + "m ago"
  if (s < 86400) return Math.round(s / 3600) + "h ago"
  return Math.round(s / 86400) + "d ago"
}

// 20261019-0924 → "2026-10-19 09:24" (the id IS the creation stamp).
// Snapshot rows carry INTEGER snapper ids and still evaluate this binding —
// coerce, then shape-check.
function fmtIdDate(id) {
  var s = (id === null || id === undefined) ? "" : String(id)
  if (s.length < 13) return s || "—"
  return s.substring(0, 4) + "-" + s.substring(4, 6) + "-" + s.substring(6, 8)
    + " " + s.substring(9, 11) + ":" + s.substring(11, 13)
}

// snapper snapshot path: <subvol>/.snapshots/<id>/snapshot
function localSnapPath(subvol, id) {
  var sub = subvol === "/" ? "" : subvol
  return sub + "/.snapshots/" + id + "/snapshot"
}

function fmtSize(mb) {
  if (mb === null || mb === undefined) return "—"
  if (mb < 1024) return Math.round(mb) + " MB"
  return (mb / 1024).toFixed(1) + " GB"
}

function bucketOf(t) {
  var days = t ? (Date.now() / 1000 - t) / 86400 : 999
  if (days <= 14) return "daily"
  if (days <= 56) return "weekly"
  return "monthly"
}

function dayKeyFromDate(d) {
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2)
    + "-" + ("0" + d.getDate()).slice(-2)
}

function todayKey() { return dayKeyFromDate(new Date()) }

function yesterdayKey() {
  var d = new Date()
  d.setDate(d.getDate() - 1)
  return dayKeyFromDate(d)
}

function dayKeyOf(row) {
  if (row && typeof row.t === "number" && row.t > 0)
    return dayKeyFromDate(new Date(row.t * 1000))
  if (row && typeof row.id === "string" && row.id.length === 13 && row.id.charAt(8) === "-")
    return row.id.substring(0, 4) + "-" + row.id.substring(4, 6) + "-" + row.id.substring(6, 8)
  if (row && typeof row.iso === "string" && row.iso.length >= 10)
    return row.iso.substring(0, 10)
  return "—"
}

function dayLabelOf(key) {
  if (key === todayKey()) return "Today"
  if (key === yesterdayKey()) return "Yesterday"
  var p = key.split("-")
  if (p.length !== 3) return key
  var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  return d.toLocaleDateString(Qt.locale(), "dddd")
}

function daySubOf(key) {
  var p = key.split("-")
  if (p.length !== 3) return ""
  var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  return d.toLocaleDateString(Qt.locale(), "ddd MM/dd")
}

// group rows [{t,id,iso}, …] into newest-day-first day buckets
function dayGroups(rows, isBackup) {
  var groups = [], index = {}
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var k = dayKeyOf(r)
    if (!index[k]) {
      index[k] = { key: k, rows: [] }
      groups.push(index[k])
    }
    index[k].rows.push(r)
  }
  groups.sort(function(a, b) { return a.key < b.key ? 1 : -1 })
  for (var j = 0; j < groups.length; j++) {
    var g = groups[j]
    g.label = dayLabelOf(g.key)
    g.sub = daySubOf(g.key)
    g.noun = g.rows.length === 1 ? (isBackup ? "backup" : "snapshot")
      : (isBackup ? "backups" : "snapshots")
    if (isBackup) g.bucket = bucketOf(g.rows[0].t)
  }
  return groups
}

function snapTotal(snapper) {
  var n = 0, c = (snapper && snapper.configs) || []
  for (var i = 0; i < c.length; i++) n += (c[i].count || 0)
  return n
}

function snapNewestT(snapper) {
  var best = 0, c = (snapper && snapper.configs) || []
  for (var i = 0; i < c.length; i++) {
    var rows = c[i].rows || []
    if (rows.length && typeof rows[0].t === "number" && rows[0].t > best)
      best = rows[0].t
  }
  return best
}

function snapFresh(snapper) {
  var newest = snapNewestT(snapper)
  return newest && (Date.now() / 1000 - newest) <= 7200
}

// single-quote shell escaping for commands routed through the executable
// dataengine (KProcess runs the string via a shell)
function shq(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}
