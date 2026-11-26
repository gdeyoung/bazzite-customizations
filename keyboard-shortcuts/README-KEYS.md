# Hermes desktop keys — KDE, Omarchy-parity

No key remapper needed: KDE's `kglobalaccel` (System Settings → Keyboard →
Shortcuts) already maps keys to apps, KRunner, or arbitrary commands,
user-level and reversible. `keyboard-shortcuts/hermes-keys.sh apply` encodes
the four binds below; `revert` removes them; `status` shows state.

v2 (2026-11-01): reconciled with the live box — Super+Space was set by hand
on 2026-11-01 and the script now writes the same stanza it lives in; the
Meta+Shift+H bind was redesigned (see Notes).

## The binds

| Key | Action | Why this one |
|---|---|---|
| **Meta+Space** | KRunner — `ai <q>`, `hr <task>`, `ssh <host>`, `;snip` | Your primary Omarchy gesture. Live since 2026-11-01; Alt+Space is gone. |
| **Meta+Return** | Konsole | "super enter = terminal" — Omarchy muscle memory. |
| **Meta+H** | KRunner preloaded with `ai ` — type the question, Enter | Ask-lane one keystroke from anywhere. |
| **Meta+Shift+H** | KRunner preloaded with `hr ` — type the task, Enter | Task-lane one keystroke from anywhere. |
| Hold **COMPOSE** (Ornata) | voxtype PTT dictation | Already wired (evdev 127) — untouched, conflicts with nothing. |

Not added: **Super+numbers → workspaces.** You said you barely use it, and
Plasma already has Meta+Ctrl+arrows for desktops; Meta+1..9 is better kept on
task switching (default behavior). Skip until you feel the want.

Already taken on this box (do not rebind): Meta+D peek desktop, Meta+W
overview, Meta+T tile editor, Meta+G grid, Meta+L lock, Meta+Ctrl+arrows
desktops, Meta+F1..12 desktop-switch/other, Meta+Alt+arrows window switch.
Meta+H / Meta+Return / Meta+Shift+H verified unclaimed 2026-11-01.

## Verify (apply day, 30 seconds)

1. `./keyboard-shortcuts/hermes-keys.sh apply` → log out/in once.
2. Meta+Space → KRunner opens → type `ai ping` → answer row/notification.
3. Meta+Return → Konsole opens.
4. Meta+H → KRunner opens with `ai ` prefilled, caret in the box.
5. Meta+Shift+H → KRunner opens with `hr ` prefilled → type `reply OK` →
   Enter → notification when the agent turn finishes.
6. If a bind didn't register: System Settings → Keyboard → Shortcuts — the
   Hermes entries are listed there and can be bound/changed by hand (that
   GUI is ground truth for kglobalaccel).

## Notes

- App-launcher shortcuts live in `kglobalshortcutsrc` as nested
  `[services][<desktop-file-id>]` groups — the same mechanism System Settings
  writes. The custom lanes are `.desktop` launchers in
  `~/.local/share/applications/`; `revert` removes both halves.
- Both preloads call KRunner's DBus `/App query`, which opens the window with
  the text prefilled (verified against KRunner 6.31 in the runner harness).
  Because input then flows through the normal Match→Run path, counters,
  recents, and notifications all work.
- v1's Meta+Shift+H used a kdialog box + a direct `Run` call at the runner
  daemon. Dropped: `.desktop` Exec lines are not shell-parsed, so the
  `$(kdialog …)` substitution never executed — the bind was broken by
  construction. The preload design replaces it with one tested mechanism.
- If a Plasma update renames `/App query`, the fallback is plain
  `kglobalaccel` → `krunner` (the key just opens the search) — one line per
  bind to change, noted here.
