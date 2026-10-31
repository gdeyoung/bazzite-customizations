# krunner-hermes — UX design spec (post-review, 2026-10-30)

Reviewer: UX pass per fleet rule. Every platform fact below was verified against the
**exact host stack** (Plasma 6.7.5 / kf6-krunner 6.31.0), not assumed:

- Canonical interface XML `src/data/org.kde.krunner1.xml` @ KRunner v6.31.0:
  `Match(s) → a(sssida{sv})` — **field 4 is INT32**, not uint32.
- `src/dbusutils_p.h` @ v6.31.0: match struct = (id, text, iconName,
  categoryRelevance, relevance, properties); Actions triple marshals as
  **(id, text, iconName)**.
- `src/dbusrunner.cpp` @ master: `a{sv}` keys are all-lowercase
  `subtext`, `multiline`, `category`, `urls`, `actions`, `icon-data`;
  per-match property `actions` (list of action IDs) filters the runner-global
  Actions() list per row; **empty list hides all actions; omitting the property
  shows all**.
- `src/querymatch.h` @ v6.31.0: `CategoryRelevance { Lowest=0, Low=30,
  Moderate=50, High=70, Highest=100 }`. Field 4 of the match struct feeds
  `setCategoryRelevance` — it is **not** `QueryMatch::Type` (Plasma 5 semantics;
  the code comment in hermes_runner.py is outdated).
- Live session bus: KWin WindowsRunner emits `30` (= Low), relevance 0.7 —
  calibration point for ranking.
- All icons spec'd below exist in Breeze on this host (checked on disk).

---

## A. Critique (prioritized, with code evidence)

### P0 — breaks or actively wrong

**P0-1. Wire-format mismatch: KRunner will reject every match.**
`hermes_runner.py:223` declares `out_signature="a(sssuda{sv})"` and packs
`dbus.UInt32(mtype)`. The krunner1 interface (installed 6.31.0 XML and the
Qt demarshaler) expects `a(sssida{sv})` with **Int32**. Qt validates reply
signatures strictly → `QDBusPendingReply` is invalid → the runner logs an
error and renders nothing. The 2026-10-26 "live-verified" pass used
busctl/gdbus (signature-agnostic); a Qt consumer was never exercised
(README: "not yet installed as a KRunner plugin"). **As shipped, the widget
does not work.** Fix in §B-1. The module docstring (line 7) also documents
the wrong signature.

**P0-2. Fetch fires at Match time → per-keystroke LLM calls + notification spam.**
`Match()` line 257 calls `fetch_answer(question)` for every distinct query
text. Typing `ai what is the fleet LiteLLM alias` (~33 chars) issues ~25 HTTP
requests — one per intermediate prefix — each answering a *different partial
question*, each completion firing a desktop notification (line 180). Cost,
wrong answers to prefixes, and notification pile-up. Fix (§B-2): **move the
fetch to `Run()` (Enter)**. Match becomes pure display. This simultaneously
fixes known issue (b): Enter on the ask row is no longer a silent no-op —
Enter is the verb "ask", which is the KRunner contract for every other row.
Retype-to-see-inline still works (the cache is filled on Enter).

**P0-3. Errors are cached as answers → poisoned cache, misleading copy, no retry.**
Lines 181–184: on exception the daemon does `cache.put(qh, "(ask failed: {e}")`.
A retype then renders the raw exception as the *answer title* with subtext
"Enter: copy · from LiteLLM …" (lines 250–255) — Enter copies an error string —
and because the cache is warm, the query can never refetch until eviction or
restart. A transient network blip permanently poisons that question. Fix
(§B-3): typed cache entries (`answer` | `error`), distinct error row state,
Enter-on-error = retry.

### P1 — visible defects once it renders

**P1-1. `multiLine` property key is wrong case → silently ignored.**
Line 235 sends `props["multiLine"]`; dbusrunner.cpp reads `multiline`
(all-lowercase). Cached answers render as one elided line today. Fix §B-1.

**P1-2. Category-relevance ints are out-of-enum / mis-tuned.**
`T_EXACT, T_INFO, T_HELPER = 1, 70, 90` (line 48). Under the real semantics
(CategoryRelevance): 1 < Lowest → bottom tier for the *primary actionable row*;
90 is unmapped (between High 70 and Highest 100); and help rows (90) currently
outrank the ask row's tier. Use 100/70/50 per §B-2 state matrix.

**P1-3. `hr <task>` loses case through the id round-trip.**
Match stores `task:{task.lower()}` (line 268); Run fires
`mid[len("task:"):]` (line 298) → `hermes -z` receives the lowercased task.
Corrupts any case-sensitive content (hostnames, paths, flags). Fix §B-4
(id→payload map preserving original case, same fix used for ask rows).

**P1-4. `hr ` (empty task) returns zero rows** (lines 265–272) while `ai `
shows a help row — known issue (a). Fix: symmetric help row (§B-2).

**P1-5. Task watcher reports "done" for tasks that are still running, with raw log garbage.**
`watch()` (lines 205–218): the 900×1s loop exits either on process death *or*
on cap; both paths notify "Hermes task done". A 15-min cap hit notifies
"done" while `hermes -z` is mid-flight. Body is `logf.read_text()[-400:]` —
ANSI escapes and `\r` progress lines render as garbage in a notification.
Fix §B-5: distinguish alive-at-cap, strip ANSI/CR, collapse blank runs.

**P1-6. No double-fire guard on the task lane.**
Two Enters (or Enter + retype + Enter) fire two concurrent unattended agent
turns — real side effects, two completion notifications. The `fetching` set
guards only the ai lane. Fix §B-6: per-task-key running registry + running
row state.

**P1-7. Raw exception strings in notifications** (line 184, known issue d).
urllib exceptions are multi-line, leak URLs, and read as stack traces.
Fix §B-7 humanizer.

**P1-8. Actions() returns `[]` while the .desktop declares
`X-Plasma-Request-Actions-Once=true`** (known issue e). Dead declaration.
Fix: implement — with the **(id, text, icon)** tuple order and per-row
`actions` filtering (§B-8). Note the parent-task brief assumed "(name+icon+id)"
— that order would produce buttons with icon text as labels.

### P2 — polish

- **P2-1.** Model name in the cached-answer subtext (known issue c) — wasted
  space on the row where it's least useful. Move model identity to help-row
  subtext only; show **cache age** on answer rows instead (more decision-useful).
- **P2-2.** Notification copy is inconsistent: "Hermes: {q}" / "Hermes: ask
  failed — {q}" / "Hermes task failed" / "Hermes task done: {q}" — four
  grammars, one icon (`help-browser`) for all states incl. errors. Unify (§B-9).
- **P2-3.** No feedback on `hr` Enter: up to 15 min of silence before the first
  signal. Add a task-started notification with the log path (§B-9).
- **P2-4.** Bare `ai`/`hr` (no space) shows *both* help rows (line 274),
  while `ai ` shows one different row. Unify (§B-2).
- **P2-5.** Unbounded answer text as row title (up to 700 chars) and
  notification truncation at an arbitrary char with no marker. Cap the row
  title; mark truncation (§B-2, §B-9).
- **P2-6.** Default `litellm.base_url` is `localhost:4000` — LiteLLM lives on
  AICube (192.168.1.243:4000) in this fleet; only correct because install.sh
  overrides it. Make the example/fleet config the default-facing story, keep
  localhost for dev.

---

## B. Redesign spec (implement verbatim)

### B-1. Wire format corrections (all P0-1/P1-1)

1. `Match` annotation → `out_signature="a(sssida{sv})"`; pack
   `dbus.Int32(mtype)` for field 4. Fix the module docstring (line 7) to
   `Match(s) -> a(sssuda{sv})` → `a(sssida{sv})`.
2. Property keys: `subtext`, `multiline` (**lowercase**), plus per-row
   `actions` (list of string action IDs) where spec'd.
3. Keep `(id, text, icon, catrel, relevance, props)` field order (already
   correct).
4. Optional 2-line addition: a no-op `SetActivationToken(s)` method —
   Wayland KRunner fire-and-forgets it before Run; implementing silences an
   error reply. Not required.
5. Do **not** implement `Teardown`/`Config` (DBus2 lifecycle; missing methods
   are ignored).

### B-2. Match() state matrix

`q` = stripped query; `qh` = `q.lower()` (cache/registry key); `{age}` helper:
`<60s → "12s"`, `<60m → "4m"`, else `"2h"`. CategoryRelevance ints per
v6.31.0 enum. All rows are the *only* row for their query, so ordering across
rows matters only where noted.

| # | State (trigger) | id | title | subtext | icon | CR | rel | props |
|---|---|---|---|---|---|---|---|---|
| 1 | `ai` or `ai ` (empty q) | `ai-help` | `Ask Hermes — type a question after 'ai'` | `ONE-SHOT ANSWER · NOTIFIED, THEN CACHED INLINE · {model} VIA LITELM` | `help-browser` | 50 | 0.6 | — |
| 2 | `ai <q>`, no cache, not in flight | `ask:{qh}` | `Ask Hermes: {q}` | `ENTER ASKS · ANSWER NOTIFIES · RETYPE TO READ INLINE` | `help-browser` | 100 | 1.0 | `actions: []` |
| 3 | `ai <q>`, fetch in flight (`qh ∈ fetching`) | `asking:{qh}` | `Asking… {q}` | `IN FLIGHT · {age} ELAPSED · ENTER SHOWS STATUS` | `clock` | 70 | 0.9 | `actions: []` |
| 4 | `ai <q>`, cached answer | `answer:{qh}` | `{answer, trimmed to 240 chars + "…" if longer}` | `CACHED {age} AGO · ENTER COPIES` | `help-browser` | 70 | 0.95 | `multiline: true`, `actions: ["copy","askagain","reshow"]` |
| 5 | `ai <q>`, cached error | `error:{qh}` | `Ask failed — {q}` | `{humanized reason, ≤80 chars} · ENTER RETRIES` | `dialog-error` | 70 | 0.95 | `actions: ["askagain"]` |
| 6 | `hr` or `hr ` (empty task) | `hr-help` | `Run Hermes — type the task after 'hr'` | `ONE UNATTENDED hermes -z TURN · NOTIFIED WHEN DONE` | `system-run` | 50 | 0.6 | — |
| 7 | `hr <task>`, not running | `task:{qh}` | `Run Hermes: {task}` | `ENTER FIRES hermes -z · RESULT NOTIFIES · LOG IN ~/.cache/hermes-runner` | `system-run` | 100 | 1.0 | `actions: []` |
| 8 | `hr <task>`, that task running | `taskrun:{qh}` | `Running: {task}` | `RUNNING · {age} ELAPSED · ENTER SHOWS TAIL` | `chronometer` | 70 | 0.95 | `actions: []` |
| 9 | `hermes` / `hermes help` | `help-ai` | `Hermes: ask with 'ai <question>'` | `NOTIFIED ANSWER, THEN CACHED INLINE · {model} VIA LITELM` | `help-browser` | 50 | 0.55 | — |
| 10 | (same, second row) | `help-hr` | `Hermes: run a task with 'hr <task>'` | `UNATTENDED AGENT TURN · NOTIFIED WHEN DONE` | `system-run` | 50 | 0.5 | — |

Rules:
- **Match never performs I/O.** No fetch, no spawn (P0-2). The `fetching`
  set is only consulted (state 3), populated/emptied by the worker thread.
- Bare `ai` and bare `hr` (no trailing space) render states 1 / 6
  respectively — not the two-row pair (P2-4). The pair (states 9–10) is only
  for `hermes` / `hermes help`.
- State 4 vs 5 decided by the typed cache (B-3); state 3 takes precedence
  over 2 only when `qh ∈ fetching` **and** no cached entry exists yet.
- State 7 fires even while a *different* task is running (concurrency across
  distinct tasks is allowed; see risks).
- Every non-applicable row carries `actions: []` explicitly — omitting the
  property shows **all** actions on that row (documented DBus behavior).

### B-3. Typed cache (P0-3)

`AnswerCache` values become `(kind, text, ts)` with `kind ∈ {"answer","error"}`.
- Success: `put(qh, "answer", answer, now)`; cache stores the **full** answer
  (title trim is display-only).
- Failure: `put(qh, "error", humanized_reason, now)` — never the raw
  exception (raw goes to stderr log only).
- `Run` on `error:{qh}`: drop the entry, start a fetch (goes through the same
  in-flight dedupe), KRunner closes, answer/error notifies as usual.

### B-4. id→payload map (P1-3)

`self.payload = {}` filled in `Match()` at row-creation time:
`self.payload[f"task:{qh}"] = task` (original case), same for ask rows.
`Run()` resolves the original string from the map; the lowercased id is used
only as the lookup key. Bounded: when `len > 256`, drop oldest (dict FIFO).
Populating in `Match()` is safe: DBus dispatch is single-threaded on the GLib
main loop.

### B-5. Task watcher (P1-5)

```
ansi = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
def clean_tail(path):
    t = ansi.sub('', path.read_text(errors='replace'))
    t = t.replace('\r', '\n')
    t = re.sub(r'\n{3,}', '\n\n', t).strip()
    return t[-400:]
```
Watcher loop: poll 1 s. On process death → "task done" notification (B-9).
At the 900 s cap, if still alive → **"still running"** notification (B-9),
then keep polling (up to 60 more minutes) and send "task done" on eventual
death; remove the task from the running registry only on death. Watcher
exceptions → "task failed" (B-9), registry cleared.

### B-6. Running-task registry (P1-6)

`self.running_tasks = {}` (`qh → {"pid","start","logf"}`), guarded like
`fetching`. `Run` on `task:{qh}`: if `qh ∈ running_tasks` → re-notify the
"task running" body and return (no second spawn). Populate in `fire_task`,
clear in the watcher on death/failure. Match state 8 reads this dict.

### B-7. Error humanizer (P1-7)

```
def humanize(exc, conf) -> str
  HTTPError          → f"LiteLLM HTTP {e.code}: {first line of body, ≤80}"
  URLError/timeout   → f"timeout after {conf timeout_s}s — LiteLLM {base_url}"
  ConnectionRefused  → f"LiteLLM unreachable at {base_url}"
  JSONDecodeError    → "LiteLLM returned malformed JSON"
  else               → first line of str(e), ≤120 chars
```
`hermes executable not found` keeps its current message shape.

### B-8. Actions() (P1-8)

Constant list, **(id, text, icon)** order, uppercase labels per fleet
micro-caps idiom:

```python
return [
    ("copy",     "COPY",       "edit-copy"),
    ("askagain", "ASK AGAIN",  "view-refresh"),
    ("reshow",   "SHOW AGAIN", "help-browser"),
]
```

Per-row visibility comes from the `actions` property in the state matrix.
Keep `X-Plasma-Request-Actions-Once=true` (list is constant; fetched once).

**Run(id, actionId) dispatch table** (empty actionId = primary/Enter):

| id prefix | actionId `""` | `copy` | `askagain` | `reshow` |
|---|---|---|---|---|
| `ask:` | start fetch of original-case q (via payload map) | copy q text | start fetch | notify cached answer if any |
| `asking:` | notify "still asking" status (B-9) | copy q text | no-op (already in flight) | — |
| `answer:` | copy answer + "copied" notify; fallback: re-notify answer | copy answer | drop cache entry, refetch | re-notify full answer |
| `error:` | drop entry, refetch | copy q text | drop entry, refetch | — |
| `task:` | fire_task (case-preserved) | copy task text | re-fire task | — |
| `taskrun:` | notify tail-so-far (B-9 "running" body) | copy task text | — | — |
| `ai-help`/`hr-help`/`help-*` | no-op (help rows) | — | — | — |

Clipboard via the existing Klipper DBus call; on failure fall back to
re-notify of the payload.

### B-9. Notification copy templates (P2-2/P2-3)

App name `-a Hermes` everywhere; per-state icon; urgency via `notify-send -u`.

| Event | summary | body | icon | urgency |
|---|---|---|---|---|
| Answer arrived | `Hermes · {q ≤60}` | `{answer, ≤700 chars, + "…" if cut}` | `help-browser` | normal |
| Ask failed | `Hermes · ask failed` | `{q}\n{humanized reason}\nEnter on the error row retries.` | `dialog-error` | normal |
| Copied | `Hermes · copied` | `Answer is on the clipboard.` | `edit-copy` | low |
| Still asking (Enter on state 3) | `Hermes · still asking` | `{q}\n{age} elapsed · answer notifies when done` | `clock` | low |
| Task started | `Hermes · task started` | `{task}\nlog: {logf path}` | `system-run` | low |
| Task done | `Hermes · task done` | `{clean_tail, ≤400}` | `task-complete` | normal |
| Task still running at cap | `Hermes · still running` | `15 min watch cap hit; hermes -z continues.\nlog: {logf}\n\n{clean_tail}` | `clock` | normal |
| Task failed | `Hermes · task failed` | `{task}\n{reason}` | `dialog-error` | critical |
| Task already running (2nd Enter) | `Hermes · already running` | `{task}\nstarted {age} ago · log: {logf}` | `chronometer` | low |

Tone-accenting is carried by icon + urgency (task-complete / dialog-error /
critical) — color is not a lever KRunner/notify-send gives us.

### B-10. .desktop and README

- `org.kde.runners.hermes.desktop`: no structural change needed; syntaxes and
  descriptions stay (count and order match). Keep
  `X-Plasma-Request-Actions-Once=true`.
- README: correct the signature line (`a(sssida{sv})`); replace the
  "Verified" claims that used the `u` signature; document Enter-to-ask (the
  old text says answers fire while typing); document the new states and
  actions.

---

## C. Prefix ergonomics verdict

**Keep `ai` / `hr`.** Reasons:
- Two keystrokes to a lane, space, then free text — the cheapest discoverable
  grammar KRunner offers; syntaxes (`ai :q:`, `hr :q:`, `hermes`) surface in
  KRunner's config UI for discovery.
- No collisions on this host: no installed runner (KWin windows, baloo,
  calculator, appstream, kate docs, yafti, bazaar) claims `ai ` / `hr `
  prefixes (verified: zero syntax declarations match; windows runner
  free-text matches titles, not prefixes).
- Both prefixes are user-configurable already (`answer_prefix`/`task_prefix`).
- Rejected alternatives: single `hermes <verb>` grammar (5 chars + a keyword
  before any content — worse), and bare free-text intent detection (would
  race every other runner and fire LLM calls on typos).

One idiom fix included in B-2: bare `ai` / `hr` now route to their own lane
help row instead of the generic pair — the prefix teaches its lane.

## D. Risks / edge cases

1. **Long answers in a one-line row** — mitigated by real `multiline`
   (lowercase key) + 240-char title trim + full text via Enter-to-copy and
   SHOW AGAIN. KRunner wraps multiline rows but caps row height; the
   notification remains the reading surface.
2. **Notification truncation** — 700-char body cap with explicit "…" marker;
   copied-by-Enter is always the full answer.
3. **Model latency UX** — local-fast is typically seconds, timeout 45 s.
   Between Enter and the answer there is no interim signal (accepted: a
   transient "asking…" notification would be replace-only noise; retype
   shows state 3 with elapsed time if the user checks). If this bothers in
   practice, revisit with `notify-send -r` replace-id (server support
   varies) — do not add without testing.
4. **Retype-to-see-inline discoverability** — now stated on the ask row
   itself ("RETYPE TO READ INLINE") and in help rows; KRunner cannot
   refresh a row in place (platform constraint).
5. **Concurrent distinct tasks** — allowed by design (states 7/8); each
   spawns a full `hermes -z` turn and they contend for model lanes. If this
   ever bites, add a `max_concurrent_tasks` config gate; not spec'd now.
6. **Enter on help rows is a no-op** — KRunner cannot rewrite the query from
   `Run()`, so help rows can't "insert" their prefix. Accepted; the titles
   carry the syntax.
7. **Cache has no TTL** — age is displayed; ASK AGAIN force-refreshes. Do
   not add silent expiry (an old-but-visible answer beats a surprising
   refetch).
8. **`fetching` set vs daemon restart** — in-flight state is memory-only;
   after a HUP/restart the row reverts to state 2. Fine.
9. **KRunner id mangling** — verified safe: dbusrunner strips the
   `hermes_` prefix before calling `Run`, so ids arrive as sent (ids
   containing `_` after the first char are unaffected).
10. **Default base_url** points at localhost — dev-only default; the fleet
    install path passes `--litellm-url` (P2-6 doc note).

## E. Acceptance tests (all doable without KRunner rendering)

1. `busctl --user introspect org.kde.runners.hermes /hermes` shows
   `Match` out = `a(sssida{sv})`.
2. `Match("ai ")` → one row, CR int32 50. `Match("hr")`/`Match("hr ")` →
   help row (symmetry).
3. `Match("ai ping")` fires **no** HTTP request (log silent, cache empty);
   `Run("ask:ping", "")` fires it; notification arrives; `Match("ai ping")`
   now returns state 4 with `multiline=true`, lowercase keys only.
4. Kill/point LiteLLM at a dead port → `Run` → error notification is
   humanized; `Match("ai ping")` returns state 5 (`dialog-error`);
   `Run("error:ping","")` refetches.
5. `Match("hr Check Jellyfin NOW")` → `Run` → spawned `hermes -z` argv
   preserves case (verify in task log / `ps`).
6. Immediate second `Run` of the same task → "already running"
   notification; `Match` shows state 8.
7. `Actions()` returns exactly B-8's three triples in (id, text, icon)
   order; state-2 row props include `actions: []`.
8. Signatures: full introspection of the object matches krunner1
   (Match/Run/Actions + optional SetActivationToken).

---

## F. v2 additions — foyer-informed improvements (2026-10-31, Phase 0 draft)

Source review: `omarchy-foyer` (Omarchy original, full clone audited). Admission
bar held: nothing KRunner already owns natively. Baseline measured same day:
5 real `ai` questions via local-fast → **min 0.25s · median 0.63s · max 0.79s**
(well inside the 8s p95 target). Known non-goal: model answered one
fleet-specific question wrong (`o1` for `local-heavy`) — knowledge quality is a
model/prompt issue, not a runner mechanic; revisit only if counters show it bites.

### F-1. Dictation normalization (Phase 1a) — voice-native lanes

VoxType dictation lands whole phrases in the box; today they miss the lanes.
`normalize(query)` runs at the top of `route()` AND in `Run()` before id lookup
(the id embeds the normalized key). Semantics ported from foyer VoiceModel,
lane-adapted:

- `^(?:ask|question)\s+(?:the\s+)?(?:ai|assistant|hermes|computer)\s+(?:about\s+|to\s+)?` → `ai `
  ("ask the assistant about tailscale" → `ai tailscale`)
- `^(?:tell|have)\s+(?:the\s+)?(?:ai|assistant|hermes|computer)\s+(?:to\s+)?` → `hr `
  ("tell hermes to check the backups" → `hr check the backups`)
  — ASK phrasing → answer lane; TELL/HAVE phrasing → task lane.
- Dictated colons: `(ai|hr)\s*:\s*` (case-insensitive) → `"$1 "` — the router
  matches on first word only, so colon forms must fold.
- Early-rewrite filler: `(ai|hr)\s+(?:about|to)\s+` → `"$1 "` (idempotent while
  typing one character at a time).
- Hard rules: idempotent (`normalize(normalize(x)) == normalize(x)`); any query
  that doesn't match a rule passes through byte-identical — never invent a
  prefix ("why is dns slow" stays unprefixed; "ask a friend" untouched).
- Fixtures: `test/fixtures_normalize.py` (ported from foyer's voice-model
  tests + our no-false-claim cases: "2048 game", "2+2", "hermesy").

### F-2. Web-fallback sibling row (Phase 1b)

Every cached **answer** row gains a sibling directly below it:

| field | value |
|---|---|
| id | `web:{key}` |
| title | `web: {question}` |
| subtext | `OPEN BROWSER SEARCH · ENTER OPENS` |
| icon | `web-browser` (verify exists in Breeze; fallback `internet-web-browser`) |
| catrel / rel | Moderate / 0.9 (answer row stays 0.95 above it) |

- Enter → `xdg-open` of `web_search_url` with `{q}` replaced by
  URL-encoded question. Config field `web_search_url`, default
  `https://duckduckgo.com/?q={q}` (works off-LAN; fleet SearXNG URL is a
  one-line config override — OPEN QUESTION for UX review).
- Error rows get NO web sibling (Enter retries — one verb per row).
- The `asking:` in-flight row gets no sibling either (no answer to fall back
  from yet).

### F-3. Bare-`ai` recents (Phase 1c)

`ai` with no query → help row (unchanged, id `ai-help` keeps muscle memory)
followed by up to **5** most-recent **answer** cache entries, newest first:

| field | value |
|---|---|
| id | `recent:{key}` |
| title | clipped answer (same clip as answer rows) |
| subtext | `Q: {question} · {age} AGO · ENTER COPIES` |
| icon / catrel / rel | `help-browser` / High / 0.8 (below help 0.6? — OPEN QUESTION) |
| actions | `["copy", "askagain", "reshow"]` (same set as answer rows) |

- Privacy scoping (foyer discipline): only ai-lane Q&A. Never `hr` task text
  (agent work, often sensitive), never error rows (they'd be noise).
- Cache already stores ts; recents = sort by ts, filter type==answer, cap 5.

### F-4. Help extension (Phase 1d)

`hermes` / `hermes help` gains one row per new behavior, and in Phase 2 one
row per configured handoff prefix (dynamic: title `Hermes: hand off with
'{prefix} <query>'`, subtext `OPENS {label}`). Help rows stay Moderate/≤0.55
so real matches outrank them.

### F-5. Handoffs lane (Phase 2) — new lane, new config

Config: `"handoffs": [{"prefix": "gh", "label": "GitHub", "url": "https://github.com/search?q=%s"}]`
Example-config defaults: `gh` GitHub · `el` Elastic docs · `map` Maps ·
`sea` fleet SearXNG · `jf` Jellyfin search · `gal` Galaxy portal.

Sanitize rules (foyer-identical): prefix `/^[a-z]{2,6}$/`; label ≤24 chars;
url `https?://` **with `%s`**; no dupes; **RESERVED = [`ai`, `hr`, `hermes`]
may not be shadowed**. Malformed entry → skipped + ONE journal WARN line
(count, not per-entry spam); the runner keeps serving every other lane.

Rows: `<prefix> <q>` → id `handoff:{prefix}:{q}`, title `{label}: {q}`,
subtext `OPENS {url host} · ENTER OPENS BROWSER`, icon `web-browser`,
Highest/1.0. Bare `<prefix>` → its own help row ("type the query after '{prefix}'").
Enter → `xdg-open(url.replace("%s", urlencode(q)))`. Claim is exact-first-word
match on a SANITIZED prefix — never substring, so "gh" can't eat "ghost".

### F-6. Phase acceptance gates (extends §E)

- Phase 1: all `NORMALIZE_FIXTURES` pass + idempotence loop; route() returns
  answer+web sibling with correct URL template; bare-`ai` returns help+≤5
  recents newest-first, errors/hr excluded; zero row changes for non-lane
  queries (golden-set diff against v0.2 route() output).
- Phase 2: sanitize table (reserved shadow / dupe / http / missing %s /
  long label / bad prefix all rejected); malformed-config fixture leaves both
  v0.2 lanes green; handoff row Enter opens correct URL (mocked xdg-open).
- Live (both phases): one real dictated phrase claimed+answered; one web row
  opened; harness kr-driver screenshots; journal clean.
