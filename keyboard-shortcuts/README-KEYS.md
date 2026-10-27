# Hermes desktop keys — KDE, Omarchy-parity

No key remapper needed: KDE's `kglobalaccel` (System Settings → Keyboard →
Shortcuts) already maps keys to apps, KRunner, or arbitrary commands,
user-level and reversible. `keyboard-shortcuts/hermes-keys.sh apply` encodes
the four binds below; `revert` removes them; `status` shows state.

## The binds (chosen against your live shortcut map, 2026-10-26)

| Key | Action | Why this one |
|---|---|---|
| **Meta+Space** | KRunner (with the Hermes runner: `ai <q>`, `hr <task>`) | Your primary Omarchy gesture. Alt+Space stays as stock secondary. |
| **Meta+Return** | Konsole | "super enter = terminal" — Omarchy muscle memory. |
| **Meta+H** | KRunner preloaded with `ai ` — type the question, Enter | Ask-lane one keystroke from anywhere. |
| **Meta+Shift+H** | Input box → fires `hr <task>` directly at the runner daemon | Task lane without opening KRunner at all. |
| Hold **COMPOSE** (Ornata) | voxtype PTT dictation | Already wired (evdev 127) — untouched, conflicts with nothing. |

Not added: **Super+numbers → workspaces.** You said you barely use it, and
Plasma already has Meta+Ctrl+arrows for desktops; Meta+1..9 is better kept on
task switching (default behavior). Skip until you feel the want.

Already taken on this box (do not rebind): Meta+D peek desktop, Meta+W
overview, Meta+T tile editor, Meta+G grid, Meta+L lock, Meta+Ctrl+arrows
desktops, Meta+F1..12 desktop-switch/other, Meta+Alt+arrows window switch.

## Verify (install day, 30 seconds)

1. `./keyboard-shortcuts/hermes-keys.sh apply` → log out/in once.
2. Meta+Space → KRunner opens → type `ai ping` → answer row/notification.
3. Meta+Return → Konsole opens.
4. Meta+H → KRunner opens with `ai ` prefilled.
5. Meta+Shift+H → input box → "reply OK" → notification with the agent's tail.
6. If a bind didn't register: System Settings → Keyboard → Shortcuts →
   Custom Shortcuts — the three Hermes entries are listed there and can be
   bound/changed by hand (that GUI is ground truth for kglobalaccel).

## Notes

- The custom lanes are `.desktop` launchers in `~/.local/share/applications/`
  + entries in `kglobalshortcutsrc` — the same mechanism System Settings
  writes; nothing layered, `revert` removes both halves.
- Meta+H uses KRunner's DBus `/App query` (single-runner-style preload). If a
  Plasma update renames that method, the fallback is plain `kglobalaccel` →
  `krunner` (Meta+H just opens the search) — one line to change, noted here.
