# Hermes KRunner Runner — `ai <question>` / `hr <task>`

The Omarchy "front door" feeling, KDE-native: Alt+Space, ask a question or
fire an agent task, no terminal, no browser. Zero-compile Plasma 6 DBus
runner — no C++, no KDE SDK, nothing layered into the image.

**Status: code-complete + live-verified against the session bus (not yet
installed as a KRunner plugin — install is a deliberate, listed step).**

## What the two prefixes do

| You type (Alt+Space) | What happens |
|---|---|
| `ai what is the fleet LiteLLM alias for GLM-5.3` | Question goes to the fleet LiteLLM proxy (default model `local-fast`). Answer pops as a desktop notification; retype/re-match the same query and the answer row appears inline in KRunner. Enter copies it. |
| `hr check jellyfin service health and notify me` | Fires one unattended Hermes agent turn (`hermes -z`), logs to `~/.cache/hermes-runner/task-<ts>.log`, and notifies with the tail of the result when the turn ends. |
| `hermes` | Shows the two syntax rows. |

KRunner stays KRunner: apps, windows, calculator, unit conversion, timers and
file search remain native. This runner only adds the two agent lanes — the
parts of Omarchy's Foyer that have no KDE equivalent.

## How it works

```
KRunner ──org.kde.krunner1──▶ hermes_runner.py (systemd user service)
   Match(s) → a(sssuda{sv})      ├─ 'ai': background thread → LiteLLM /chat/completions
   Run(ss)                       │        answer → notification + bounded cache →
   Actions() → a(sss)            │        inline on the next Match of the same query
                                 └─ 'hr': Popen(hermes -z) → watcher thread → notification
```

- Interface signatures taken from the live Plasma 6.7.5 session
  (`busctl introspect org.kde.KWin /WindowsRunner`, 2026-10-26) —
  `Match(s)→a(sssuda{sv})`, `Run(ss)`, `Actions()→a(sss)`.
- Runtime deps: `python3-dbus` + `python3-gobject` (both in the Bazzite base
  image) + `notify-send`. No pip, no venv, no sudo.
- Discovered via `~/.local/share/krunner/dbusplugins/org.kde.runners.hermes.desktop`
  (`X-Plasma-API=DBus`, `X-Plasma-DBusRunner-Service/Path` — same contract as
  the shipped baloo/KWin runners on this host).

## Config — `~/.config/hermes-runner/config.json`

Copy `config.json.example`. Fields: `answer_prefix`/`task_prefix`, `litellm.base_url`,
`litellm.model`, `litellm.timeout_s`, `api_key_env` / `api_key_file` (parsed
at runtime; never hardcoded — see below), `max_answer_chars`, `copy_answers`,
`notify` (set false for headless testing), `notify_icon`.
Reload without restarting: `systemctl --user kill -s HUP hermes-runner`.

## Install (when at the tower)

```
./install.sh --litellm-url http://192.168.1.243:4000/v1 --model local-fast \
             --api-key-env ZHW_PROXY_API_KEY --api-key-file ~/.hermes/secrets/infra.env
systemctl --user restart plasma-krunner.service
# Alt+Space → "ai ping"
```

Rollback: `./uninstall.sh` (removes daemon/spec/unit, keeps config+cache).

## Verified (2026-10-26, live session bus — daemon run standalone, KRunner unaware)

- Bus name `org.kde.runners.hermes` owned; introspection returns the exact
  krunner1 signatures (`Match s → a(sssuda{sv})`, `Run ss`, `Actions → a(sss)`).
- `Match("hermes")` → two syntax rows; `Match("ai ")` → help row;
  `Match("hr check the nas")` → task row. All non-blocking (<5 ms).
- `Match("ai ping")` → async fetch against fleet LiteLLM `local-fast` →
  notification → re-Match shows `answer:ping "Pong!"` inline (multiLine).
- `Match("ai say hello")` → `"Hello!"` cached; `Run("answer:say hello")`
  notify path clean (clipboard lane exercised with `copy_answers:true` on
  install day via Klipper DBus).
- `Run("task:reply with exactly: TASK-LANE-OK")` → real `hermes -z` turn;
  log contains `TASK-LANE-OK`; completion notification fired.
- Test rig leaves no trace: standalone process (no desktop file, no unit
  enabled), killed by PID after the run; only `~/.cache/hermes-runner/*.log`
  and `/tmp/hr-test/` remain.

## Design notes / gotchas folded in

- **Match must never block.** KRunner calls it synchronously on typing; the
  LLM fetch runs in a daemon thread and the answer surfaces via notification
  + cache. KRunner only re-Matches on text change, so the inline answer
  appears on retype — documented in the subtext ("answer arrives as a
  notification; retypes show it inline").
- **No secrets in code or repo.** Key resolution: env var first, then a
  `KEY=value` local file. The repo's example points at `LITELLM_API_KEY`;
  fleet install passes the real env/file names as install args.
- **pkill -f self-match.** Tearing the test daemon down with `pkill -f
  hermes_runner.py` killed the invoking shell instead (the plasmoid skill
  documents this exact trap). Track PIDs/session ids, kill by those.
- Kill switch: remove `hermes` from `[Plugins]` in `~/.config/krunnerrc`, or
  uninstall outright.
