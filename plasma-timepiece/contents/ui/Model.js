// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
//
// Walked in UTC, where every day is 24 hours long. A local-midnight cursor has
// to be resolved by the engine in zones that start DST at 00:00 -- Chile every
// September, Cuba every March -- and V4 resolves the missing midnight backward
// onto the previous day while V8 resolves it forward, so the local walk repeats
// a date in the shell and not under the tests. A grid of civil dates never
// needed a wall clock in the first place.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(Date.UTC(year, month, 1)).getUTCDay() - start + 7) % 7
  var cursor = new Date(Date.UTC(year, month, 1 - leading))
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getUTCFullYear()
      var cellMonth = cursor.getUTCMonth()
      var cellDay = cursor.getUTCDate()
      var weekday = cursor.getUTCDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setUTCDate(cursor.getUTCDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

// UTC for the same reason as the grid: the month is read back off the date, so
// a first of the month that has no local midnight would step into the wrong one.
function stepMonth(year, month, delta) {
  var target = new Date(Date.UTC(year, Number(month) + Number(delta), 1))
  return { year: target.getUTCFullYear(), month: target.getUTCMonth() }
}

// ---- Bar-label date masking. `showDate: false` takes the date out of the
//      bar label while leaving the day name and the time alone, whatever
//      format the label is in (including every format on the right-click
//      ring). Day-NAME tokens (ddd/dddd) are kept; numeric date tokens
//      (d, dd, MMM, MMMM, yy, yyyy, ww) are dropped word by word. A format
//      that is nothing BUT date tokens is returned unchanged — a clock with
//      nothing to show is worse than a clock with the date still in it.
var DATE_WORD = /MMMM|MMM|yyyy|yy|'W'|ww/
var BARE_DAY = /^d{1,2}$/
var ORPHAN_SEPARATOR = /^[-–—,./]+|[-–—,./]+$/g

function stripDateWords(line) {
  var kept = []
  var words = String(line).split(" ")
  for (var i = 0; i < words.length; i++) {
    var word = words[i]
    if (word === "") continue
    if (DATE_WORD.test(word) || BARE_DAY.test(word)) continue
    var trimmed = word.replace(ORPHAN_SEPARATOR, "")
    if (trimmed === "") continue
    kept.push(trimmed)
  }
  if (kept.length === 0) return String(line)
  return kept.join(" ")
}

function applyShowDate(format, showDate) {
  if (showDate === false || showDate === "false") {
    return String(format).split("\n").map(stripDateWords).join("\n")
  }
  return String(format)
}

// ---- World clock. Setting shape: "ET:America/New_York,PT:America/Los_Angeles".
//      Labels stay short enough for the row (city names allowed — it wraps).
function plausibleTimeZone(zone) {
  return /^UTC$|^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+){1,2}$/.test(zone)
}

function parseWorldClocks(spec) {
  if (!spec || typeof spec !== "string") return []
  var out = []
  var parts = spec.split(",")
  for (var i = 0; i < parts.length; i++) {
    var piece = parts[i].replace(/^\s+|\s+$/g, "")
    if (piece === "") continue
    var idx = piece.indexOf(":")
    if (idx < 1) continue
    var label = piece.slice(0, idx).replace(/^\s+|\s+$/g, "")
    var zone = piece.slice(idx + 1).replace(/^\s+|\s+$/g, "")
    if (label === "" || zone === "" || label.length > 14) continue
    if (out.length >= 5) break
    if (!plausibleTimeZone(zone)) continue
    out.push({ label: label, zone: zone })
  }
  return out
}

// zonesToString: inverse of parseWorldClocks — picker writes go through this
//      so the stored shape never drifts.
function zonesToString(zones) {
  var out = []
  for (var i = 0; i < zones.length; i++) out.push(zones[i].label + ":" + zones[i].zone)
  return out.join(",")
}

// ---- Zone search (settings view). NN/g findings: users find zones by city,
//      not offset; search beats browsing; abbreviations people actually say
//      (ET, PT, UTC) resolve as aliases. Ranking: alias > city starts-with >
//      city contains > region/subregion match (region only from 3 chars, so
//      "a" does not dump all of Africa/America).
var ZONE_ALIASES = {
  et: "America/New_York", est: "America/New_York",
  ct: "America/Chicago", cst: "America/Chicago",
  mt: "America/Denver", mst: "America/Denver",
  pt: "America/Los_Angeles", pst: "America/Los_Angeles",
  utc: "UTC", gmt: "UTC", z: "UTC"
}

function prettifyCity(path) {
  var parts = String(path).split("/")
  return parts[parts.length - 1].replace(/_/g, " ")
}

function filterZones(regions, query, limit) {
  limit = limit || 8
  var q = String(query || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (q === "") return []
  var scored = []
  function add(score, zone, region, city) {
    for (var i = 0; i < scored.length; i++) {
      if (scored[i].zone === zone) { if (score > scored[i].s) scored[i].s = score; return }
    }
    scored.push({
      s: score,
      zone: zone,
      region: region,
      city: prettifyCity(city),
      subregion: String(city).indexOf("/") >= 0 ? String(city).split("/")[0].replace(/_/g, " ") : ""
    })
  }
  var alias = ZONE_ALIASES[q]
  if (alias) {
    if (alias === "UTC") add(3, "UTC", "UTC", "UTC")
    else {
      var rp = alias.split("/")
      add(3, alias, rp[0], rp[1])
    }
  }
  for (var region in regions) {
    if (!Object.prototype.hasOwnProperty.call(regions, region)) continue
    var rl = region.toLowerCase()
    var cities = regions[region]
    for (var j = 0; j < cities.length; j++) {
      var city = cities[j]
      var zone = region + "/" + city
      if (alias && zone === alias) continue
      var pretty = prettifyCity(city).toLowerCase()
      if (pretty.indexOf(q) === 0) add(2, zone, region, city)
      else if (pretty.indexOf(q) >= 0) add(1, zone, region, city)
      else if (rl.indexOf(q) === 0 && q.length >= 3) add(0.5, zone, region, city)
      else if (zone.toLowerCase().indexOf(q) >= 0) add(0.5, zone, region, city)
    }
  }
  scored.sort(function(a, b) {
    if (b.s !== a.s) return b.s - a.s
    return a.zone < b.zone ? -1 : (a.zone > b.zone ? 1 : 0)
  })
  var out = []
  for (var k = 0; k < scored.length && out.length < limit; k++) {
    out.push({ zone: scored[k].zone, region: scored[k].region, city: scored[k].city, subregion: scored[k].subregion })
  }
  return out
}

// ---- Countdown timer. State lives in the widget entry: timerMinutes is the
//      idle preset, timerEndsAt/timerRemainingMs carry run/pause, timerDoneAt
//      stamps the fire so the bar's "done" ping can age out on its own.

// ---- Pomodoro. A second timer mode that runs itself: focus blocks alternate
//      with breaks, every 4th break is a long one, and phases advance without
//      a click. State lives in the widget entry next to the manual timer's:
//      pomodoroMode ("off"|"focus"|"break"|"longbreak"), pomodoroEndsAt,
//      pomodoroCyclesDone, pomodoroFocusMin, pomodoroBreakMin. The manual
//      timer and pomodoro never run at once — starting one clears the other.
var POMODORO_LONG_BREAK_MIN = 15
var POMODORO_CYCLE = 4 // focus blocks before a long break

function clampPomodoroMinutes(value, fallback, lo, hi) {
  var n = Math.round(Number(value) || fallback)
  return Math.max(lo, Math.min(hi, n))
}

// The one transition table. mode is the phase ENDING; returns the next state
// (mode, minutes, cyclesDone) or null for "off"/unknown input.
function nextPomodoroPhase(mode, cyclesDone, focusMin, breakMin) {
  focusMin = clampPomodoroMinutes(focusMin, 25, 1, 120)
  breakMin = clampPomodoroMinutes(breakMin, 5, 1, 60)
  var done = Number(cyclesDone) || 0
  if (mode === "focus") {
    done += 1
    if (done % POMODORO_CYCLE === 0) return { mode: "longbreak", minutes: POMODORO_LONG_BREAK_MIN, cyclesDone: done }
    return { mode: "break", minutes: breakMin, cyclesDone: done }
  }
  if (mode === "break" || mode === "longbreak") {
    return { mode: "focus", minutes: focusMin, cyclesDone: done }
  }
  return null
}

function pomodoroPhaseLabel(mode) {
  if (mode === "focus") return "FOCUS"
  if (mode === "break") return "BREAK"
  if (mode === "longbreak") return "LONG BREAK"
  return ""
}

// Bar suffix: F/B/L + mm:ss so the label stays short (Sunday Oct 18 5:30 PM · F 17:32).
function pomodoroBarSuffix(mode, msRemaining) {
  var letter = mode === "focus" ? "F" : (mode === "break" ? "B" : (mode === "longbreak" ? "L" : ""))
  if (letter === "") return ""
  return letter + " " + formatCountdown(msRemaining)
}

function formatCountdown(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var m = Math.floor(total / 60)
  var s = total % 60
  return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
}

function stepTimerMinutes(minutes, delta) {
  var next = (Number(minutes) || 0) + delta
  if (next < 1) return 1
  if (next > 600) return 600
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    stripDateWords: stripDateWords,
    applyShowDate: applyShowDate,
    plausibleTimeZone: plausibleTimeZone,
    parseWorldClocks: parseWorldClocks,
    zonesToString: zonesToString,
    prettifyCity: prettifyCity,
    filterZones: filterZones,
    formatCountdown: formatCountdown,
    stepTimerMinutes: stepTimerMinutes,
    POMODORO_LONG_BREAK_MIN: POMODORO_LONG_BREAK_MIN,
    POMODORO_CYCLE: POMODORO_CYCLE,
    clampPomodoroMinutes: clampPomodoroMinutes,
    nextPomodoroPhase: nextPomodoroPhase,
    pomodoroPhaseLabel: pomodoroPhaseLabel,
    pomodoroBarSuffix: pomodoroBarSuffix
  }
}
