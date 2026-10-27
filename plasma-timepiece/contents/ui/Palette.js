// Categorical identity hues carried over from the Omarchy design spec
// (design/timer-ux-spec.md §5) — they are the SPEC, not decoration choices:
//   TZ_HUES        stable arbitrary marks for the world-clock labels
//                  (cyan/amber/rose/blue/orange — deliberately no green or
//                  violet, so zones never masquerade as pomodoro phases)
//   BREAK_HUE      pomodoro break phase
//   LONG_BREAK_HUE pomodoro long-break phase
// Kept as hex literals exactly as specced, in a .js data file so the QML
// sources themselves stay theme-token clean. Degrade rule per spec: these
// literals appear ONLY on decorative phase elements (dots, phase words,
// thin fills); every digit and verb stays theme foreground.
var TZ_HUES = ["#7dcfff", "#e0af68", "#f7768e", "#7aa2f7", "#ff9e64"]
var BREAK_HUE = "#9ece6a"
var LONG_BREAK_HUE = "#bb9af7"
