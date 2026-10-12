# VoxType push-to-talk dictation on KDE Plasma Wayland — remote WhisperX backend

Hold a key, speak, release: the text types itself into whatever app has focus —
any app, Wayland or XWayland. Transcription runs on a **remote [WhisperX](https://github.com/m-bain/whisperX)
server on the LAN**, not on the desktop, so an immutable, GPU-less Bazzite/Kinoite
box gets GPU-quality Whisper with sub-second round-trips.

Built on [peteonrails/voxtype](https://github.com/peteonrails/voxtype) (MIT) —
the excellent local-first dictation tool that ships with Omarchy — using its
`mode = "remote"` backend pointed at a self-hosted
[whisperx-asr-service](https://hub.docker.com/r/learnedmachine/whisperx-asr-service)
container. The non-obvious discovery that makes this trivial: **that container
serves the OpenAI-compatible `/v1/audio/transcriptions` route alongside its
native `/asr`**, so voxtype's remote mode talks to it with no shim, no proxy,
no code.

```
[PTT key] ──evdev(code 127)──▶ voxtype daemon ──16 kHz mono wav──▶ POST /v1/audio/transcriptions
                                     │                                     │
                                     │                             WhisperX on GPU
                                     ◀──────── text ────────────────────────┘
                                     │
                                     ├──▶ ydotoold (uinput virtual kbd) ──▶ KWin ──▶ focused app
                                     ├──▶ OSD waveform (GTK4 layer-shell)
                                     └──▶ MPRIS pause-while-dictating
```

## Measured numbers

Verified on Fedora Kinoite 44 (Plasma 6.7.5 Wayland, PipeWire/WirePlumber 0.5.17),
voxtype 1.1.0, WhisperX (`large-v3` class, float16 CUDA) on the LAN:

| Measurement | Result |
|---|---|
| Remote transcription round-trip, 3.5 s utterance | **0.46 s** |
| Remote transcription round-trip, 22.1 s utterance | **0.97 s** |
| CLI `voxtype transcribe`, 5.1 s synthetic sample | 0.51 s, exact text |
| Typing delivery under concurrent key events | 150/150 keystrokes delivered (kernel-level capture) |
| `type_delay_ms = 0` (default) | intermittent truncation — typed output cut at ~16–20 chars |
| `type_delay_ms = 5` | 5/5 consecutive dictations complete |
| `type_delay_ms = 10` | 5/5 consecutive dictations complete |

## The gotchas (each one cost an hour)

1. **KWin silently drops the tail of zero-delay typing bursts.** With the default
   `type_delay_ms = 0`, transcriptions were always complete in the logs, but the
   *typed output* randomly cut off after ~15–20 characters — race-dependent, so
   it looked like "audio clipping" or "the second recording fails". voxtype's
   own CONFIGURATION doc documents this for its `eitype` driver ("KWin can
   otherwise accept a zero-delay event burst while silently dropping the tail of
   a long dictation") — but the built-in 1 ms safety pacing is **eitype-only**,
   and on KDE the driver chain (`wtype` unavailable → `eitype` not installed →
   `ydotool`) fell through to an unpaced driver. Fix: `[output] type_delay_ms = 5`.
   Diagnosis tip: run the daemon as `voxtype -v daemon` — the debug log prints
   the exact `ydotool type --key-delay N …` invocation.
2. **The Menu key opens context menus.** If your PTT key reports as
   `KEY_COMPOSE` (kernel code 127 — e.g. the key between Right Ctrl and Fn on a
   Razer Ornata), XKB translates it to the `Menu` keysym and Qt apps pop a
   right-click menu on every press. Fix: a tiny **KWin script** registering a
   no-op global shortcut on `Menu` — KWin consumes the keystroke above every
   app, while voxtype reads the raw evdev code below KWin. Do **not** reach for
   an XKB remap (`ctrl:menu_rctrl`): it maps the key onto Right Ctrl (which you
   may use), only applies to XWayland apps when pushed live via `setxkbmap`, and
   on Plasma Wayland the KWin-side keymap needs a full re-login to pick it up.
3. **PipeWire auto-suspend eats the first words.** A USB mic idle-suspends after
   a few seconds; the resume latency after "record start" clips the opening of
   the utterance — *intermittently*, because a recently-used mic is still hot.
   Fix: a WirePlumber rule pinning `session.suspend-timeout-seconds = 0` on the
   dictation mic's node (script applies it; verify with `pactl list sources`).
4. **Not every key has a builtin name.** `key = "COMPOSE"` is rejected
   ("Unknown key name"). Raw kernel codes work with the `EVTEST_` prefix:
   `key = "EVTEST_127"`. Capture any key's code by reading 24-byte evdev
   records off its `/dev/input/event*` node (helper pattern in the write-up's
   companion skill; `evtest` works too).
5. **voxtype's evdev listener skips virtual keyboards** (anti-feedback by
   design) — you cannot trigger PTT with a synthesized keystroke. Test the
   pipeline headlessly with `voxtype record start` / `record stop` instead.
6. **v1.1.0 renamed the config key**: `[whisper] mode = "remote"` — `backend =`
   still parses but logs a deprecation warning.
7. **The OSD frontend needs `libgtk4-layer-shell.so.0`, not packaged on
   Kinoite.** Extract it from the Fedora rpm into `~/.local/lib` and wrap the
   `voxtype-osd-gtk4` binary with `LD_LIBRARY_PATH` (script does this).
   Symptom without it: OSD child crash-loops with exit 127.
8. **No rpm-ostree layering needed.** The 374 MB rpm bundles every GPU runtime
   for *local* inference; remote mode needs none of them — the 19 MB standalone
   `avx2` binary is the right install on an immutable OS.
9. **ydotool types raw US keycodes.** Fine on US layouts; non-US layouts garble
   (use voxtype's `eitype` or `dotool` drivers if that matters to you).
10. **HTTP plaintext to the ASR host is expected on a trusted LAN** — voxtype
    warns; keep the endpoint off the internet.

## Install

```bash
# Required: the WhisperX endpoint speaks OpenAI /v1/audio/transcriptions
export ASR_ENDPOINT="http://<your-whisperx-host>:10230"

# Optional overrides (defaults in the script header):
#   HOTKEY_EVDEV_CODE=127        # PTT key (127 = KEY_COMPOSE / Menu position)
#   TYPE_DELAY_MS=5              # KWin tail-drop pacing
#   MIC_NODE_PATTERN="usb-Shure" # PipeWire node regex for your mic

bash install-voxtype-remote.sh
```

The script is parameterized, fail-closed (SHA256-pinned binary download), needs
no sudo, and installs: voxtype + config, `ydotoold` as a systemd **user**
service (logind's ACL on `/dev/uinput` makes unprivileged uinput work — no
`input` group membership), the OSD frontend + layer-shell lib, the KWin
Menu-neutralizer script, and the WirePlumber mic no-suspend rule. A full
cleanup section prints at the end.

System requirements: KDE Plasma 6 Wayland, PipeWire, systemd user units,
`ydotool` package installed, glibc ≥ 2.39.

## Verify

The script ends with a synthetic end-to-end test (`espeak-ng` sample → remote
transcription → text). After install, hold the PTT key and say:
*"This is a test of the first statement"* — release, then immediately do it
again four more times. Five complete back-to-back dictations is the regression
test that caught gotcha #1.

## Credits

- **[peteonrails/voxtype](https://github.com/peteonrails/voxtype)** (MIT) — the dictation daemon; remote-whisper mode, OSD, spoken punctuation, the CONFIGURATION doc whose KWin warning pointed at the root cause.
- **[whisperx-asr-service](https://hub.docker.com/r/learnedmachine/whisperx-asr-service)** container (WhisperX by [m-bain](https://github.com/m-bain/whisperX)) — the transcription server; its OpenAI-compatible route is what makes this a zero-code integration.
- `ydotool`, `ydotool`'s uinput daemon, GTK4 layer-shell, KWin scripting APIs.

© 2026 Greg DeYoung — bazzite-customizations · MIT
