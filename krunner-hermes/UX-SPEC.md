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

## F. v2 additions — foyer-informed improvements (2026-10-31, UX-reviewed)

Source review: `omarchy-foyer` (Omarchy original, full clone audited). Admission
bar held: nothing KRunner already owns natively. **Scope rule (UX review):**
the handoffs lane stays on the right side of the bar only while it remains
*fleet-scoped* — LAN/fleet targets and config-managed defaults; generic public
web search belongs to the native webshortcuts runner + KCM. Baseline measured
2026-10-31: 5 real `ai` questions via local-fast → **min 0.25s · median 0.63s ·
max 0.79s** (target p95 <8s). Known non-goal: model answered one fleet question
wrong (`o1` for `local-heavy`) — model knowledge, not runner mechanics.

### F-1. Dictation normalization (Phase 1a) — voice-native lanes

VoxType dictation lands whole phrases in the box; today they miss the lanes.
`normalize(query)` runs **in `route()` only** — `Run()` receives only the row
id, and ids are minted from the normalized query inside `route()`. Semantics
ported from foyer VoiceModel, lane-adapted:

- `^(?:ask|question)\s+(?:the\s+)?(?:ai|assistant|hermes|computer)\s+(?:about\s+|to\s+)?` → `ai `
  ("ask the assistant about tailscale" → `ai tailscale`). ASK phrasing →
  answer lane (the safe direction — answers can't act).
- `^(?:tell|have)\s+(?:the\s+)?(?:ai|assistant|hermes|computer)\s+(?:to\s+)?` → `hr `
  ("tell hermes to check the backups" → `hr check the backups`; "tell ai a
  joke" → `hr a joke` — TELL defaults to the task lane by design). Nothing
  fires without Enter on a row titled `Run Hermes: {task}` — a misparse is
  visible before it costs anything.
- Dictated colons: `(ai|hr)\s*:\s*` (case-insensitive) → `"$1 "` — the router
  matches on first word only, so colon forms must fold.
- Early-rewrite filler: `(ai|hr)\s+(?:about|to)\s+` → `"$1 "` (idempotent while
  typing one character at a time).
- Hard rules: idempotent (`normalize(normalize(x)) == normalize(x)`); any query
  that doesn't match a rule passes through byte-identical — never invent a
  prefix ("why is dns slow" stays unprefixed; "ask a friend" untouched; ASR
  artifacts like "ask I about x" fold correctly; "seagate"/"hermesy" can't
  match — exact-word, whitespace-terminated).
- Fixtures: `test/fixtures_normalize.py` (foyer voice-model ports + our
  no-false-claim cases + the two tell→hr intended-default fixtures).

### F-2. Web-fallback sibling row (Phase 1b)

Every cached **answer** row gains a sibling directly below it:

| field | value |
|---|---|
| id | `web:{key}` |
| title | `Web search: {question}` (Sentence case, v0.2 grammar) |
| subtext | `SEARCH {web_search_name} · ENTER OPENS BROWSER` |
| icon | `internet-web-browser` (verified: breeze + breeze-dark apps/48; `web-browser` is NOT in Breeze on this host) |
| catrel / rel | **High(70) / 0.6** — same tier as nothing above it, lower rel than the parent answer (High/0.95) so the sibling renders directly under it; Moderate/0.9 would break tier grammar and let other runners interpose |
| props | `actions: []` explicit (B-2 rule) |

- Enter (`Run` actionId `""` on a `web:` id) → `xdg-open` with the
  **original-case** question substituted into `web_search_url`; other action
  ids on the row no-op (one verb per row).
- Config: `web_search_url` (default `https://duckduckgo.com/?q=%s`, `%s`
  placeholder — same substitution grammar as handoffs) + `web_search_name`
  (≤12 chars, default `DUCKDUCKGO`, mirrors the `{model} VIA LITELLM` pattern).
  Fleet install gets SearXNG via `install.sh --web-search-url
  http://192.168.1.249:8787/search?q=%s --web-search-name SEARXNG` and a
  commented fleet block in `config.json.example` (the P2-6 litellm pattern).
  A fallback row must survive off-LAN and Watertower-down; DDG default, fleet
  URL by config.
- NO web sibling on: error rows (Enter retries), in-flight rows (nothing to
  fall back from yet), or recents rows (passive history, one verb already).

### F-3. Bare-`ai` recents (Phase 1c)

`ai` with no query → help row (unchanged, id `ai-help`, Moderate/0.6 stays on
top) followed by up to **5** most-recent **answer** cache entries, newest
first:

| field | value |
|---|---|
| id | `recent:{key}` |
| title | clipped **question** (120 chars) — the question is what the user scans for and the entry's unique key; answers as titles put five past answers' content on screen and truncate badly |
| subtext | `ANSWER CACHED {age} AGO · ENTER COPIES` |
| icon / catrel / rel | `help-browser` / **Moderate(50)** / `0.5 − 0.03·i` (0.50→0.38 — below help 0.6, descending rel pins newest-first deterministically under re-sort) |
| actions | `["copy", "askagain", "reshow"]` |

- `Run` dispatch for `recent:` is identical to `answer:` — Enter copies the
  full cached answer; copy/askagain (drop + refetch)/reshow (re-notify).
- Privacy scoping (foyer discipline, confirmed correct by review): only
  ai-lane Q&A. Never `hr` task text (hostnames/paths, agent work), never
  error rows (noise). Cache is 32 entries; help + 5 = 6 rows, viewport-sized.

### F-4. Help extension (Phase 1d)

Help rows only for behaviors with **new syntax**: dictation phrases and
(Phase 2) handoff prefixes. Web sibling and recents are passive — no help
rows. Phase-2 handoff help rows: Moderate(50), rel `0.45 − 0.02·i` in config
order (below help-ai 0.55 / help-hr 0.50), title `Hermes: hand off with
'{prefix} <query>'`, subtext `SEARCHES {url host} · OPENS IN BROWSER` (help
rows never promise Enter — D-6).

### F-5. Handoffs lane (Phase 2) — new lane, new config

Config: `"handoffs": [{"prefix": "gh", "label": "GitHub", "url": "https://github.com/search?q=%s"}]`.
Example-config defaults (**`map` cut — generic public search is the native
webshortcuts runner's job and the likeliest English-word collision**): `gh`
GitHub · `el` Elastic docs · `sea` fleet SearXNG · `jf` Jellyfin search ·
`gal` Galaxy portal.

Sanitize rules (foyer-identical): prefix `/^[a-z]{2,6}$/`; label ≤24 chars;
url `https?://` **with `%s`**; no dupes; **RESERVED built from config —
`[conf.answer_prefix, conf.task_prefix, "hermes"]`** (prefixes are
user-configurable; a custom `answer_prefix: "gh"` must be rejected — a
hardcoded list wouldn't catch it). Malformed entry → skipped + ONE journal
WARN line (count, not per-entry spam); the runner keeps serving every lane.

Rows: `<prefix> <q>` → id `handoff:{prefix}:{q}`, title `{label}: {q}`,
subtext `SEARCH {url host} · ENTER OPENS BROWSER`, icon
`internet-web-browser`, Highest/1.0. Bare `<prefix>` → help row: title
`{label} — type the query after '{prefix}'`, subtext `SEARCHES {url host} ·
OPENS IN BROWSER`, Moderate(50)/0.55. Enter → `xdg-open(url.replace("%s",
urlencode(q)))`. Claim is exact-first-word match on a SANITIZED prefix —
never substring ("gh" can't eat "ghost"; "sea" can't match "seagate").

### F-6. Phase acceptance gates (extends §E)

- Icon-lint: every icon literal emitted by `route()` must resolve under
  `/usr/share/icons/breeze` (catches the `web-browser` class forever).
- Phase 1: all `NORMALIZE_FIXTURES` pass + idempotence loop; route() returns
  answer+web sibling with correct URL template and `actions: []`; bare-`ai`
  returns help+≤5 recents newest-first with descending rel, errors/hr
  excluded; sibling renders directly under its answer (adjacency check);
  `recent:`/`web:` dispatch covered (copy semantics / xdg-open with
  original-case question); normalization asserted route()-only.
- Phase 2: sanitize table (reserved-from-config shadow / dupe / http /
  missing %s / long label / bad prefix all rejected); malformed-config
  fixture leaves both v0.2 lanes green; handoff row Enter opens correct URL
  (mocked xdg-open); handoff help rows in config order with stated rel.
- Live (both phases): one real dictated phrase claimed+answered; one web row
  opened; harness kr-driver screenshots; journal clean.
- Zero-row-drift: golden-set diff of route() output for non-lane queries
  against v0.2 (the "2048 game" discipline).

### F-7. Model switch (Phase 3a) — `ai model [<name>]`

Config gains `"models": ["local-fast", "local-heavy", "local-fast-reason",
"cloud-dev"]` (fleet aliases; user-editable). Behavior change vs v0.3: `ai
model …` becomes a subcommand of the ai lane instead of being asked as a
question (documented in README).

- `ai model` (bare): one row per alias in config order, icon `cpu`
  (icon-lint verified), Moderate(50):
  - current: id `model-cur:<alias>`, title `Model: <alias>`, subtext
    `CURRENT · ANSWERS USE THIS MODEL`, rel 0.55, `actions: []`
  - others: id `model:<alias>`, title `Model: <alias>`, subtext
    `ENTER SWITCHES · PERSISTS TO CONFIG · ANSWERS MOVE TO <alias>`,
    rel 0.5 − 0.02·i, `actions: []`
  - Run on `model-cur:` re-notifies (§B-9): `Hermes · model` /
    `<alias> answers ai questions` / `cpu` / low — no dead ids in the
    state matrix.
- `ai model <name>`: case-insensitive exact match against the allowlist →
  action row id `model:<name>`, title `Switch to <name>`, subtext
  `ENTER SWITCHES THE AI LANE · PERSISTS TO CONFIG`, Highest/1.0,
  `actions: []` (explicit — omitted props show ALL global actions, v0.3
  ruling). Switch-to-self (name == current) renders the bare list with
  CURRENT marked — never a "Switch to <current>" row. Unknown name →
  the STANDARD ask row for the full question (§B-2 state 2,
  Highest/1.0) with ONE help row below: id `model-help`, title
  `No such model: <name>`, subtext `VALID · <first three aliases>` or
  `VALID · <aliases> +n MORE` when capped, Moderate/0.5, `actions: []` —
  the ai lane stays askable (F-1 never-hijack) while typo feedback
  survives.
- Run (`model:` kind): read-modify-write `config.json` preserving unknown
  keys (`litellm.model` only), update in-memory conf, one journal line,
  §B-9 notification `Hermes · model switched` / `<name> now answers ai
  questions` / `cpu` / normal; errors writing config → `Hermes · switch
  not saved` / `using <name> this session · config write failed` /
  `dialog-error` / low — model still switched in memory (sticky until
  restart).
- Sanitize: allowlist membership only; `models: []` disables the subcommand
  (falls back to question routing).

### F-8. Adoption counters (Phase 3b) — counts on Run, never query text

File `~/.cache/hermes-runner/stats.json` (chmod 600, write-temp+rename per
event — SIGTERM-safe by construction). Counted on **Run dispatch only**
(Match fires per keystroke; counting there inflates everything):

| counter | credited when |
|---|---|
| `asks` | ask/askagain fires (incl. dictation-folded) |
| `tasks` | task fires |
| `answer_uses` | `answer:` rows: Enter/copy/reshow (consumption, not delivery) |
| `error_retries` | error-row Enter/askagain (retries, not failures) |
| `handoffs.<prefix>` | handoff Enter opens URL |
| `web_opens` | web sibling Enter opens browser |
| `recents_copies` | `recent:` Enter/copy |
| `model_switches` | model switch persists |
| `dictation_hits` | Run on a row whose id was minted from a query that `normalize()` changed (daemon tags fold-events per id at Match time; Run consumes) |
| `days.<YYYY-MM-DD>.<same keys>` | day-granular rollup for the 2-week cut/keep report |

`answer:` and `recent:` counters are DISJOINT (recent copies credit
`recents_copies` only — never both). Names describe the counted event, so
the adoption report reads true: delivery volume is approximated by `asks`.

`python3 hermes_runner.py --stats` prints pretty JSON + totals (no dbus).
Privacy: counts only — query text is never stored. The two-week adoption
review (≈2026-11-14) reads this file and lanes that don't earn their keep
get cut.

### F-9. SSH lane (Phase 4) — `ssh <host>`

Source of truth: `~/.ssh/config`, parsed at load + HUP reload (same
lifecycle as handoffs). Parser (foyer-based, extended): `Host` lines may
name several hosts per group; `Hostname`/`Port`/`User` apply to the whole
group; glob names (`*` `?`) and NEGATED names (`!foo`) are skipped;
trailing `# comments` stripped; names lowercased for matching, original
case kept for titles. `Include` directives are FOLLOWED (one level of
`~` expansion + glob, missing files silently skipped — a host hidden in
an Include is this lane's likeliest real-world miss).

- Claim: the query is claimed iff its FIRST WORD is exactly `ssh`
  (`sshconf`/`sshd` are unclaimed); the remaining terms then match hosts
  exact > name-prefix > substring, cap 8. `ssh seagate` IS claimed and
  yields the no-match row.
- `ssh <terms>`: rows id `ssh:<name>`, title `SSH <name>` (original
  case), subtext `CONNECT <user@>host[:port] · ENTER OPENS TERMINAL`
  (only present parts), icon `utilities-terminal`, Highest/1.0,
  `actions: []`.
- `ssh` bare: help row title `SSH — type a host after 'ssh'` (subtext
  `HOSTS COME FROM ~/.ssh/config · TYPE 'hermes ssh' FOR DETAILS`,
  Moderate/0.55, `actions: []`) + first 5 hosts alphabetically at
  Moderate 0.5−0.02i as connect rows.
- No matches: one row `No host matches '<terms>'`, subtext `HOSTS COME
  FROM ~/.ssh/config`, id `ssh-help`, Moderate/0.5, `actions: []`.
- Run (`ssh:` kind): spawn `konsole --hold -e ssh <name>` (name
  re-validated against the parsed table — never trust the wire id);
  counts `ssh_sessions`. `--hold` keeps the window up after disconnect.
- No config duplication: hosts are NEVER copied into config.json. README
  recommends short multi-name aliases (`Host aic aicube`) — keystroke
  filtering is the completion; there is none (and foyer has none either).

### F-10. Snippets (Phase 4) — `;name [text]`

Config: `snippets: [{name, text}]`, sanitized at load: name
`^[a-z0-9][a-z0-9-]{0,15}$` (validated RAW — no silent lowering; unique;
`help` is reserved FOR the `;help` alias below), text non-empty,
single-line, ≤2000 chars. Malformed entries skipped + one journal line,
never fatal.

- Claim: query starts with `;`.
- `;` bare (or `;help`): the INDEX — every snippet in config order, cap
  8 rows then a `+N MORE · ALL IN config.json` pointer row. Row: id
  `snippet:<name>`, title `<name>`, subtext `clip(text, 80) · ENTER
  COPIES`, icon `text-x-generic`, Moderate — first row 0.55, then
  0.5−0.02i, actions `[copy, show, delete]`. Zero snippets configured →
  ONE save-syntax help row: `No snippets yet` / `TYPE ;name text… TO
  SAVE ONE · SNIPPETS LIVE IN config.json`, Moderate/0.5, `actions: []`.
- `;name` exact match: ONE row, Highest/1.0, `actions: []` — Enter
  copies (single-verb pattern, like ask/task/handoff). Title `<name>`,
  subtext `clip(text, 80) · ENTER COPIES`.
- `;name <terms>` where name EXISTS: row 1 the copy row as above
  (Highest/1.0, `actions: []`); row 2 `Overwrite '<name>' with new
  text`, Moderate/0.5, subtext `clip(terms, 80) · ENTER REPLACES THE
  SNIPPET`, id `snippet-save:<name>`, `actions: []`.
- `;<valid-new-name> <text>` where name is UNKNOWN: single row `Save
  snippet '<name>'`, subtext `clip(text, 80) · ENTER SAVES · THEN
  ;<name> COPIES`, id `snippet-save:<name>`, Highest/1.0, `actions: []`.
- `;<anything>` that is a VALID name with NO text and no match (e.g.
  `;foo`), or an INVALID name (regex fail / reserved): ONE help row `No
  such snippet: <name>` / `Invalid snippet name: <name>`, subtext
  `VALID NAMES a-z 0-9 - MAX 16 · TYPE ';' TO LIST`, id `snippet-help`,
  Moderate/0.5, `actions: []`.
- Run kinds: `snippet:` act ""→ clipboard + `snippet_uses` + notify
  `Hermes · snippet copied` (low); act `copy` same; act `show` → notify
  `Hermes · <name>` body full text + `snippet_uses` (like reshow credits
  answer_uses); act `delete` → remove + persist + `snippet_edits` +
  notify `Hermes · snippet deleted` whose BODY CARRIES THE FULL TEXT
  (undo-by-copy — delete is the runner's only destructive verb, one
  misclick from COPY). `snippet-save:` → upsert + persist +
  `snippet_edits` + notify `Hermes · snippet saved`. Persist is
  read-modify-write of config.json preserving unknown keys.
- Actions() constants gain: `("show", "SHOW", "help-browser")` and
  `("delete", "DELETE", "edit-delete")` (B-8 CAPS grammar; both
  Breeze-verified on this host) alongside copy/askagain/reshow.
- Privacy: snippet TEXT never in titles; previews clip to 80 chars.

### F-11. Layered help (Phase 4) — the query line is the navigation

SUPERSEDES §B-2 states 9–10 (the old two-row `hermes` pair) and §F-4's
`hermes`-query handoff help rows — all `hermes`/`help` traffic now gets
the index below.

- `hermes` AND bare `help` claim the INDEX — one row per lane with
  FIXED rels (deterministic, independent of configured handoff count):
  help-ai .55 · help-hr .50 · help-dictation .45 · help-ssh .43 ·
  help-snippet .42 · help-model .41 · help-handoff-<p> .40−0.01i (cap 8
  handoff rows, then `+N MORE · TYPE 'hermes handoffs'`) · help-docs
  .30. Every subtext ends with its drill hint (`TYPE 'hermes ssh' FOR
  DETAILS` style).
- `hermes <unknown>` / `help <unknown>` fall back to the INDEX (no typo
  row — the index IS the correction).
- `hermes <lane>` detail pages: cap 6 rows each at Moderate 0.5−0.02i,
  ids `helppage:<lane>:<n>`, icon `help-browser`, `actions: []` (inert)
  except example rows which carry a `copy` action (clipboard-ready
  example). One syntax row, 2–3 examples, one management/config row per
  lane; handoffs page lists every configured prefix when the index had
  to cap. Pages appear ONLY under `hermes`/`help` queries — they can
  never crowd a live lane.
- `hermes docs` row: id `help-docs`, Moderate/0.30, icon `help-browser`,
  `actions: []`; Run opens the README via xdg-open (kind `docs`).
  README stays the full manual.
- Counter additions: `ssh_sessions`, `snippet_uses` (copy + show),
  `snippet_edits` (create+overwrite+delete) — Run-only, same rules as
  §F-8.
- Reserved registry becomes BIDIRECTIONAL at load: handoff prefixes
  reject `ssh` and `help` in addition to existing rules; and
  `answer_prefix`/`task_prefix` values equal to any lane claim
  (`ssh`, `help`, `hermes`) are rejected with a journal warning — the
  config default applies until fixed. Renames can no longer shadow a
  lane in either direction.

---

## L. Launcher lane — app browsing, categories, favorites (2026-11-02, spec r1)

Goal: foyer-style start-menu browsing inside the native KRunner window —
search box on top, browsable rows below, arrow keys + Enter. Apps live
under one prefix; the native application runner stays untouched (no twin
rows for a plain `firefox` query). Reference: `omarchy-foyer`
AppModel.js/RunnerModel.js (desktop-entry rows, alias search, hides,
categories) — reimplemented for KDE, not ported.

### L-1 Scope and admission

- Lane claim regex: `^apps(\s|$)` case-insensitive. Bare `apps` = browse
  root. Anything else (including bare app names) is NOT claimed — native
  KRunner application search keeps that surface (no-duplication rule).
- Row kinds minted: `app:<desktop-id>` (launch), `apppin:<desktop-id>`
  (pin/unpin toggle), `appcat:<slug>` (category drill).
- Excluded: recents-from-xbel, menu JSONC trees, .desktop editing,
  window management, anything KRunner lanes already own.

### L-2 Enumeration and cache

- Scan dirs, in id-precedence order (first id wins, mirroring KService):
  `~/.local/share/applications`, `/usr/local/share/applications`,
  `/usr/share/applications`, `~/.local/share/flatpak/exports/share/applications`,
  `/var/lib/flatpak/exports/share/applications` (+ any `applications/`
  dir under `$XDG_DATA_DIRS` at load time). Symlinks followed once.
- Per file (plain INI, `[Desktop Entry]` group; a file with no parseable
  group is skipped silently): keep `Type` (must be `Application`),
  `Name`, `GenericName`, `Comment`, `Icon`, `Exec`, `Categories`,
  `TryExec`. Skip when: `NoDisplay=true`, `Hidden=true`, `OnlyShowIn`
  present and not containing `KDE`/`GNOME`-generic (skip unless the list
  is empty or contains `KDE`), `NotShowIn` contains `KDE`, `TryExec` set
  and not resolvable via `PATH`. `id` = basename with `.desktop` kept —
  `launchCommand`-style id preservation matters for flatpak ids
  (`org.telegram.desktop` will not resolve stripped).
- Cache: `~/.cache/hermes-runner/apps.json`
  `{"v":1,"dirs":{path:mtime_ns},"apps":[…]}`. A Match call checks dir
  `stat().st_mtime_ns` (plus flatpak dirs) — all unchanged → cache hit,
  zero parsing. Any change or version mismatch → one full rescan,
  rewrite cache atomically (tmp + rename). Rescans are capped to one
  per Match call. Cache errors are never fatal: fall back to direct
  scan and log once to stderr (journal).

### L-3 Category model

- Precedence-ordered main-category map (first match wins):
  Settings→Settings, System→System, TerminalEmulator→System,
  Game→Games, Network→Internet, AudioVideo→Media, Audio→Media,
  Video→Media, Graphics→Graphics, Office→Office,
  Development→Development, Utility→Utilities, TextEditor→Utilities,
  Education→Learning, Science→Learning. No match → `More`.
- Category slugs and labels: internet=Internet, games=Games,
  settings=Settings, system=System, media=Media, graphics=Graphics,
  office=Office, development=Development, utilities=Utilities,
  learning=Learning, more=More. Fixed display order: Internet, Media,
  Games, System, Settings, Development, Graphics, Office, Utilities,
  Learning, More.
- User overrides: config `app_categories` —
  `{"<desktop-id>": "<slug>"}` wins over the file's Categories. Unknown
  slug in config = journal warning, entry falls back to file mapping.

### L-4 Query grammar and rows

- `apps` (root): pinned rows (config order, subtext `pinned · <slug>`),
  then frequency rows (top 6 by launch count, desc, excluding pinned,
  subtext `<count>× · <slug>`), then one row per non-empty category in
  L-3 display order (label `Category — N apps`, kind `appcat`).
- `apps <tok>` where `<tok>` (case-insensitive) prefix-matches exactly
  one category name or slug, or the query has exactly one token that
  prefix-matches several (e.g. `s` → settings/system): render those
  category rows only. Remaining tokens filter inside.
- `apps <slug> [text]`: rows = that category's apps, alphabetical by
  Name (Name as tiebreak id). Subtext = GenericName else Exec basename
  (args after the executable stripped; `%f/%u/%U/%F` placeholders cut).
  `text` filters as below.
- `apps <text>` (no category hit): fuzzy filter across ALL apps:
  case-insensitive; multi-token queries are AND (every token must match
  somewhere in name+genericName+comment+exec-basename); substring, not
  levenshtein. Empty result set → single info row (`No apps match`,
  subtext `try a category, e.g. apps games`).
- App row: label = Name, icon = Icon (theme name or absolute path;
  empty → `application-x-executable`), actions `["launch","pin"]` or
  `["launch","unpin"]` when already pinned.
- Relevance ladder: exact Name match 1.0, name-prefix 0.9, other hits
  0.55; category rows 0.9; root pinned/frequency rows 0.95/0.85.

### L-5 Favorites

- Pins: config `app_pins` — ordered array of desktop-ids. Dead id
  (app no longer enumerated) → row skipped at render, no warning spam
  (one journal line per daemon lifetime per id).
- Toggle: action 2 on any app row (`apppin` kind) flips membership and
  writes config.json atomically (tmp+rename, load-conf schema
  validated); the write goes through the existing sanitize path so a
  corrupt list can never take the runner down. Response row: `Pinned
  <Name>` / `Unpinned <Name>`, subtext shows remaining pin count.
- Frequency: stats counter `app_launches` — a per-day map is NOT
  needed; a lifetime count map `{desktop-id: n}` in the stats file.
  Incremented only on real launch dispatch, never on pin toggles or
  info rows.

### L-6 Launching (safety rules)

- Launch = `subprocess.Popen(["kioclient","exec",<absolute .desktop
  path>], start_new_session=True, close_fds=True, cwd="/")` — the
  desktop file's own Exec runs through KDE's launcher (Terminal=true,
  StartupWMClass, activation tokens all handled there).
  `kioclient` absent from PATH → fallback argv
  `["gtk-launch", id]`. If both missing: error row `Cannot launch
  (no kioclient/gtk-launch)`.
- NEVER build a command from the `Exec=` string; NEVER `shell=True`;
  the id→path mapping comes only from the enumeration cache (an id in a
  Run payload that is not in the cache → error row, no filesystem
  guessing). Run() must return in <100 ms — Popen is fire-and-forget.
- Launch also bumps `app_launches` and (per F-5 recents pattern) mints
  nothing else — no answer feed, no clipboard.

### L-7 Empty-state Actions() (ambition, verified in harness)

- `Actions()` gains `("apps", "APPS", "start-here-kde")` and
  `("fav", "FAVORITES", "bookmarks")` buttons. In the nested-session
  harness, verify whether plasma-krunner renders runner actions at
  empty query. If yes: button click routes to Run with that actionId →
  handler re-drives the UI via the proven `/App query` preload
  (`apps` / pins-only query `apps ★` — final char in build). If plasma
  ignores them, the fallback is documented in help: type `apps`+Enter.
  The fallback ships regardless; the buttons are pure upside.

### L-8 Config, stats, help

- Config keys (additive): `app_pins` (array), `app_categories` (map).
  Both optional; absence = defaults. `hermes config` / SIGHUP reload
  picks them up live like every other key.
- Stats keys: `app_launches` (map), `app_pins_set`,
  `app_pins_removed`, `app_browses` (root renders) — surfaced in the
  existing Stats help view.
- Help (§F-11 model) gains a Launcher block: `apps` root, category
  drill, text filter, pin/unpin action, empty-state note.

### L-9 Tests (admission gates)

- Unit (fixtures: normal, NoDisplay, Hidden, OnlyShowIn=GNOME,
  NotShowIn=KDE, TryExec missing, Terminal=true, flatpak id, dup id in
  two dirs, bad INI, unicode Name): parser skips, id precedence,
  category precedence + overrides, claims regex (bare `firefox` NOT
  claimed; `apps`, `apps games`, `APPs` claimed), root ordering
  (pins→freq→categories), frequency exclusion of pins, category
  filter + AND-token fuzzy, dead-pin skip, pin toggle roundtrip on a
  temp config, cache mtime rescan (stale→rescan, fresh→hit),
  `launch` argv (mock Popen: exactly kioclient+abs path, no shell, no
  Exec-derived argv), stats increments, error rows for unknown id /
  missing launchers, Actions() contains the two buttons.
- Harness (`run-krunner.sh` extended): stubbed `kioclient` first in
  nested PATH (tailfin stub pattern) — drive Match over DBus for root/
  category/fuzzy/pin-toggle; stub log must show exactly one exec with
  the fixture .desktop's absolute path; journal checkpoints; pixels at
  both scales (root rows render, icons present).

### L-10 Explicitly out of scope

Mullvad-style categories-as-tabs chrome, grid views, .desktop file
editing, per-app "open file…" handlers, Wayland window activation.
Any of those would mean fighting KRunner's window instead of feeding
it rows.
