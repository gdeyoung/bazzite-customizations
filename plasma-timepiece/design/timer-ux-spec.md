# Time Piece — Timer/Pomodoro Section Redesign + tz Color Pass

Repo: omarchy-timepiece v0.4.0. Scope: the timer block in `Panel.qml` (~L995–1112)
redesign; light color pass on the popup tz row (~L518–581). No changes to
settings view, config shape, Model.js state machine, or bar-suffix behavior.
Design target: ~420px popup width (grid column ~390 inside padding), degrades
via the existing Flickable. Engine: Quickshell 0.3.2 / Qt6 Quick / V4 — no
computed object keys, no Canvas, no images; glyphs + plain Rectangle/Text/Row/
Column/Flow + Behavior only.

Fixes for the owner's verdict ("plain blah, not intuitive"): (a) no hierarchy —
readout same size as buttons; (b) "10M" read like a third button; (c) no state
or progress feedback; (d) two invisible modes swapped via visibility tricks;
(e) "N OF 4" buried in a 10px label.

## 1. Layout sketches (~420px, states abridged)

```
IDLE · manual tab                IDLE · pomodoro tab
+--------------------------------------+ +--------------------------------------+
| TIMER·          [ TIMER | POMODORO ] | | TIMER·          [ TIMER | POMODORO ] |
|                                      | |                                      |
|   +----+                        +----+| |        FOCUS 25 · BREAK 5            |
|   | −5M|      1 0 : 0 0         | +5M|| |              25:00                   |
|   +----+   (24px bold digits)   +----+| |        LONG 15 · 4 BLOCKS            |
|                                      | |                                      |
|           [ START ]                  | |          [ START CYCLE ]              |
+--------------------------------------+ +--------------------------------------+

RUNNING · manual                   DONE · manual (ping, ≤2 min)
| TIMER · RUNNING·                     | | TIMER · DONE· ●(pulse)                |
|   (dim)   0 7 : 3 2                  | |   (urgent) 0 0 : 0 0                  |
|   ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░          | |   ░░░░░░░░░░░░░░░░░░░░░░░░ (empty)    |
|        [ PAUSE ]                     | |            [ RESET ]                  |

POMODORO · focus (2nd block)       POMODORO · break / long break
| POMODORO · FOCUS · 2 OF 4· ●        | | POMODORO · BREAK · 2 OF 4· ●          |
|            1 7 : 3 2                 | | POMODORO · LONG BREAK · 4 OF 4· ●     |
|   ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░           | |   ▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░             |
|   ▓▓▓▓░░░▓▓▓▓░░░░░░▓▓▓▓░░░  rail     | |   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░  rail             |
|      [ SKIP → ]   [ STOP ]           | |      [ SKIP → ]   [ STOP ]            |
```

- `·` = phaseColor dot (6px ●). `▓` thin phase bar = REMAINING time.
- Rail = 4 segments = the 4 focus blocks of the set (see §4).
- Paused manual = RUNNING sketch with header `TIMER · PAUSED`, digits at
  Util.alpha(fg, 0.75), frozen bar, verbs `RESUME` / `RESET`.

## 2. Element tree (QML)

```
Item timerSection (width: parent.width)          // replaces current Item L1001
├─ Row headerRow (width: parent.width, spacing: Style.space(8))
│  ├─ Text sectionTitle    // caption, ls 2, Qt.darker(fg,1.5) — existing idiom
│  ├─ Rectangle phaseDot   // 6x6, radius 3→space(2)? use radius width/2, phaseColor
│  └─ Item headerSpacer (fill) + Row modeTabs (anchors.right, visible: idleOnly)
│     ├─ Rectangle tabTimer  { border hairline; Text "TIMER" }
│     └─ Rectangle tabPomo   { same; Text "POMODORO" }
├─ Item heroBlock (width: parent.width, topMargin: space(6))
│  ├─ Row heroRow (horizontalCenter, spacing: space(12))
│  │  ├─ TimerPill stepDown  label "−5M"  width: space(52)  // fixed slot
│  │  ├─ Text heroReadout    // display, bold; digits NEVER below 1:1 contrast
│  │  └─ TimerPill stepUp    label "+5M"  width: space(52)  // fixed slot
│  ├─ Rectangle phaseBar (width: gridColumn.width, height: space(3))
│  │  ├─ track color: Util.alpha(fg, 0.12); radius: space(1)
│  │  └─ Rectangle phaseFill (anchors.left, width: frac * parent.width)
│  └─ Text pomoSummary      // pomodoro idle only, caption, centered
├─ Row cycleRail (horizontalCenter, spacing: space(4))   // pomodoro runs only
│  └─ 4 × Rectangle segment (w: (gridColumn.width − 3*space(4))/4, h: space(4))
└─ Row verbsRow (horizontalCenter, topMargin: space(10), spacing: space(8))
   └─ TimerPill ×1–2  (primary / ghost, see states)
```

TimerPill additions (backwards compatible): `property color toneColor` (default
`Commons.Color.accent`) driving `prominent` text/border/hover tint; `property
bool enabled2` visual-dim (opacity 0.3, no hover) — keep signal `clicked()`;
min height `space(24)`, primary verb padding `space(28)` wide / `space(28)` tall.

## 3. Typography, spacing, radii

| Element | Style.font.* | Weight/ls | Notes |
|---|---|---|---|
| heroReadout | display (24) | bold, ls 1 | mm:ss always, tabular monospace |
| sectionTitle / "N OF 4" | caption (10) | ls 2 | matches existing section labels |
| pill/tab verbs | caption (10) | bold, ls 1 | TimerPill idiom unchanged |
| pomoSummary | caption (10) | ls 1, muted | `Qt.darker(fg,1.5)` |
| tz label (popup) | caption (10) | ls 1 | hue pass §5; tz time stays body bold fg |

Spacing rhythm (all `Style.space()`): header→hero 6, stepper↔hero 12,
hero→bar 8, bar→rail 6, rail→verbs 8, verbs internal gap 8, section top gap 10
(matches calendarColumn rhythm of 8/10). Pill heights: ghost `max(24, text+8)`,
primary 28 (= `Style.spacing.controlHeight`). Radii: pills/tabs
`Style.cornerRadius`; phaseBar `space(1)`; segments/dot `space(2)`.

## 4. States (every one; visibility = V/E, colors = roles)

`idleOnly` := `!timerRunning && timerDoneAt===0 && timerRemainingMs===0 && !pomodoroActive`.
Tab property: in-memory `property string timerTab: "manual"` on the panel —
NEVER persisted (no config migration into popup). Tabs hidden unless idleOnly.

**Manual idle-fresh** — title "TIMER"; tabs V (TIMER selected: fill
`Style.selectedFillFor(fg,accent)` 0.18 + accent text; other transparent+fg);
hero `formatCountdown(timerMinutes*60000)` e.g. "10:00" (kills the "10M looks
like a button" problem; mm:ss is the universal timer format — Nielsen
consistency); steppers E; verbs: [START] primary. No bar, no rail, no dot.
**Manual idle-adjusted** — same, hero reflects new preset.
**Manual running** — tabs hidden; title "TIMER · RUNNING"; dot accent; hero
mm:ss fg; phaseBar fill accent, width = remaining/initial; steppers V but
disabled-dim; verbs [PAUSE] primary. Fixed stepper slots ⇒ zero layout shift.
**Manual paused** — title "TIMER · PAUSED"; hero alpha 0.75; bar frozen;
steppers disabled; verbs [RESUME] primary, [RESET] ghost.
**Manual done (ping ≤2 min)** — title "TIMER · DONE"; dot urgent pulsing; hero
"00:00" urgent bold; bar track `Util.alpha(urgent,0.15)`, fill 0; steppers
disabled; verbs [RESET] primary with urgent tone.
**Pomodoro idle (tab)** — hero "25:00" (= pomodoroFocusMin); summary
"FOCUS 25 · BREAK 5 · LONG 15 · 4 BLOCKS"; verbs [START CYCLE] primary accent.
**Pomodoro focus** — title "POMODORO · FOCUS · " + ((cyclesDone%4)+1) + " OF 4";
dot+bar+hero accent; rail: `longbreak ? 4 : cyclesDone%4` segments filled
accent, current block half-alpha, rest `Util.alpha(fg,0.12)`; verbs
[SKIP →] ghost, [STOP] ghost. No steppers in pomodoro tab.
**Pomodoro break** — title "POMODORO · BREAK · " + min(cyclesDone,4) + " OF 4"
(count = completed blocks; rail carries the same info visually);
dot+bar break-green; rail unchanged (accent = work done); verbs same.
**Pomodoro longbreak** — title "POMODORO · LONG BREAK · 4 OF 4"; all hues
violet; rail 4/4 filled accent; verbs same.
Mutual exclusion unchanged: starting either mode still clears the other
(existing timerToggle/pomodoroStart guards); tabs-hidden-while-running makes
the lock visible instead of implied.

## 5. Color decisions

Phase story — three roles, never color alone (WCAG 1.4.1; the phase WORD and
dot shape/position always co-code):

| Role | Value | Where used |
|---|---|---|
| FOCUS | `Commons.Color.accent` (token) | dot, phase word, bar fill, hero(digits) |
| BREAK | `#9ece6a` literal | dot, phase word, bar fill — NOT digits |
| LONG BREAK | `#bb9af7` literal | same set as BREAK |
| DONE | `Commons.Color.urgent` (token) | dot, "00:00", track tint |
| neutral | foreground / `Qt.darker(fg,1.5)` | everything informational |

Justification + degradation: accent/urgent are tokens by construction. The two
literals are mid-lightness, hue-120°-apart rest colors (Tokyo Night palette,
field-tested on dark bars): #9ece6a ≈ 9:1 and #bb9af7 ≈ 7:1 on the #101315
default bg. Degrade rule: literals may appear ONLY on the ≤3 decorative phase
elements (dot, phase word, thin fill); every digit and verb stays foreground —
a hostile theme can make the section less colorful, never unreadable. They are
deliberately NOT accent-derived: accent often lands blue/green per theme, and
re-deriving breaks would collapse the focus/break distinction. If Color ever
grows success/secondary roles, each literal swaps to a token in one line.
Default Omarchy theme ships accent == foreground (#cacccc): focus reads
neutral-hot, breaks still read green/violet — distinction survives.

tz row (light pass): 5-entry constant array (plain array literal — V4 safe),
indexed by zone order, no new config:
`TZ_HUES = ["#7dcfff","#e0af68","#f7768e","#7aa2f7","#ff9e64"]`
(cyan/amber/rose/blue/orange — none green/violet, so zones never masquerade as
pomodoro phases in the same popup). Apply to the zone LABEL text only; the time
stays foreground bold. Zone >5 is capped already; index ≥5 falls back to
`Qt.darker(fg,1.5)`. Justification: owner float; categorical hues are
arbitrary-but-stable identity marks (Gestalt similarity), mid-lightness so
they survive light themes as decoration while the payload text stays readable.

## 6. Motion (Behavior / PropertyAnimation only, Qt6 Quick)

1. `phaseFill.width`: `Behavior on width { NumberAnimation { duration: 300;
   easing.type: Easing.OutQuad } }` — smooths the 250ms state ticks.
2. Phase/dot/word/fill `color`: `Behavior on color { ColorAnimation {
   duration: 250 } }` — phase flips read as one crossfade, not a repaint.
3. Done pulse: `SequentialAnimation on phaseDot.opacity { running:
   timerDoneAt > 0; loops: Animation.Infinite; NumberAnimation 1→0.25 (500,
   InOutQuad); NumberAnimation 0.25→1 (500, InOutQuad) }`.
4. Hover stays instant (existing pill idiom) and tabs/verbs changes are
   instant — restraint; nothing else animates. No anchors animated; only
   width/color/opacity (cheap, no re-layout beyond the bar itself).

## 7. Rationale (per major decision)

- Hero 24px readout + 10px controls: visual hierarchy — the number IS the
  section (NN/g visual hierarchy; "plain blah" was equal-weight text).
- mm:ss in every state incl. idle: consistency & standards (Nielsen #4); "10M"
  was read as a button (Affordance, Norman).
- Segmented TIMER|POMODORO tabs: recognition over recall + visibility of
  system status (Nielsen #1, #2); two unnamed modes sharing one row via
  visibility swaps was the core intuition failure. Fitts: tabs are 24px-tall
  wide targets at the section's edge.
- Steppers flanking the value in fixed slots: Fitts (targets adjacent to the
  thing they change) + Gestalt proximity; fixed slots kill centering jumps.
- Thin remaining-bar + 4-segment cycle rail: dual-scale progress (phase vs
  set) answers "how long left" and "where am I" separately — Jakob's Law
  (progress bars/segmented rails match every other timer UI users know).
- Phase color triad + word + dot: redundancy, never color alone (WCAG 1.4.1);
  accent = engagement, desaturated-adjacent green/violet = arousal-down rest.
- Tabs hidden while anything runs: constraint made visible (mutual exclusion),
  prevents mode-confusion mid-run (Nielsen error prevention #5).
- Config stays in settings, tab state stays in RAM: minimal-action for the
  90% case without migrating config back into the read-out popup.

## 8. Implementation notes / risks

- Keep every existing function/persist key: timerStep/timerToggle/timerReset,
  pomodoroStart/Advance/Stop, POMODORO_CYCLE; only the Item L1001–1112 block
  and TimerPill internals change. Model.js: reuse formatCountdown,
  pomodoroPhaseLabel; nothing new needed (rail counts are inline arithmetic).
- Heights: section grows ~space(70); popup already Flickable — verify
  contentHeight includes new children; at 420px worst row (RUNNING: title +
  hero + bar + verbs) ≈ 24+30+3+28+rhythm ≈ 130px, fits without scroll.
- V4 traps: plain array literal for TZ_HUES (no computed keys); rail fill
  count via ternary, not lookup object; no .js module imports.
- Risk: theme accents that are green/violet narrow the focus-vs-break hue gap —
  mitigated by word+dot dual coding; accept, don't hue-compare in V4.
- Risk: pulse + 300ms width animation run while popup open only; done ping
  outlasts popup — animation `running:` binding self-stops on close. Cheap.
- Risk: tab memory ("manual" default each open) could surprise users who
  always pomodoro — acceptable; persisting it would violate the no-config-
  in-popup rule. Revisit only if owner asks.
