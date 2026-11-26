# Hermes KRunner Runner — `ai <question>` / `hr <task>`

The Omarchy "front door" feeling, KDE-native: Super+Space, ask a question or
fire an agent task, no terminal, no browser. Zero-compile Plasma 6 DBus
runner — no C++, no KDE SDK, nothing layered into the image.

**Status: v0.8.1 — foyer tree (UX-SPEC.md §L-16), single-runner mode, harness-gated, unit-tested.**

## What the prefixes do

| You type (Super+Space) | What happens |
|---|---|
| `ai <question>` | Enter on the row ASKS: background fetch from the fleet LiteLLM proxy (default `local-fast`). Answer pops as a desktop notification; retype the same query and the answer row appears inline in KRunner — Enter copies it. Match time does NO I/O (no request spam while typing). |
| `hr <task>` | Enter FIRES one unattended Hermes agent turn (`hermes -z`), notifies "task started", logs to `~/.cache/hermes-runner/task-<ts>.log`, and notifies with the cleaned tail when it ends. A running registry prevents double-fire; while running, the row shows elapsed time and Enter shows the log tail. |
| `ai` / `hr` (nothing after) | Lane help + (for `ai`) the 5 most recent answered questions as `recent:` rows — question as title, "ANSWER CACHED n AGO · ENTER COPIES" subtext. Enter copies the cached answer; the ↻ action re-asks. |
| `hermes` | All three syntax rows, including the dictation row. |

**Dictation (v0.2.2):** `ask hermes about X`, `tell hermes to Y` (also "the assistant", `ai:`/`hr:`/`question:`/`task:` prefixes) normalize into the lanes inside `route()` — what you see in the box is what was claimed. Purely local regex, idempotent, 26 fixture-tested. Ported from Omarchy Foyer's VoiceModel.

**Web fallback (v0.2.2):** every inline answer row is paired with a `Web search: <question>` sibling — Enter opens your default browser at `web_search_url` (default DuckDuckGo) with the original-case question. Fleet SearXNG works too: `--web-search-url http://192.168.1.249:8787/search?q=%s --web-search-name SEARXNG`. No sibling while fetching or on errors.

Errors are their own state: a failed ask shows a red row with a one-line humanized reason ("LiteLLM unreachable at …") and Enter retries it. Errors are never cached as answers.

**Handoffs (v0.3):** `<prefix> <query>` opens a fleet-scoped search in your browser — `gh` GitHub · `sea` fleet SearXNG · `el` Elastic docs (via site: search). Enter opens the URL with your original-case query. Bare prefix (`gh` alone) shows its help row; `hermes` lists all configured handoffs. Config: `"handoffs": [{prefix, label, url}]` — prefix 2–6 lowercase letters, label ≤24 chars, URL must be http(s) with exactly one `%s`, duplicates and lane prefixes (`ai`/`hr`/`hermes` — whatever yours are renamed to) are rejected at load; malformed entries are skipped with one journal line, never fatal. `map` was cut in UX review: generic web search is the native webshortcuts runner's job — this lane stays fleet-scoped. Jellyfin/Galaxy handoffs: verify the search URL first, then add to config.

**Model switch (v0.4):** `ai model` lists your configured aliases (`models` in config — default local-fast/local-heavy/local-fast-reason/cloud-dev) with the current one marked `CURRENT`; Enter on any other switches the ai lane to it and persists to config.json (unknown keys preserved). Case-insensitive; unknown names keep the ask row and add a `No such model` help row. Config write failure still switches for the session and says so.

**Adoption counters (v0.4):** every Enter-verb counts (asks, tasks, answer uses, error retries, handoff opens per prefix, web opens, recent copies, model switches, dictation folds) into `~/.cache/hermes-runner/stats.json` — counts only, never query text. `/usr/bin/python3 hermes_runner.py --stats` prints totals + per-day rollup (system python — the module imports dbus at top level); the two-week adoption review decides which lanes stay.

**SSH lane (v0.5):** `ssh <host>` connects straight from `~/.ssh/config` — Enter opens `konsole --hold -e ssh <name>` (window stays up after disconnect). Hosts are parsed at load (HUP reloads, like handoffs): `Host` groups share Hostname/Port/User, globs and `!negated` names are skipped, `Include` is followed one level (missing files silently skipped). Matching is typed-prefix filtering — exact > prefix > substring, cap 8 rows; `sshconf`/`sshd` are NOT claimed (first word must be exactly `ssh`). Subtext shows the real target `CONNECT root@10.0.0.9:2222 · ENTER OPENS TERMINAL`; original-case names keep their case in titles. Bare `ssh` shows a help row + the first 5 hosts; no match shows one `No host matches` row. Hosts are never copied into config.json. No tab completion exists in KRunner (runners can't rewrite the query box) — short multi-name aliases in `~/.ssh/config` (`Host aic aicube`) are the compensation.

**Snippets (v0.5):** `;` is an in-band snippet CRUD. `;sig` Enter copies snippet `sig`; row buttons COPY · SHOW · DELETE. `;sig Greg DeYoung` Enter saves it (retyping an existing name shows the copy row plus an `Overwrite` row below it — save-if-new is Highest, overwrite is deliberately lower). `;` alone lists all snippets (name in title, 80-char preview in subtext, cap 8 + a `+N more` pointer). Names: `a-z 0-9 -`, max 16, unique, validated as typed (`;Sig` is invalid, never silently lowered); `help` is reserved (`;help` = the index). Text: single line, ≤2000 chars — multi-line snippets stay config.json-only by design (`"snippets": [{name, text}]`). Delete is recoverable: the `snippet deleted` notification carries the full text for undo-by-copy. Saves/deletes persist via read-modify-write of config.json (unknown keys preserved) — on write failure the change stays in memory and the notification says so.

**Layered help (v0.5):** `hermes` (or bare `help`) is the index — one row per lane (ai · hr · dictation · ssh · snippets · model · each handoff · docs) with a drill hint in every subtext. `hermes ssh`, `hermes snippets`, `hermes model`, `hermes ai`, `hermes hr`, `hermes dictation`, `hermes handoffs` open short detail pages (≤6 rows): a syntax row, copy-action example rows (the COPY button puts the example on your clipboard), and a config pointer. `hermes docs` opens this README. Unknown lanes fall back to the index — the index IS the correction. Help rows are inert (`actions: []`) except the copy examples; help describes config, never edits it.

**App launcher (v0.7):** `apps` is a start-menu-style browse lane that mirrors Kickoff itself. Favorites are THE KDE menu favorites, read live from kactivitymanagerd (`ResourceLink`, read-only, 5 s TTL) — whatever you favorite/unfavorite in Kickoff appears/disappears here, in your order. Groupings are THE real XDG menu tree (`/etc/xdg/menus/applications.menu`: Accessories · Development · Education · Games · Graphics · Internet · Multimedia · Office · System Tools), with Include/And/Exclude rules honored and groups shown in menu order; unfiled apps are reachable via fuzzy search. Bare `apps`: anchor row → first 10 favorites (with a `+N MORE FAVORITES` drill row) → your hermes pins → most-used → category rows. Kickoff-favorite rows are launch-only (KDE's data is never written); hermes pins keep PIN/UNPIN. ↓ + Enter on a category row re-drives into it (`apps games`, multi-word works: `apps system tools`); `apps <words>` is AND-token fuzzy search; `apps pins` shows the favorites + pins blocks. Launch is by desktop-id via `kioclient exec` (flatpaks fall back to `gtk-launch`) — never Exec parsing, no shell. Uninstalled favorites are skipped exactly as Kickoff skips them. Apps no menu rule claims get a synthetic `More` group (`apps more`) so nothing is browse-orphaned. Favorite rows say `favorite · <group>`; pins say `pinned · <group>`. Results cache to `~/.cache/hermes-runner/apps.json` (v3). Bare app names stay with KRunner's native runner; apps literally *named* "apps" may render native groups above ours (Plasma's 1.0-tie prerogative). KRunner shows no runner buttons on an empty query, so the entry point is simply typing `apps`.

KRunner stays KRunner: apps, windows, calculator, unit conversion, timers and
file search remain native. This runner only adds the agent lanes — the
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
# Super+Space → "ai ping"
```

Rollback: `./uninstall.sh` (removes daemon/spec/unit, keeps config+cache).

## Verified

**2026-11-01 — v0.5.0 phase gates (unit + nested harness kr14 + live):**
105/105 tests (ssh parser incl. negation + one-level Include fixtures, ssh
lane ranking/claims/caps, snippets CRUD matrix incl. `;foo` unknown and
zero-snippet states, dispatch persistence incl. recoverable delete +
wire-garbage rejection, layered-help index/pages/fallback, bidirectional
reserved registry). Harness kr14 (nested Wayland, KRunner 6.31): wire
assertions for `ssh:` rows (group-shared `CONNECT root@10.0.0.9:2222`
subtext, exact-first-word claim), `;sig New Sig` copy+overwrite row pair,
9-row help index at literal rels .55→.30, double HUP reload confirmed in the
runner log; pixels confirmed for the SSH row and the full index (vision
lane rerouted to `local-agent` — MediaServer `local-vision` backend was
down at gate time). Live install: index/ssh/snippet/docs rows on the user
bus, journal clean.

**2026-10-31 — v0.4.0 phase gates (unit + nested harness kr13 + live):**
71/71 tests (normalize fixtures, handoff sanitize, model switch incl.
persist/preserve-unknown-keys, counters incl. day rollup + chmod 600 +
corrupt-file fresh start, dispatch stats, icon lint incl. `cpu`). Harness
kr13 on the isolated nested bus: `ai model` Match returns the four model
rows with `model-cur:` first; vision-confirmed rendering in real krunner.
Live: `enable`+`restart` install (the `enable --now` stale-process bug is
fixed — it bit twice on 2026-10-31), all six help rows + model rows on the
user bus, journal clean.

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

## v0.8 — foyer home (r4)

Super+Space now opens a Hermes-only menu with the full 15-row budget
(`querySingleRunner ss hermes "apps"` — see UX-SPEC.md §L-15 for the
Milou render-cap law and why plain `query()` re-imposes it).

- **Root = foyer tree**: `Favorites` branch (N apps · your KDE menu
  favorites) + category branches. No loose apps on the dropdown —
  every row fans out (v0.8.1 directive). The Apps anchor refreshes.
- **Category views are bounded**: anchor + 13 alphabetized apps +
  `SHOWING 13 OF N · TYPE TO FILTER` hint. KRunner cannot scroll —
  typing is the scroll. No more category walls.
- Deterministic ordering under the render cap (stepped relevances).
- Tests: 158 (incl. single-runner drill + leaked-thread race guard);
  harness apps8 40/40 checkpoints.

## v0.8.2 — the prime law (§L-17)

`querySingleRunner` alone is NOT enough on Plasma 6.7.5: once a session
has run any plain multi `query()` (Alt+Space, a stale cached bind), the
bare call silently falls back to multi mode — one Hermes row behind the
natives, single-runner chip still showing. Fixed by PRIMING with
`displaySingleRunner` (+0.4 s settle) before the query:

- **keys v5** — Super+Space Exec = prime + query (deterministic single
  mode even on a poisoned session)
- **apps-root anchor** — re-drive now primes; the anchor row is the
  logout-free bridge out of a stale multi-mode popup
- drills stay unprimed (already single; priming would flash the field)
- harness apps13 gate: session POISONED with a plain query before the
  bind replay; single mode proven at the wire (zero Match calls to
  sibling runners) — `CKPT-MENU-SINGLE`

159 tests (new: primed anchor Run asserts display+query pair).

## v0.9.0 — r6 foyer parity (§L-18)

The root dropdown is now Foyer's top level: anchor **Apps** +
five branches — **Apps · Settings · System · Update · About** — and
each fans out like Foyer does. The r5 app tree (Favorites branch +
categories) lives behind the Apps branch (`apps browse`).

- **Settings** — KCM fan-out from a cached `kcms.json` scan (TTL 1 h,
  never fatal); anchor shows computed `N MODULES · TYPE LETTERS TO
  FILTER`; 13 rows + SHOWING footer under the 15-row law; rows launch
  via kioclient by desktop-id
- **System** — Lock / Sleep / Log Out / Reboot / Shut Down; anchor
  warns `NO CONFIRMATION DIALOG`; destructive rows carry `CLOSES OPEN
  APPS` (the subtext IS the consent — KRunner has no dialog)
- **Update** — runs `ujust update` in Konsole (Bazzite-native)
- **About** — system summary to clipboard + notification
- **Type-to-filter**: a single token that prefix-matches a branch name
  filters the root (`apps set` → Settings); `apps settings <letters>`
  filters KCMs; `apps system lock` filters power rows; empty drills
  fall through to the normal category/app search (`apps system tools`
  is still the System Tools category)
- **Harness safety**: power/update actions stub under
  `harness_mode: true` — the gate runs on the live host and must
  never reboot it (`CKPT-R6-POWER-STUB`, `CKPT-R6-HOST-SURVIVED`)
- stats: settings_opens, settings_launches, system_opens,
  power_actions, update_runs, about_copies

176 tests; harness apps14 gate adds r6 branch drills + stub-safety
checkpoints under poison.
