# Hermes KRunner Runner — `ai <question>` / `hr <task>`

The Omarchy "front door" feeling, KDE-native: Alt+Space, ask a question or
fire an agent task, no terminal, no browser. Zero-compile Plasma 6 DBus
runner — no C++, no KDE SDK, nothing layered into the image.

**Status: v0.2 — UX-reviewed (UX-SPEC.md), harness-gated, unit-tested.**

## What the two prefixes do

| You type (Alt+Space) | What happens |
|---|---|
| `ai <question>` | Enter on the row ASKS: background fetch from the fleet LiteLLM proxy (default `local-fast`). Answer pops as a desktop notification; retype the same query and the answer row appears inline in KRunner — Enter copies it. Match time does NO I/O (no request spam while typing). |
| `hr <task>` | Enter FIRES one unattended Hermes agent turn (`hermes -z`), notifies "task started", logs to `~/.cache/hermes-runner/task-<ts>.log`, and notifies with the cleaned tail when it ends. A running registry prevents double-fire; while running, the row shows elapsed time and Enter shows the log tail. |
| `ai` / `hr` (nothing after) | Lane help + (for `ai`) the 5 most recent answered questions as `recent:` rows — question as title, "ANSWER CACHED n AGO · ENTER COPIES" subtext. Enter copies the cached answer; the ↻ action re-asks. |
| `hermes` | All three syntax rows, including the dictation row. |

**Dictation (v0.2.2):** `ask hermes about X`, `tell hermes to Y` (also "the assistant", `ai:`/`hr:`/`question:`/`task:` prefixes) normalize into the lanes inside `route()` — what you see in the box is what was claimed. Purely local regex, idempotent, 26 fixture-tested. Ported from Omarchy Foyer's VoiceModel.

**Web fallback (v0.2.2):** every inline answer row is paired with a `Web search: <question>` sibling — Enter opens your default browser at `web_search_url` (default DuckDuckGo) with the original-case question. Fleet SearXNG works too: `--web-search-url http://192.168.1.249:8787/search?q=%s --web-search-name SEARXNG`. No sibling while fetching or on errors.

Errors are their own state: a failed ask shows a red row with a one-line humanized reason ("LiteLLM unreachable at …") and Enter retries it. Errors are never cached as answers.

KRunner stays KRunner: apps, windows, calculator, unit conversion, timers and
file search remain native. This runner only adds the two agent lanes — the
parts of Omarchy's Foyer that have no KDE equivalent.

## How it works

```
KRunner ──org.kde.krunner1──▶ hermes_runner.py (systemd user service)
   Match(s) → a(sssida{sv})      ├─ 'ai': Run → background thread → LiteLLM /chat/completions
   Run(ss)                       │        answer/error → notification + typed cache →
   Actions() → a(sss)            │        inline on the next Match of the same query
   SetActivationToken(s)         └─ 'hr': Popen(hermes -z) → watcher → notification
```

- Wire signatures per the installed KRunner 6.31 interface: field 4 is
  **int32** CategoryRelevance. KWin's introspection XML advertises 'u' but
  marshals C++ int as 'i' — a daemon trusting the XML gets every reply
  rejected with InvalidSignature (harness-caught 2026-10-30). Trust the
  caller's demarshal expectation, not the provider's self-description.
- Runtime deps: `python3-dbus` + `python3-gobject` (both in the Bazzite base
  image) + `notify-send`. No pip, no venv, no sudo.
- Discovered via `~/.local/share/krunner/dbusplugins/org.kde.runners.hermes.desktop`
  (`X-Plasma-API=DBus`, `X-Plasma-DBusRunner-Service/Path` — same contract as
  the shipped baloo/KWin runners on this host).

## Config — `~/.config/hermes-runner/config.json`

Copy `config.json.example`. Fields: `answer_prefix`/`task_prefix`, `litellm.base_url`,
`litellm.model`, `litellm.timeout_s`, `api_key_env` / `api_key_file` (parsed
at runtime; never hardcoded — see below), `max_answer_chars`, `copy_answers`,
`notify` (set false for headless testing), `web_search_url` (must contain
exactly one `%s`; default DuckDuckGo), `web_search_name` (≤12 chars, shown in
the sibling row subtext).
Reload without restarting: `systemctl --user kill -s HUP hermes-runner`.

## Install (when at the tower)

```
./install.sh --litellm-url http://192.168.1.243:4000/v1 --model local-fast \
             --api-key-env ZHW_PROXY_API_KEY --api-key-file ~/.hermes/secrets/infra.env
systemctl --user restart plasma-krunner.service
# Alt+Space → "ai ping"
```

Rollback: `./uninstall.sh` (removes daemon/spec/unit, keeps config+cache).

## Verified

**2026-10-30 — harness gate (nested Wayland session, krunner 6.31 live):**
26/26 unit tests (`test/test_runner.py` — routing matrix, humanizer, tail
cleaner, typed cache, enum bounds); daemon on the nested bus: help rows,
cold ask with zero Match-time I/O, `Run` → real LiteLLM fetch → notification
→ cached inline answer with per-row action icons, error lane via dead-port
daemon (humanized row, Enter-retry, never cached as answer), `Actions()`
triples, `SetActivationToken` no-op; real krunner discovered us from
`~/.local/share/krunner/dbusplugins` and rendered both states (pixel-checked).
The 2026-10-26 "verified" note below was the trap this gate caught:

- 2026-10-26 checks trusted introspection XML (`a(sssuda{sv})`) and were
  daemon-only — krunner was never an actual consumer, so the uint32/int32
  rejection was invisible until the 2026-10-30 harness run.

## Design notes / gotchas folded in

- **Match must never block — and never do I/O.** KRunner calls it
  synchronously on every keystroke; the fetch fires only on Run (Enter).
  KRunner only re-Matches on text change, so the inline answer appears on
  retype — documented in the subtext.
- **No secrets in code or repo.** Key resolution: env var first, then a
  `KEY=value` local file. The repo's example points at `LITELLM_API_KEY`;
  fleet install passes the real env/file names as install args.
- **pkill -f self-match.** Tearing the test daemon down with `pkill -f
  hermes_runner.py` killed the invoking shell instead (the plasmoid skill
  documents this exact trap). Track PIDs/session ids, kill by those.
- Kill switch: remove `hermes` from `[Plugins]` in `~/.config/krunnerrc`, or
  uninstall outright.
