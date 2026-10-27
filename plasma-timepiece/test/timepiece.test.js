// Run with: node --test test/timepiece.test.js
// Ported from omarchy-timepiece test/timepiece.test.js: the pure-Model tests
// are verbatim (Model.js is ported verbatim); the wiring tests were adapted
// to assert the Plasma 6 port's files instead of the Quickshell ones.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const M = require("../contents/ui/Model.js")

const read = (f) => fs.readFileSync(path.join(__dirname, "..", f), "utf8")
const main = read("contents/ui/main.qml")
const popup = read("contents/ui/PanelPopup.qml")
const zonesComp = read("contents/ui/ZoneClocks.qml")
const config = read("contents/config/config.qml")
const kcfg = read("contents/config/main.xml")
const palette = read("contents/ui/Palette.js")
const zonesSrc = read("contents/ui/zones.js")
const meta = JSON.parse(read("metadata.json"))

// ---- Model.applyShowDate: the date mask (verbatim from the Omarchy suite)

test("default fork format masks to day name + time", () => {
  assert.equal(M.applyShowDate("dddd MMM d h:mm AP", false), "dddd h:mm AP")
})

test("showDate true leaves the format untouched", () => {
  assert.equal(M.applyShowDate("dddd MMM d h:mm AP", true), "dddd MMM d h:mm AP")
  assert.equal(M.applyShowDate("dddd MMM d h:mm AP", null), "dddd MMM d h:mm AP")
})

test("string \"false\" masks too — tolerant reader parity", () => {
  assert.equal(M.applyShowDate("dddd MMM d h:mm AP", "false"), "dddd h:mm AP")
})

test("every preset ring format masks to something sane", () => {
  const cases = {
    "dddd HH:mm": "dddd HH:mm",            // no date to hide
    "dddd h:mm AP": "dddd h:mm AP",
    "HH:mm": "HH:mm",
    "h:mm AP": "h:mm AP",
    "ddd d MMM HH:mm": "ddd HH:mm",
    "ddd d MMM h:mm AP": "ddd h:mm AP",
    "yyyy-MM-dd HH:mm": "HH:mm",           // one word, dropped whole
    "d MMMM 'W'ww yyyy": "d MMMM 'W'ww yyyy" // nothing but date: unchanged
  }
  for (const format in cases)
    assert.equal(M.applyShowDate(format, false), cases[format], format)
})

test("vertical formats keep their all-date lines rather than going empty", () => {
  const vertical = "dd\nMMM\n'W'ww\n''yy"
  assert.equal(M.applyShowDate(vertical, false), vertical)
})

test("mixed vertical line masks; time-only line untouched", () => {
  assert.equal(M.applyShowDate("ddd d\nHH:mm", false), "ddd\nHH:mm")
})

test("masking is idempotent", () => {
  const once = M.applyShowDate("dddd MMM d h:mm AP", false)
  assert.equal(M.applyShowDate(once, false), once)
})

// ---- World clock parsing and zone labels (verbatim)

test("parseWorldClocks parses label:zone pairs, comma separated", () => {
  assert.deepEqual(M.parseWorldClocks("ET:America/New_York, PT:America/Los_Angeles"), [
    { label: "ET", zone: "America/New_York" },
    { label: "PT", zone: "America/Los_Angeles" }
  ])
})

test("parseWorldClocks keeps structurally plausible zones, drops garbage, caps at five", () => {
  assert.deepEqual(M.parseWorldClocks("ET:Not/AZone,PT:America/Los_Angeles"), [
    { label: "ET", zone: "Not/AZone" },
    { label: "PT", zone: "America/Los_Angeles" }
  ])
  assert.deepEqual(M.parseWorldClocks("ET:noslashzone,PT:America/Los_Angeles"), [
    { label: "PT", zone: "America/Los_Angeles" }
  ])
  assert.equal(M.parseWorldClocks("").length, 0)
  assert.equal(M.parseWorldClocks(null).length, 0)
  assert.equal(M.parseWorldClocks("A:UTC,B:UTC,C:UTC,D:UTC,E:UTC,F:UTC").length, 5)
  assert.equal(M.parseWorldClocks("nolabel:America/New_York").length, 1)
  assert.equal(M.parseWorldClocks("thislabeliswaytoolong:America/New_York").length, 0)
})

test("plausibleTimeZone accepts IANA shapes and fixed offsets, rejects junk", () => {
  assert.equal(M.plausibleTimeZone("America/New_York"), true)
  assert.equal(M.plausibleTimeZone("Europe/London"), true)
  assert.equal(M.plausibleTimeZone("Etc/GMT+5"), true)
  assert.equal(M.plausibleTimeZone("UTC"), true)
  assert.equal(M.plausibleTimeZone("Not a zone!"), false)
  assert.equal(M.plausibleTimeZone(""), false)
})

test("zonesToString round-trips through parseWorldClocks", () => {
  const zones = [
    { label: "New York", zone: "America/New_York" },
    { label: "UTC", zone: "UTC" }
  ]
  const str = M.zonesToString(zones)
  assert.equal(str, "New York:America/New_York,UTC:UTC")
  assert.deepEqual(M.parseWorldClocks(str), zones)
  assert.deepEqual(M.parseWorldClocks(M.zonesToString([])), [])
})

test("filterZones: aliases first, city-prefix beats substring, capped, empty-safe", () => {
  const Z = require("../contents/ui/zones.js").TZ_REGIONS
  const et = M.filterZones(Z, "et", 8)
  assert.equal(et[0].zone, "America/New_York") // alias wins
  assert.equal(M.filterZones(Z, "a", 8).length, 8) // capped at the limit
  const london = M.filterZones(Z, "london", 8)
  assert.equal(london.length, 1)
  assert.equal(london[0].zone, "Europe/London")
  const news = M.filterZones(Z, "new", 8)
  assert.equal(news[0].zone, "America/New_York") // prefix beats substring
  assert.ok(news.some(z => z.zone === "America/North_Dakota/New_Salem" && z.subregion === "North Dakota"))
  const utc = M.filterZones(Z, "UTC", 8)
  assert.equal(utc[0].zone, "UTC")
  assert.deepEqual(M.filterZones(Z, "", 8), [])
  assert.deepEqual(M.filterZones(Z, null, 8), [])
  assert.equal(M.filterZones(Z, "zzzzz", 8).length, 0)
})

test("zones.js picker list is real: every entry exists in this tzdata", () => {
  assert.match(zonesSrc, /var TZ_REGIONS =/)
  const data = require("../contents/ui/zones.js").TZ_REGIONS
  let count = 0
  for (const [region, cities] of Object.entries(data)) {
    assert.match(region, /^[A-Za-z]+$/)
    for (const city of cities) {
      if (region === "UTC" && city === "UTC") { count++; continue }
      assert.ok(fs.existsSync(`/usr/share/zoneinfo/${region}/${city}`), `${region}/${city} missing from tzdata`)
      assert.doesNotMatch(city, / /)
      count++
    }
  }
  assert.ok(count >= 40, `picker too thin (${count} zones)`)
})

// ---- Countdown timer math (verbatim)

test("formatCountdown renders mm:ss and clamps at zero", () => {
  assert.equal(M.formatCountdown(0), "00:00")
  assert.equal(M.formatCountdown(-5000), "00:00")
  assert.equal(M.formatCountdown(594000), "09:54")
  assert.equal(M.formatCountdown(3723000), "62:03")
})

test("stepTimerMinutes clamps to 1..600 and tolerates junk", () => {
  assert.equal(M.stepTimerMinutes(10, 5), 15)
  assert.equal(M.stepTimerMinutes(3, -5), 1)
  assert.equal(M.stepTimerMinutes(598, 5), 600)
  assert.equal(M.stepTimerMinutes("10", 5), 15)
})

// ---- Pomodoro phase table (verbatim)

test("pomodoro phase table: 4th focus goes long, breaks return to focus, off is null", () => {
  assert.deepEqual(M.nextPomodoroPhase("focus", 0, 25, 5), { mode: "break", minutes: 5, cyclesDone: 1 })
  assert.deepEqual(M.nextPomodoroPhase("focus", 3, 25, 5), { mode: "longbreak", minutes: 15, cyclesDone: 4 })
  assert.deepEqual(M.nextPomodoroPhase("break", 4, 25, 5), { mode: "focus", minutes: 25, cyclesDone: 4 })
  assert.deepEqual(M.nextPomodoroPhase("longbreak", 7, 30, 10), { mode: "focus", minutes: 30, cyclesDone: 7 })
  assert.equal(M.nextPomodoroPhase("off", 0, 25, 5), null)
  assert.deepEqual(M.nextPomodoroPhase("focus", 0, 999, 0), { mode: "break", minutes: 5, cyclesDone: 1 })
})

test("pomodoro bar suffix is compact and phase-flagged", () => {
  assert.equal(M.pomodoroBarSuffix("focus", 1052000), "F 17:32")
  assert.equal(M.pomodoroBarSuffix("break", 30000), "B 00:30")
  assert.equal(M.pomodoroBarSuffix("longbreak", 900000), "L 15:00")
  assert.equal(M.pomodoroBarSuffix("off", 60000), "")
})

// ---- Calendar math sanity (Model functions the popup binds to)

test("monthGrid is always six weeks of seven days and marks today", () => {
  const weeks = M.monthGrid(2026, 9, 1, "2026-10-26")
  assert.equal(weeks.length, 6)
  let todaySeen = 0
  for (const w of weeks) {
    assert.equal(w.days.length, 7)
    for (const d of w.days) if (d.today) todaySeen++
  }
  assert.equal(todaySeen, 1)
})

test("stepMonth rolls over year boundaries", () => {
  assert.deepEqual(M.stepMonth(2026, 11, 1), { year: 2027, month: 0 })
  assert.deepEqual(M.stepMonth(2027, 0, -1), { year: 2026, month: 11 })
})

// ---- Wiring: the Plasma port (adapted from the Omarchy wiring tests)

test("applet root is a PlasmoidItem with compact and full representations as direct children", () => {
  assert.match(main, /PlasmoidItem \{/)
  assert.match(main, /compactRepresentation: MouseArea \{/)
  assert.match(main, /fullRepresentation: PanelPopup \{/)
})

test("plasma5support is imported unaliased and versioned", () => {
  assert.match(main, /import org\.kde\.plasma\.plasma5support 2\.0/)
  assert.doesNotMatch(main, /plasma5support 2\.0 as /)
  assert.match(zonesComp, /import org\.kde\.plasma\.plasma5support 2\.0/)
})

test("chip defaults to the date-inclusive format and masks via Model", () => {
  assert.match(kcfg, /<default>dddd, \[UM\] \[OD\] h:mm AP<\/default>/)
  assert.match(main, /Model\.applyShowDate\(configuredFormat, showDate\)/)
})

test("custom tokens: [UM] uppercase month + [OD] ordinal day resolve around Qt", () => {
  assert.match(main, /split\("\[UM\]"\)\.join\("@@"\)/)
  assert.match(main, /split\("\[OD\]"\)\.join\("##"\)/)
  assert.match(main, /Model\.ordinalDay\(d\.getDate\(\)\)/)
  assert.equal(M.ordinalDay(1), "1st")
  assert.equal(M.ordinalDay(11), "11th")
  assert.equal(M.ordinalDay(21), "21st")
  assert.equal(M.ordinalDay(27), "27th")
})

test("applet reads showDate tolerating the string form", () => {
  assert.match(main, /v === false \|\| v === "false"/)
})

test("applet owns the timer actions and writes exact keys through configuration", () => {
  assert.match(main, /function timerStep\(delta\)/)
  assert.match(main, /function timerToggle\(\)/)
  assert.match(main, /function timerReset\(\)/)
  assert.match(main, /timerRunning: true, timerEndsAt: Date\.now\(\) \+ remaining, timerDoneAt: 0/)
  assert.match(main, /function pomodoroStart\(\)/)
  assert.match(main, /timerRunning: false, timerRemainingMs: 0, timerDoneAt: 0,/)
})

test("fires live in the always-mounted applet, not the popup", () => {
  assert.match(main, /function checkFires\(nowMs\)/)
  assert.match(main, /nowMs >= timerEndsAt/)
  assert.match(main, /nowMs - timerDoneAt >= 120000/)
  assert.match(main, /save\(\{ timerDoneAt: 0 \}\)/)
  assert.doesNotMatch(popup, /function checkFires/) // popup can't fire — it may not exist
})

test("timer state persists via Plasmoid.configuration so a shell restart resumes", () => {
  assert.match(main, /Plasmoid\.configuration\[k\] = patch\[k\]/)
  for (const key of ["timerRunning", "timerEndsAt", "timerRemainingMs", "timerDoneAt",
                     "pomodoroMode", "pomodoroEndsAt", "pomodoroCyclesDone"])
    assert.ok(kcfg.includes(`name="${key}"`), `${key} missing from main.xml`)
})

test("pomodoro modes are exclusive and flips fire notify-send", () => {
  assert.match(main, /if \(pomodoroActive\) pomodoroStop\(\) \/\/ modes are exclusive/)
  assert.match(main, /notify-send -a 'Time Piece'/)
  assert.match(main, /function notifyPhase\(mode\)/)
  assert.match(main, /Model\.nextPomodoroPhase\(pomodoroMode, pomodoroCyclesDone, pomodoroFocusMin, pomodoroBreakMin\)/)
})

test("chip carries the countdown in the label via Model", () => {
  assert.match(main, /Model\.pomodoroBarSuffix\(pomodoroMode/)
  assert.match(main, /Model\.formatCountdown\(Math\.max\(0, timerEndsAt - now\.getTime\(\)\)\)/)
})

test("world clocks parse through Model and read zone times via a validated date call", () => {
  assert.match(main, /Model\.parseWorldClocks\(String\(Plasmoid\.configuration\.worldClocks \|\| ""\)\)/)
  assert.match(zonesComp, /date '\+%-I:%M %p'/)
  assert.match(zonesComp, /TZ='/)
  assert.match(zonesComp, /\^\[0-9\]\{1,2\}:\[0-9\]\{2\} \(AM\|PM\)\$/) // output validated before display
  assert.match(zonesComp, /onNewData: \(sourceName, data\) =>/) // formal params, never injected
})

test("zone add/remove goes through Model.zonesToString in both surfaces", () => {
  assert.match(main, /function zonesRemove\(zone\)/)
  assert.match(main, /Model\.zonesToString\(kept\)/)
  assert.match(config, /function zoneAdd\(zone\)/)
  assert.match(config, /function zoneRemove\(zone\)/)
  assert.match(config, /Model\.zonesToString\(current\)/)
  assert.match(config, /Model\.zonesToString\(kept\)/)
})

test("settings dialog searches the verbatim zones.js picker through Model.filterZones", () => {
  assert.match(config, /import "\.\.\/ui\/zones\.js" as Zones/)
  assert.match(config, /import "\.\.\/ui\/Model\.js" as Model/)
  assert.match(config, /Model\.filterZones\(Zones\.TZ_REGIONS, text, 8\)/)
})

test("popup timer section is labeled — reads as a timer, not mystery steppers", () => {
  assert.match(popup, /TIMER · DONE/)
  assert.match(popup, /TIMER · RUNNING/)
  assert.match(popup, /TIMER · PAUSED/)
})

test("v0.5 timer section redesign pins (spec: design/timer-ux-spec.md)", () => {
  assert.match(popup, /text: Model\.formatCountdown\(timerSection\.remainingMs\)/)
  assert.match(popup, /property string timerTab: "manual"/)
  assert.match(popup, /panel\.timerTab = "pomo"/)
  assert.match(popup, /visible: timerSection\.idleOnly/)
  assert.match(popup, /property color phaseColor/)
  assert.match(popup, /width: parent\.width \* timerSection\.phaseFraction/)
  assert.match(popup, /model: Model\.POMODORO_CYCLE/)
  assert.match(popup, /if \(modelData <= done\) return panel\.accent/)
  assert.match(popup, /dimmed: !timerSection\.idleOnly/)
  assert.match(popup, /START CYCLE/)
  assert.match(popup, /FOCUS " \+ applet\.pomodoroFocusMin/)
  assert.match(popup, /SKIP →/)
})

test("tz hue pass matches the spec list, applied by zone order with a fallback", () => {
  assert.match(palette, /TZ_HUES = \["#7dcfff", "#e0af68", "#f7768e", "#7aa2f7", "#ff9e64"\]/)
  assert.match(palette, /"#9ece6a"/)   // break hue
  assert.match(palette, /"#bb9af7"/)   // long-break hue
  assert.match(popup, /index < Palette\.TZ_HUES\.length/)
})

test("calendar grid is wired through Model (grid, weekday order, year progress)", () => {
  assert.match(popup, /Model\.monthGrid\(panel\.viewYear/)
  assert.match(popup, /Model\.weekdayOrder\(panel\.applet\.weekStart\)/)
  assert.match(popup, /Model\.yearProgressPercent\(/)
  assert.match(main, /Model\.normalizedWeekStart\(/)
  assert.match(main, /Model\.weekStartSettingName\(Model\.toggledWeekStart\(weekStart\)\)/)
})

test("package identity and metadata carry the port", () => {
  assert.equal(meta.KPackageStructure, "Plasma/Applet")
  assert.equal(meta.KPlugin.Id, "com.gdeyoung.plasma.timepiece")
  assert.equal(meta.KPlugin.Version, "0.1.0")
  assert.equal(meta["X-Plasma-API-Minimum-Version"], "6.0")
})

test("no Quickshell imports leaked into the ported files", () => {
  for (const f of [main, popup, zonesComp, config])
    assert.doesNotMatch(f, /import Quickshell/)
})
