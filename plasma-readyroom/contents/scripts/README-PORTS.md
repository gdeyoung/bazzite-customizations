# Ported scripts — provenance and classification

All `gc-*` helpers are **verbatim ports** (sha256-identical) from
[omarchy-ready-room](https://github.com/gdeyoung/omarchy-ready-room) — see
README.md for the source pin. Two helpers exist only in this Plasma port:

| script | what it does | reads | writes |
|---|---|---|---|
| `gc-gear-stats` | wraps `gc-stats` in `timeout … \| head -2` for the dataengine's connect/disconnect cycle | /proc, /sys, nvidia-smi | nothing |
| `71-readyroom.rules` | verbatim upstream udev rule (copied beside gc-udev, which finds it relative to itself) | — | nothing (installed only by the user, manually, as root) |

Notes on verbatim scripts:

- `gc-session`, `gc-replay`, `gc-binds`, `gc-mangohud`, `gc-udev`,
  `gc-clip-saved` call Omarchy-specific CLIs (`omarchy-shell`,
  `omarchy-toggle-idle`, `omarchy-notification-send`,
  `omarchy-launch-floating-terminal-with-presentation`, `hyprctl`,
  `hyprsunset`). On Bazzite those are absent, so the affected subcommands
  degrade exactly as upstream designed (ownership refused, states read
  "unknown"/"foreign", errors surface in the UI) rather than misbehaving.
  See README "Omarchy-only helpers on Bazzite" for the matrix.
- `gc-thumb` is ported for clip thumbnails but unused by v0.1.0's QML (kept
  so the helper set stays byte-identical for future tabs).
- Port law: bugfixes found here must be filed/fixed upstream first, then
  re-copied — the same rule the Omarchy plugins follow in reverse.
