#!/usr/bin/env python3
"""Hermes KRunner DBus runner — 'ai <q>' asks LiteLLM, 'hr <task>' fires Hermes.

Zero-compile Plasma 6 runner: implements org.kde.krunner1 (Match/Run/Actions)
on the session bus; discovered via the .desktop file's X-Plasma-API=DBus keys.
Interface signatures per the installed KRunner 6.31 XML (UX pass 2026-10-30;
field 4 wire type is INT32 — KWin's introspection XML advertises 'uint32' but
QtDBus marshals C++ int as 'i'; python-dbus must declare 'i' or krunner
rejects every reply with InvalidSignature — harness-caught 2026-10-30):
    Match(s)  -> a(sssida{sv})
    Run(ss)   -> ()
    Actions() -> a(sss)          # triples are (id, text, iconName)
    SetActivationToken(s) -> ()  # no-op; silences Wayland activation error

Design rules (UX-SPEC.md — implement verbatim):
  - Match NEVER performs I/O: no fetch, no spawn. Enter (Run) is the verb
    "ask" — fetching at Match time meant one HTTP call + notification per
    keystroke prefix. Retype shows cached/in-flight states inline.
  - Typed cache: entries are ("answer"|"error", text, ts). Errors are
    humanized, shown as a distinct row, and Enter retries — never cached
    as answers.
  - id→payload map preserves original case for ask/task round-trips.
  - Per-task running registry prevents double-firing agent turns.
  - Stdlib + python-dbus only (Bazzite base RPMs). No secrets in code or
    repo: the LiteLLM key is read at runtime from env or a local file.

Config: ~/.config/hermes-runner/config.json (see config.json.example).
Reload:  systemctl --user kill -s HUP hermes-runner.service  (or restart).
"""

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

BUS_NAME = "org.kde.runners.hermes"
OBJ_PATH = "/hermes"
IFACE = "org.kde.krunner1"

# Match field 4 is CategoryRelevance (querymatch.h @ KRunner 6.31):
# { Lowest=0, Low=30, Moderate=50, High=70, Highest=100 }.
R_HIGHEST, R_HIGH, R_MODERATE = 100, 70, 50

DEFAULT_CONF = {
    "answer_prefix": "ai",
    "task_prefix": "hr",
    "litellm": {
        "base_url": "http://localhost:4000/v1",
        "model": "local-fast",
        "timeout_s": 45,
        "api_key_env": "ZHW_PROXY_API_KEY",
        "api_key_file": "~/.hermes/secrets/infra.env",
    },
    "max_answer_chars": 700,
    "copy_answers": True,
    "web_search_url": "https://duckduckgo.com/?q=%s",
    "web_search_name": "DUCKDUCKGO",
    "handoffs": [
        {"prefix": "gh", "label": "GitHub",
         "url": "https://github.com/search?q=%s"},
        {"prefix": "sea", "label": "SearXNG fleet",
         "url": "http://192.168.1.249:8787/search?q=%s"},
        {"prefix": "el", "label": "Elastic docs",
         "url": "https://duckduckgo.com/?q=site%3Aelastic.co+%s"},
    ],
}

CONF_PATH = Path(os.environ.get(
    "HERMES_RUNNER_CONF", "~/.config/hermes-runner/config.json")).expanduser()
CACHE_DIR = Path("~/.cache/hermes-runner").expanduser()

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

# ---------------------------------------------------------------- utilities

def log(*a):
    print(f"[hermes-runner {time.strftime('%H:%M:%S')}]", *a, file=sys.stderr)


def age_str(ts, now=None):
    s = max(0, (now or time.time()) - ts)
    if s < 60:
        return f"{int(s)}s"
    if s < 3600:
        return f"{int(s // 60)}m"
    return f"{int(s // 3600)}h"


def clip(text, n):
    text = text or ""
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def sanitize_handoffs(conf):
    """F-5: foyer-identical sanitize. RESERVED is built FROM config prefixes
    so renaming a lane can't be silently shadowed. Returns (clean, skipped);
    malformed entries are dropped, never fatal."""
    reserved = {conf.get("answer_prefix", "ai"),
                conf.get("task_prefix", "hr"), "hermes"}
    clean, seen, skipped = [], set(), 0
    for h in (conf.get("handoffs") or []):
        try:
            p = str(h["prefix"]).strip()
            label = str(h["label"]).strip()
            url = str(h["url"]).strip()
        except (KeyError, AttributeError, TypeError):
            skipped += 1
            continue
        if (not re.fullmatch(r"[a-z]{2,6}", p) or p in reserved or p in seen
                or not label or len(label) > 24
                or not re.match(r"^https?://", url) or url.count("%s") != 1):
            skipped += 1
            continue
        seen.add(p)
        clean.append({"prefix": p, "label": label, "url": url,
                      "host": urllib.parse.urlparse(url).netloc})
    return clean, skipped


def load_conf():
    conf = json.loads(json.dumps(DEFAULT_CONF))  # deep copy
    try:
        user = json.loads(CONF_PATH.read_text())
        for k, v in user.items():
            if isinstance(v, dict) and isinstance(conf.get(k), dict):
                conf[k].update(v)
            else:
                conf[k] = v
    except FileNotFoundError:
        pass  # run on defaults; install.sh writes a real config
    except Exception as e:  # broken user config: defaults, loudly
        log(f"config unreadable ({e}); using defaults")
    conf["_handoffs"], skipped = sanitize_handoffs(conf)
    if skipped:
        log(f"{skipped} handoff entries skipped (sanitize)")
    return conf


def litellm_key(conf):
    env = conf["litellm"].get("api_key_env", "")
    if env and os.environ.get(env):
        return os.environ[env]
    keyfile = Path(conf["litellm"].get("api_key_file", "")).expanduser()
    if env and keyfile.is_file():  # KEY=value lines
        m = re.search(rf"^\s*(?:export\s+)?{env}=\"?([^\"\n]+)\"?",
                      keyfile.read_text(), re.M)
        if m:
            return m.group(1).strip()
    return ""


def humanize(exc, conf):
    """One clean line, for row subtext and notifications. No trace grammar."""
    url = conf["litellm"].get("base_url", "")
    if isinstance(exc, urllib.error.HTTPError):
        try:
            body = exc.read(200).decode(errors="replace").splitlines()
            first = body[0] if body else ""
        except Exception:
            first = ""
        return clip(f"LiteLLM HTTP {exc.code}: {first}", 80)
    if isinstance(exc, urllib.error.URLError):
        reason_obj = getattr(exc, "reason", exc)
        r = str(reason_obj).lower()
        if "refused" in r or isinstance(reason_obj, ConnectionRefusedError):
            return f"LiteLLM unreachable at {url}"
        if "timed out" in r or "timeout" in r:
            return (f"timeout after {conf['litellm'].get('timeout_s', 45)}s "
                    f"— LiteLLM {url}")
        return clip(f"network error: {reason_obj}", 80)
    if isinstance(exc, json.JSONDecodeError):
        return "LiteLLM returned malformed JSON"
    first = str(exc).splitlines()[0] if str(exc) else exc.__class__.__name__
    return clip(first, 120)


def clean_tail(path):
    """Last 400 chars of a task log: ANSI-stripped, CR-normalized, squeezed."""
    try:
        t = ANSI_RE.sub("", Path(path).read_text(errors="replace"))
    except Exception:
        return "(log unreadable)"
    t = t.replace("\r", "\n")
    t = re.sub(r"\n{3,}", "\n\n", t).strip()
    return t[-400:]


def notify(summary, body, icon="help-browser", urgency="normal", conf=None):
    conf = conf or {}
    if not conf.get("notify", True):
        log("notify (suppressed):", summary)
        return
    body = clip(body or "", conf.get("max_answer_chars", 700))
    try:
        subprocess.Popen(
            ["notify-send", "-a", "Hermes", "-i", icon, "-u", urgency,
             summary, body],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        log("notify-send missing; notification skipped:", summary)


def clipboard(text):
    try:
        bus = dbus.SessionBus()
        bus.call_blocking("org.kde.klipper", "/klipper",
                          "org.kde.klipper.klipper",
                          "setClipboardContents", "s", (text,))
        return True
    except Exception as e:
        log("clipboard failed:", e)
        return False


# ------------------------------------------------------------------- model

class AnswerCache:
    """qh -> (kind, text, ts), kind in {"answer","error"}. Bounded, safe."""
    def __init__(self, size=32):
        self.lock, self.map, self.size = threading.Lock(), {}, size

    def get(self, q):
        with self.lock:
            return self.map.get(q)

    def put(self, q, kind, text):
        with self.lock:
            if len(self.map) >= self.size:
                self.map.pop(next(iter(self.map)))
            self.map[q] = (kind, text, time.time())

    def drop(self, q):
        with self.lock:
            self.map.pop(q, None)

    def recent_answers(self, n=5):
        """[(question, ts)] newest-first, answers only (UX-SPEC F-3:
        privacy scope — never errors, and hr task text never enters the
        cache at all)."""
        with self.lock:
            items = [(q, v[2]) for q, v in self.map.items() if v[0] == "answer"]
        items.sort(key=lambda t: t[1], reverse=True)
        return items[:n]


# ------------------------------------------------------- pure row routing
# Module-level and I/O-free so unit tests can exercise every state without
# a session bus (UX-SPEC B-2 state matrix; Match() only wraps this).

def normalize(query, conf):
    """Dictation normalization (UX-SPEC F-1, foyer VoiceModel semantics).
    route()-only — Run() receives ids minted from the normalized text.
    Idempotent; a query matching no rule passes through byte-identical.
    Lane TARGETS follow config; the speakable words (ai/assistant/hermes/
    computer) are fixed."""
    text = str(query or "")
    ap = str(conf["answer_prefix"])
    tp = str(conf["task_prefix"])
    spoken = r"(?:ai|assistant|hermes|computer)"
    m = re.match(rf"^(?:ask|question)\s+(?:the\s+)?{spoken}\s+"
                 r"(?:about\s+|to\s+)?", text, re.I)
    if m:
        return ap + " " + text[m.end():].lstrip()
    m = re.match(rf"^(?:tell|have)\s+(?:the\s+)?{spoken}\s+"
                 r"(?:to\s+|about\s+)?", text, re.I)
    if m:
        return tp + " " + text[m.end():].lstrip()
    lanes = rf"({re.escape(ap)}|{re.escape(tp)})"
    m = re.match(lanes + r"\s*:\s*", text, re.I)      # dictated colon folds
    if m:
        return m.group(1).lower() + " " + text[m.end():]
    m = re.match(lanes + r"\s+(?:about|to)\s+", text, re.I)  # rewrite filler
    if m:
        return m.group(1).lower() + " " + text[m.end():]
    return text

def route(query, cache, fetching, running, conf):
    """Rows as (id, title, subtext, icon, catrel, relevance, props-dict)."""
    q = normalize(query, conf).strip()
    low = q.lower()
    words = low.split(" ", 1)
    first = words[0] if words else ""
    rest = words[1].strip() if len(words) > 1 else ""
    model = conf["litellm"]["model"]
    now = time.time()
    out = []

    def row(mid, title, subtext, icon, catrel, rel, props=None):
        out.append((mid, title, subtext, icon, catrel, rel, dict(props or {})))

    # Prefix routing on the first WORD, not startswith(prefix+" "): bare
    # "ai" / "hr" must reach their own lane help (harness-caught 2026-10-30).
    if first == conf["answer_prefix"]:
        if not rest:
            row("ai-help", "Ask Hermes — type a question after 'ai'",
                f"ONE-SHOT ANSWER · NOTIFIED, THEN CACHED INLINE · {model} "
                "VIA LITELLM",
                "help-browser", R_MODERATE, 0.6)
            # Recents (F-3): newest-first below help, descending rel pins
            # order under re-sort; question is the title, never the answer.
            for i, (rkey, rts) in enumerate(cache.recent_answers(5)):
                row(f"recent:{rkey}", clip(rkey, 120),
                    f"ANSWER CACHED {age_str(rts, now)} AGO · ENTER COPIES",
                    "help-browser", R_MODERATE, round(0.5 - 0.03 * i, 2),
                    {"actions": ["copy", "askagain", "reshow"]})
            return out
        key = rest
        entry = cache.get(key)
        if key in fetching and not entry:
            row(f"asking:{key}", f"Asking… {rest}",
                "IN FLIGHT · ANSWER NOTIFIES WHEN DONE",
                "clock", R_HIGH, 0.9, {"actions": []})
        elif entry and entry[0] == "answer":
            row(f"answer:{key}", clip(entry[1], 240),
                f"CACHED {age_str(entry[2], now)} AGO · ENTER COPIES",
                "help-browser", R_HIGH, 0.95,
                {"multiline": True,
                 "actions": ["copy", "askagain", "reshow"]})
            # Web fallback (F-2): sibling directly under the answer; same
            # tier (High), lower rel — never Moderate/0.9 (tier grammar).
            row(f"web:{key}", f"Web search: {rest}",
                f"SEARCH {conf.get('web_search_name', 'DUCKDUCKGO')} · "
                "ENTER OPENS BROWSER",
                "internet-web-browser", R_HIGH, 0.6, {"actions": []})
        elif entry and entry[0] == "error":
            row(f"error:{key}", f"Ask failed — {rest}",
                f"{clip(entry[1], 80)} · ENTER RETRIES",
                "dialog-error", R_HIGH, 0.95, {"actions": ["askagain"]})
        else:
            row(f"ask:{key}", f"Ask Hermes: {rest}",
                "ENTER ASKS · ANSWER NOTIFIES · RETYPE TO READ INLINE",
                "help-browser", R_HIGHEST, 1.0, {"actions": []})
        return out

    if first == conf["task_prefix"]:
        if not rest:
            row("hr-help", "Run Hermes — type the task after 'hr'",
                "ONE UNATTENDED hermes -z TURN · NOTIFIED WHEN DONE",
                "system-run", R_MODERATE, 0.6)
            return out
        key = rest
        if key in running:
            info = running[key]
            row(f"taskrun:{key}", f"Running: {rest}",
                f"RUNNING · {age_str(info['start'], now)} ELAPSED · "
                "ENTER SHOWS TAIL",
                "chronometer", R_HIGH, 0.95, {"actions": []})
        else:
            row(f"task:{key}", f"Run Hermes: {rest}",
                "ENTER FIRES hermes -z · RESULT NOTIFIES · "
                "LOG IN ~/.cache/hermes-runner",
                "system-run", R_HIGHEST, 1.0, {"actions": []})
        return out

    if low in ("hermes", "hermes help"):
        row("help-ai", "Hermes: ask with 'ai <question>'",
            f"NOTIFIED ANSWER, THEN CACHED INLINE · {model} VIA LITELLM",
            "help-browser", R_MODERATE, 0.55)
        row("help-hr", "Hermes: run a task with 'hr <task>'",
            "UNATTENDED AGENT TURN · NOTIFIED WHEN DONE",
            "system-run", R_MODERATE, 0.5)
        row("help-dictation", "Hermes: dictate — 'ask hermes …' answers, "
            "'tell hermes …' runs",
            "VOXTYPE PHRASES FOLD INTO THE ai/hr LANES",
            "help-browser", R_MODERATE, 0.45)
        for i, h in enumerate(conf.get("_handoffs", ())):
            # below help-ai 0.55 / help-hr 0.50 / help-dictation 0.45,
            # config order, deterministic (spec F-4)
            row(f"help-handoff-{h['prefix']}",
                f"Hermes: hand off with '{h['prefix']} <query>'",
                f"SEARCHES {h['host']} · OPENS IN BROWSER",
                "internet-web-browser", R_MODERATE,
                round(0.43 - 0.02 * i, 2))
    else:
        # F-5 handoff claims: exact FIRST-WORD match on a sanitized prefix —
        # "gh" can never eat "ghost", "sea" never matches "seagate".
        for h in conf.get("_handoffs", ()):
            if first != h["prefix"]:
                continue
            # original-case query for the title (id mint lowercases)
            qw = q.split(" ", 1)
            orig_rest = qw[1].strip() if len(qw) > 1 else ""
            if not rest:
                row(f"handoff:{h['prefix']}",
                    f"{h['label']} — type the query after '{h['prefix']}'",
                    f"SEARCHES {h['host']} · OPENS IN BROWSER",
                    "internet-web-browser", R_MODERATE, 0.55)
            else:
                row(f"handoff:{h['prefix']}:{rest.lower()}",
                    f"{h['label']}: {orig_rest}",
                    f"SEARCH {h['host']} · ENTER OPENS BROWSER",
                    "internet-web-browser", 100, 1.0,
                    {"actions": []})
            break
    return out


# --------------------------------------------------------- run dispatch
# Module-level so unit tests can cover every kind/action pair with a fake
# ctx (UX-SPEC F-6 dispatch gates; v0.2 could not unit-test Run at all).
# ctx needs: .conf, .cache, .fetch_answer(text), .running_tasks — side
# effects go through clipboard()/notify()/Popen, all patchable.

def web_target(conf, text):
    """F-2: substitute the ORIGINAL-CASE question into web_search_url."""
    url = conf.get("web_search_url", "https://duckduckgo.com/?q=%s")
    return url.replace("%s", urllib.parse.quote_plus(text or ""))


def run_dispatch(kind, key, text, act, ctx):
    conf = ctx.conf

    if kind == "ask":
        if act in ("", "askagain"):
            ctx.fetch_answer(text)
        elif act == "copy":
            clipboard(text)
        elif act == "reshow":
            e = ctx.cache.get(key)
            if e:
                notify(f"Hermes · {clip(text, 60)}", e[1],
                       "help-browser", "normal", conf)
    elif kind == "asking":
        if act == "":
            notify("Hermes · still asking",
                   f"{text}\nanswer notifies when done", "clock", "low", conf)
        elif act == "copy":
            clipboard(text)
    elif kind == "answer" or kind == "recent":
        # F-3: recent: dispatch identical to answer:.
        entry = ctx.cache.get(key)
        if act in ("", "copy"):
            if entry and conf.get("copy_answers", True) \
                    and clipboard(entry[1]):
                notify("Hermes · copied", "Answer is on the clipboard.",
                       "edit-copy", "low", conf)
            elif entry:
                notify(f"Hermes · {clip(text, 60)}", entry[1],
                       "help-browser", "normal", conf)
        elif act == "askagain":
            ctx.cache.drop(key)
            ctx.fetch_answer(text)
        elif act == "reshow":
            if entry:
                notify(f"Hermes · {clip(text, 60)}", entry[1],
                       "help-browser", "normal", conf)
    elif kind == "web":
        # F-2: one verb — Enter opens the browser search; other ids no-op.
        if act == "":
            target = web_target(conf, text)
            try:
                subprocess.Popen(["xdg-open", target],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                log("xdg-open missing; web search skipped:", target)
    elif kind == "error":
        if act in ("", "askagain"):
            ctx.cache.drop(key)
            ctx.fetch_answer(text)
        elif act == "copy":
            clipboard(text)
    elif kind == "handoff":
        # F-5: key is "<prefix>:<lowercased q>"; text is the ORIGINAL-CASE
        # query from the payload map. Only Enter opens; row has actions: [].
        p, _, _ = key.partition(":")
        h = next((x for x in conf.get("_handoffs", ())
                  if x["prefix"] == p), None)
        if h and act == "":
            subprocess.Popen(
                ["xdg-open", h["url"].replace(
                    "%s", urllib.parse.quote_plus(text or key.partition(":")[2]))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif kind == "task":
        if act in ("", "askagain"):
            ctx.fire_task(text)
        elif act == "copy":
            clipboard(text)
    elif kind == "taskrun":
        info = ctx.running_tasks.get(key)
        if act == "" and info:
            notify("Hermes · still running",
                   f"{text}\nstarted {age_str(info['start'])} ago\n\n"
                   f"{clean_tail(info['logf'])}",
                   "chronometer", "low", conf)
        elif act == "copy":
            clipboard(text)
    # help rows: no-op


class HermesRunner(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJ_PATH)
        self.conf = load_conf()
        self.cache = AnswerCache()
        self.fetching = set()
        self.fetch_lock = threading.Lock()
        self.payload = {}         # row id -> original-case text (B-4)
        self.running_tasks = {}   # qh -> {"pid","start","logf"} (B-6)
        self.task_lock = threading.Lock()

    # ---- background LLM fetch (never on the DBus dispatch thread) ----
    def fetch_answer(self, question):
        qh = question.strip().lower()
        with self.fetch_lock:
            if qh in self.fetching:
                return
            self.fetching.add(qh)

        def work():
            conf = self.conf
            url = conf["litellm"]["base_url"].rstrip("/") + "/chat/completions"
            payload = json.dumps({
                "model": conf["litellm"]["model"],
                "messages": [{"role": "user", "content": question}],
                "max_tokens": 300, "temperature": 0.3,
            }).encode()
            req = urllib.request.Request(url, data=payload, headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {litellm_key(conf)}",
            })
            try:
                with urllib.request.urlopen(
                        req, timeout=conf["litellm"].get("timeout_s", 45)) as r:
                    data = json.loads(r.read())
                answer = data["choices"][0]["message"]["content"].strip()
                self.cache.put(qh, "answer", answer)
                notify(f"Hermes · {clip(question, 60)}", answer,
                       "help-browser", "normal", conf)
            except Exception as e:
                log("ask failed:", repr(e))
                reason = humanize(e, conf)
                self.cache.put(qh, "error", reason)
                notify("Hermes · ask failed",
                       f"{question}\n{reason}\nEnter on the error row retries.",
                       "dialog-error", "normal", conf)
            finally:
                with self.fetch_lock:
                    self.fetching.discard(qh)
        threading.Thread(target=work, daemon=True).start()

    # ---- 'hr <task>' lane: one-shot hermes -z turn ----
    def fire_task(self, task):
        key = task.strip().lower()
        with self.task_lock:
            if key in self.running_tasks:  # double-fire guard (B-6)
                info = self.running_tasks[key]
                notify("Hermes · already running",
                       f"{task}\nstarted {age_str(info['start'])} ago · "
                       f"log: {info['logf']}",
                       "chronometer", "low", self.conf)
                return
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        logf = CACHE_DIR / f"task-{int(time.time())}.log"
        # hermes_exe override exists so the harness can cover this lane with
        # a stub (a real hermes -z turn is never spawned in the gate).
        exe = self.conf.get("hermes_exe")
        if not exe:
            exe = shutil.which("hermes", path=os.path.expanduser(
                "~/.local/bin") + ":" + os.environ.get("PATH", ""))
        if not exe:
            exe = str(Path("~/.hermes/hermes-agent/venv/bin/hermes").expanduser())
        if not Path(exe).exists():
            notify("Hermes · task failed",
                   f"{task}\nhermes executable not found ({exe})",
                   "dialog-error", "critical", self.conf)
            return
        with logf.open("w") as fh:
            proc = subprocess.Popen([exe, "-z", task], stdout=fh,
                                    stderr=subprocess.STDOUT,
                                    start_new_session=True)
        with self.task_lock:
            self.running_tasks[key] = {"pid": proc.pid, "start": time.time(),
                                       "logf": str(logf)}
        notify("Hermes · task started", f"{task}\nlog: {logf}",
               "system-run", "low", self.conf)

        def watch():
            warned_cap = False
            deadline = time.time() + 3600  # watch at most 1 h total
            while time.time() < deadline:
                time.sleep(1)
                # poll() reaps; os.kill(pid,0) SUCCEEDS on zombies, so a
                # kill-based loop never sees the child die and the registry
                # leaks "Running" forever (live-caught 2026-10-30).
                if proc.poll() is not None:
                    with self.task_lock:
                        self.running_tasks.pop(key, None)
                    notify("Hermes · task done", clean_tail(logf),
                           "task-complete", "normal", self.conf)
                    return
                if not warned_cap and time.time() - self.running_tasks.get(
                        key, {}).get("start", 0) >= 900:
                    warned_cap = True
                    notify("Hermes · still running",
                           f"15 min watch cap hit; hermes -z continues.\n"
                           f"log: {logf}\n\n{clean_tail(logf)}",
                           "clock", "normal", self.conf)
            notify("Hermes · watch ended",
                   f"still running after 1 h; no longer watched.\nlog: {logf}",
                   "clock", "normal", self.conf)
        threading.Thread(target=watch, daemon=True).start()

    # ------------------------------------------------------------ krunner1
    @dbus.service.method(IFACE, in_signature="s",
                         out_signature="a(sssida{sv})")
    def Match(self, query):
        # Pure display; I/O happens only in Run() (UX-SPEC P0-2).
        rows = route(query, self.cache, self.fetching, self.running_tasks,
                     self.conf)
        out = []
        # id→payload map: preserve ORIGINAL CASE for ask/task/web/handoff
        # round-trips — derived from the NORMALIZED query (dictated phrases
        # must not carry "hermes about …" into the payload), v0.2.3.
        q = normalize(query or "", self.conf).strip()
        words = q.split(" ", 1)
        payload_text = words[1].strip() if len(words) > 1 else ""
        for (mid, title, subtext, icon, catrel, rel, props) in rows:
            if payload_text and (mid.startswith("ask:")
                                 or mid.startswith("task:")
                                 or mid.startswith("web:")
                                 or mid.startswith("handoff:")):
                self.payload[mid] = payload_text
                if len(self.payload) > 256:
                    self.payload.pop(next(iter(self.payload)))
            dprops = {}
            if subtext:
                dprops["subtext"] = dbus.String(subtext)
            if props.get("multiline"):
                # dbusrunner reads lowercase 'multiline' (UX-SPEC P1).
                dprops["multiline"] = dbus.Boolean(True)
            if "actions" in props:
                dprops["actions"] = dbus.Array(
                    [dbus.String(a) for a in props["actions"]], signature="s")
            out.append((dbus.String(mid), dbus.String(title), dbus.String(icon),
                        dbus.Int32(catrel), dbus.Double(rel), dprops))
        return out

    @dbus.service.method(IFACE, in_signature="ss")
    def Run(self, id, actionId):
        mid, act = str(id), str(actionId or "")
        raw = mid.split(":", 1)
        kind, key = raw[0], (raw[1] if len(raw) > 1 else "")
        # Original-case text from the payload map; the (lowercased) id tail
        # is the graceful fallback after a daemon restart.
        text = self.payload.get(mid, key)
        run_dispatch(kind, key, text, act, self)

    @dbus.service.method(IFACE, out_signature="a(sss)")
    def Actions(self):
        return [
            ("copy", "COPY", "edit-copy"),
            ("askagain", "ASK AGAIN", "view-refresh"),
            ("reshow", "SHOW AGAIN", "help-browser"),
        ]

    @dbus.service.method(IFACE, in_signature="s")
    def SetActivationToken(self, token):
        pass  # KRunner fire-and-forgets this before Run on Wayland


# -------------------------------------------------------------------- main

def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    runner = HermesRunner(bus)  # noqa: F841 — keeps refs alive
    loop = GLib.MainLoop()

    def reload_conf(*_):
        runner.conf = load_conf()
        log("config reloaded")

    import signal
    signal.signal(signal.SIGHUP, lambda *_: GLib.idle_add(reload_conf))
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())

    bus_name = dbus.service.BusName(BUS_NAME, bus)  # noqa: F841
    log(f"ready on {BUS_NAME}{OBJ_PATH}")
    loop.run()


if __name__ == "__main__":
    main()
