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

import apps_model

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
    "models": ["local-fast", "local-heavy", "local-fast-reason",
               "cloud-dev"],
    "app_pins": [],
    "app_categories": {},
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
                conf.get("task_prefix", "hr"), "hermes",
                "ssh", "help", "apps"}   # F-9/F-11 + §L-1: lane claims
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


def parse_ssh_config(text, _depth=0):
    """F-9: foyer-based ~/.ssh/config parser, extended: Host groups share
    Hostname/Port/User; globs (* ?) and negated (!name) hosts are skipped;
    Include directives are followed one level (~ + glob, missing skipped).
    `name` is the lowercase match key, `display` the original case."""
    hosts, group = [], []
    for raw in str(text or "").split("\n"):
        line = re.sub(r"\s+#.*$", "", raw)
        m = re.match(r"^Host\s+(.+)$", line, re.I)
        if m:
            group = []
            for name in m.group(1).strip().split():
                if re.search(r"[*?!]", name):
                    continue
                entry = {"name": name.lower(), "display": name,
                         "hostname": "", "port": "", "user": ""}
                group.append(entry)
                hosts.append(entry)
            continue
        inc = re.match(r"^Include\s+(.+)$", line.strip(), re.I)
        if inc and _depth < 1:
            arg = inc.group(1).strip()
            base = Path(arg).expanduser()
            paths = sorted(base.parent.glob(base.name)) \
                if any(c in arg for c in "*?") else [base]
            for path in paths:
                try:
                    hosts += parse_ssh_config(path.read_text(), _depth + 1)
                except OSError:
                    pass   # missing include: silently skipped (spec F-9)
            continue
        if not group:
            continue
        p = re.match(r"^(Hostname|Port|User)\s+(.+)$", line.strip(), re.I)
        if p:
            key = p.group(1).lower()
            for e in group:
                e[key] = p.group(2).strip()
    return hosts


def sanitize_snippets(raw):
    """F-10: foyer-identical snippet sanitize. Names ^[a-z0-9][a-z0-9-]{0,15}$,
    unique, not reserved ('help'); text non-empty single-line <=2000."""
    out, seen = [], set()
    for s in raw if isinstance(raw, list) else []:
        if not isinstance(s, dict):
            continue
        name_raw = s.get("name")
        if not isinstance(name_raw, str):
            continue                       # numbers/null never become names
        name = name_raw.strip()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,15}", name):
            continue                       # validate RAW: no silent lowering
        text = str(s.get("text") or "")
        if name in seen or name == "help":
            continue
        if not text.strip() or len(text) > 2000 or "\n" in text:
            continue
        seen.add(name)
        out.append({"name": name, "text": text})
    return out


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
    # F-9/F-11 bidirectional lane claims: a configured answer/task prefix
    # equal to a lane claim would shadow that lane — reset to the default.
    for pk in ("answer_prefix", "task_prefix"):
        if conf.get(pk) in ("ssh", "help", "hermes", "apps"):
            log(f"{pk} '{conf[pk]}' collides with a lane claim; "
                f"reset to default")
            conf[pk] = "ai" if pk == "answer_prefix" else "hr"
    conf["_snippets"], sskipped = sanitize_snippets(conf.get("snippets")), 0
    if len(conf["_snippets"]) != len(conf.get("snippets") or []):
        sskipped = len(conf.get("snippets") or []) - len(conf["_snippets"])
    if sskipped:
        log(f"{sskipped} snippet entries skipped (sanitize)")
    # §L-8: load-time sanitize for launcher config (never fatal)
    conf["_app_pins"], pskip = apps_model.sanitize_pins(conf.get("app_pins"))
    if pskip:
        log(f"{pskip} app_pins entries skipped (sanitize)")
    conf["_app_cats"], cskip = apps_model.sanitize_cat_overrides(
        conf.get("app_categories"), logger=lambda m: log("WARN", m))
    if cskip:
        log(f"{cskip} app_categories entries skipped (sanitize)")
    try:
        conf["_ssh_hosts"] = parse_ssh_config(
            Path("~/.ssh/config").expanduser().read_text())
    except OSError:
        conf["_ssh_hosts"] = []   # no ssh config: lane shows its help rows
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

def route(query, cache, fetching, running, conf, stats=None, appstore=None):
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
        # F-7 model subcommand — claimed only on exact word matches.
        model_help = None
        models = [m for m in conf.get("models", ())
                  if isinstance(m, str) and m.strip()]
        if rest.split(" ")[0] == "model" and models:
            if len(rest.split(" ")) == 1 or \
                    (len(rest.split(" ")) == 2
                     and rest.split(" ")[1].lower() == model.lower()):
                # bare list, or switch-to-self: current pinned above others;
                # the 0.02 steps count non-current rows only (spec F-7)
                j = 0
                for m in models:
                    if m == model:
                        row(f"model-cur:{m}", f"Model: {m}",
                            "CURRENT · ANSWERS USE THIS MODEL",
                            "cpu", R_MODERATE, 0.55, {"actions": []})
                    else:
                        row(f"model:{m}", f"Model: {m}",
                            f"ENTER SWITCHES · PERSISTS TO CONFIG · "
                            f"ANSWERS MOVE TO {m}",
                            "cpu", R_MODERATE, round(0.5 - 0.02 * j, 2),
                            {"actions": []})
                        j += 1
                return out
            canon = next((m for m in models
                          if m.lower() == rest.split(" ")[1].lower()), None)
            if canon:
                row(f"model:{canon}", f"Switch to {canon}",
                    "ENTER SWITCHES THE AI LANE · PERSISTS TO CONFIG",
                    "cpu", R_HIGHEST, 1.0, {"actions": []})
                return out
            # unknown: question survives (never-hijack) + one typo-help row
            shown = ", ".join(models[:3])
            more = len(models) - 3
            model_help = ("No such model: " + rest.split(" ")[1],
                          "VALID · " + shown + (f" +{more} MORE"
                                                if more > 0 else ""))
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
        if model_help:
            # F-7 unknown-model help rides under the question rows (0.5).
            row("model-help", model_help[0], model_help[1],
                "help-browser", R_MODERATE, 0.5, {"actions": []})
        return out

    if first == "apps":
        # §L launcher lane: favorites, categories, fuzzy — one prefix,
        # native app search untouched (no-duplication rule).
        if appstore is None:
            row("apphelp", "App index not loaded",
                "DAEMON STILL WARMING · RETRY IN A MOMENT",
                "help-browser", R_MODERATE, 0.5)
            return out
        freq = {}
        if stats is not None:
            m = stats.data.get("app_launches")
            freq = m if isinstance(m, dict) else {}
        seen_dead = set()

        def dead_pin(pid, _seen=seen_dead):
            if pid not in _seen:      # one journal line per id per lifetime
                _seen.add(pid)
                log(f"dead pin skipped: {pid}")

        try:
            snap = appstore.snapshot()
        except Exception as e:
            log(f"apps snapshot failed: {e}")
            snap = []
        for r in apps_model.build_rows(
                snap, conf.get("_app_pins") or [], freq,
                conf.get("_app_cats") or {}, rest,
                menu=appstore.menu or None,
                kickoff=appstore.kickoff_favorites(),
                dead_pin_logger=dead_pin):
            tier = {"HIGHEST": R_HIGHEST, "HIGH": R_HIGH,
                    "MODERATE": R_MODERATE}[r["tier"]]
            row(r["id"], r["title"], r["sub"], r["icon"], tier, r["rel"],
                {"actions": r["actions"]})
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

    # F-9 ssh lane: claimed iff the first word is exactly "ssh".
    if first == "ssh":
        hosts = conf.get("_ssh_hosts") or []

        def ssh_subtext(h):
            target = (f"{h['user']}@" if h["user"] else "") + \
                     (h["hostname"] or h["display"])
            if h["port"]:
                target += f":{h['port']}"
            return f"CONNECT {target} · ENTER OPENS TERMINAL"

        if not rest:
            row("ssh-help", "SSH — type a host after 'ssh'",
                "HOSTS COME FROM ~/.ssh/config · "
                "TYPE 'hermes ssh' FOR DETAILS",
                "utilities-terminal", R_MODERATE, 0.55, {"actions": []})
            for i, h in enumerate(sorted(hosts,
                                         key=lambda x: x["name"])[:5]):
                row(f"ssh:{h['name']}", f"SSH {h['display']}",
                    ssh_subtext(h), "utilities-terminal", R_MODERATE,
                    round(0.5 - 0.02 * i, 2), {"actions": []})
            return out
        t = rest.lower()

        def ssh_rank(h):
            n = h["name"]
            if n == t:
                return (0, n)
            if n.startswith(t):
                return (1, n)
            if t in n:
                return (2, n)
            return (3, n)

        matches = sorted((h for h in hosts
                          if h["name"] == t or h["name"].startswith(t)
                          or t in h["name"]), key=ssh_rank)[:8]
        if not matches:
            row("ssh-help", f"No host matches '{rest}'",
                "HOSTS COME FROM ~/.ssh/config",
                "utilities-terminal", R_MODERATE, 0.5, {"actions": []})
        else:
            for h in matches:
                row(f"ssh:{h['name']}", f"SSH {h['display']}",
                    ssh_subtext(h), "utilities-terminal",
                    R_HIGHEST, 1.0, {"actions": []})
        return out

    # F-10 snippets lane: claimed on the leading ';'.
    if q.startswith(";"):
        body = q[1:].strip()
        snips = conf.get("_snippets") or []
        if body in ("", "help"):
            if not snips:
                row("snippet-help", "No snippets yet",
                    "TYPE ;name text… TO SAVE ONE · "
                    "SNIPPETS LIVE IN config.json",
                    "text-x-generic", R_MODERATE, 0.5, {"actions": []})
                return out
            for i, s in enumerate(snips[:8]):
                rel = 0.55 if i == 0 else round(0.5 - 0.02 * (i - 1), 2)
                row(f"snippet:{s['name']}", s["name"],
                    f"{clip(s['text'], 80)} · ENTER COPIES",
                    "text-x-generic", R_MODERATE, rel,
                    {"actions": ["copy", "show", "delete"]})
            if len(snips) > 8:
                row("snippet-more", f"+{len(snips) - 8} more snippets",
                    "ALL IN config.json",
                    "text-x-generic", R_MODERATE, 0.34, {"actions": []})
            return out
        parts = body.split(" ", 1)
        name = parts[0].lower()
        text = parts[1].strip() if len(parts) > 1 else ""
        # validate the RAW token — `;Sig text` is invalid, never silently
        # lowered to a save row (same rule as sanitize_snippets)
        valid = bool(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,15}", parts[0])) \
            and name != "help"
        hit = next((s for s in snips if s["name"] == name), None)
        if hit:
            row(f"snippet:{name}", name,
                f"{clip(hit['text'], 80)} · ENTER COPIES",
                "text-x-generic", R_HIGHEST, 1.0, {"actions": []})
            if text:
                row(f"snippet-save:{name}",
                    f"Overwrite '{name}' with new text",
                    f"{clip(text, 80)} · ENTER REPLACES THE SNIPPET",
                    "text-x-generic", R_MODERATE, 0.5, {"actions": []})
        elif valid and text:
            row(f"snippet-save:{name}", f"Save snippet '{name}'",
                f"{clip(text, 80)} · ENTER SAVES · THEN ;{name} COPIES",
                "text-x-generic", R_HIGHEST, 1.0, {"actions": []})
        else:
            title = f"No such snippet: {name}" if valid \
                else f"Invalid snippet name: {name}"
            row("snippet-help", title,
                "VALID NAMES a-z 0-9 - MAX 16 · TYPE ';' TO LIST",
                "help-browser", R_MODERATE, 0.5, {"actions": []})
        return out

    # F-11 layered help: `hermes` / `help` index + `hermes <lane>` pages.
    if first in ("hermes", "help"):
        handoffs = list(conf.get("_handoffs") or ())
        lane = rest.lower().strip()

        def help_index():
            row("help-ai", "Hermes: ask with 'ai <question>'",
                f"NOTIFIED ANSWER, THEN CACHED INLINE · {model} VIA LITELLM",
                "help-browser", R_MODERATE, 0.55, {"actions": []})
            row("help-hr", "Hermes: run a task with 'hr <task>'",
                "UNATTENDED AGENT TURN · TYPE 'hermes hr' FOR DETAILS",
                "system-run", R_MODERATE, 0.50, {"actions": []})
            row("help-dictation",
                "Hermes: dictate — 'ask hermes …' answers, "
                "'tell hermes …' runs",
                "VOXTYPE PHRASES FOLD INTO THE ai/hr LANES",
                "help-browser", R_MODERATE, 0.45, {"actions": []})
            row("help-ssh", "Hermes: connect with 'ssh <host>'",
                "HOSTS FROM ~/.ssh/config · ENTER OPENS TERMINAL",
                "utilities-terminal", R_MODERATE, 0.43, {"actions": []})
            row("help-snippet", "Hermes: copy snippets with ';name'",
                "SAVE WITH ;name text… · TYPE 'hermes snippets' FOR DETAILS",
                "text-x-generic", R_MODERATE, 0.42, {"actions": []})
            row("help-model", "Hermes: switch AI model with 'ai model'",
                f"CURRENT {model} · TYPE 'hermes model' FOR DETAILS",
                "cpu", R_MODERATE, 0.41, {"actions": []})
            shown = handoffs[:8]
            for i, h in enumerate(shown):
                row(f"help-handoff-{h['prefix']}",
                    f"Hermes: hand off with '{h['prefix']} <query>'",
                    f"SEARCHES {h['host']} · OPENS IN BROWSER",
                    "internet-web-browser", R_MODERATE,
                    round(0.40 - 0.01 * i, 2), {"actions": []})
            if len(handoffs) > 8:
                row("help-handoff-more",
                    f"+{len(handoffs) - 8} more handoffs",
                    "TYPE 'hermes handoffs'",
                    "internet-web-browser", R_MODERATE, 0.30,
                    {"actions": []})
            row("help-docs", "Hermes: open the full manual",
                "README VIA XDG-OPEN · ALL CONFIG IN config.json",
                "help-browser", R_MODERATE, 0.30, {"actions": []})
            # §L-8: launcher lane rides last in the fixed-rel ladder
            row("help-apps", "Hermes: browse apps with 'apps'",
                "PINS · CATEGORIES · MOST-USED · TYPE 'hermes apps' "
                "FOR DETAILS",
                "start-here-kde", R_MODERATE, 0.29, {"actions": []})

        def helppage(lane_id, n, title, sub, copyable=False):
            row(f"helppage:{lane_id}:{n}", title, sub, "help-browser",
                R_MODERATE, round(0.5 - 0.02 * n, 2),
                {"actions": ["copy"]} if copyable else {"actions": []})

        if lane == "":
            help_index()
        elif lane == "ssh":
            helppage("ssh", 0, "ssh <host>",
                     "CONNECT FROM ~/.ssh/config · ENTER OPENS TERMINAL",
                     copyable=True)
            helppage("ssh", 1, "Short multi-name aliases: Host aic aicube",
                     "BOTH NAMES SHARE HOSTNAME/USER/PORT · TYPED PREFIX "
                     "IS THE WHOLE NAME")
            helppage("ssh", 2, "Include directives are followed",
                     "ONE LEVEL · MISSING FILES SKIPPED")
        elif lane == "snippets":
            helppage("snippets", 0, ";name",
                     "COPIES THE SNIPPET · SAVE WITH ;name text…",
                     copyable=True)
            helppage("snippets", 1, "; sig Greg DeYoung",
                     "EXAMPLE SAVE — ENTER CREATES, RETYPE OVERWRITES")
            helppage("snippets", 2, "Row buttons: COPY · SHOW · DELETE",
                     "DELETE NOTIFICATION CARRIES THE TEXT FOR UNDO")
            helppage("snippets", 3, "Snippets live in config.json",
                     "NAMES a-z 0-9 - MAX 16 · SINGLE LINE MAX 2000 CHARS")
        elif lane == "model":
            helppage("model", 0, "ai model",
                     "LISTS ALIASES · CURRENT MARKED · ENTER SWITCHES",
                     copyable=True)
            helppage("model", 1, "ai model local-heavy",
                     "SWITCHES AND PERSISTS · CASE-INSENSITIVE",
                     copyable=True)
            helppage("model", 2, "Aliases come from config 'models'",
                     "EDIT THE LIST · HUP RELOADS")
        elif lane == "ai":
            helppage("ai", 0, "ai <question>",
                     "ONE-SHOT ANSWER · NOTIFIED, THEN CACHED INLINE",
                     copyable=True)
            helppage("ai", 1, "ai who runs searxng",
                     "EXAMPLE ASK · RETYPE TO READ THE CACHED ANSWER INLINE",
                     copyable=True)
            helppage("ai", 2, "Answers carry COPY · ASK AGAIN · SHOW AGAIN",
                     "THE WEB-SEARCH SIBLING ROW OPENS THE BROWSER")
        elif lane == "hr":
            helppage("hr", 0, "hr <task>",
                     "UNATTENDED hermes -z TURN · NOTIFIED WHEN DONE",
                     copyable=True)
            helppage("hr", 1, "hr check disk space on aicube",
                     "EXAMPLE TASK · LOG IN ~/.cache/hermes-runner",
                     copyable=True)
        elif lane == "dictation":
            helppage("dictation", 0, "ask hermes about dns",
                     "FOLDS INTO ai dns — ANSWER LANE", copyable=True)
            helppage("dictation", 1, "tell hermes to restart docker",
                     "FOLDS INTO hr restart docker — TASK LANE",
                     copyable=True)
        elif lane == "apps":
            # §L-8: launcher-lane help block (foyer-browse grammar)
            helppage("apps", 0, "apps",
                     "FAVORITES FIRST, THEN PINS, MOST-USED, CATEGORIES",
                     copyable=True)
            helppage("apps", 1, "apps games · apps internet fire…",
                     "CATEGORY VIEW · REMAINING WORDS FILTER BY NAME · "
                     "'more' = UNFILED APPS",
                     copyable=True)
            helppage("apps", 2, "apps pins",
                     "ALL FAVORITES + YOUR PINS TOGETHER",
                     copyable=True)
            helppage("apps", 3, "Favorites mirror the KDE menu",
                     "MANAGE THEM THERE (DRAG IN MENU) — PIN/UNPIN ONLY "
                     "AFFECTS HERMES PINS SHOWN BENEATH")
            helppage("apps", 4, "App rows: ENTER launches · PIN pins",
                     "UNPIN REMOVES · PINS SURVIVE REBOOT (config.json)")
            helppage("apps", 5, "Plain app names stay native",
                     "'firef' HITS KRUNNER'S OWN APP SEARCH — NO TWINS")
        elif lane == "handoffs":
            for i, h in enumerate(handoffs[:6]):
                helppage("handoffs", i, f"{h['prefix']} <query>",
                         f"{h['label'].upper()} — SEARCHES {h['host']}",
                         copyable=True)
            helppage("handoffs", min(len(handoffs), 6),
                     "Handoffs live in config.json",
                     "PREFIX 2-6 LETTERS · ONE %s IN URL · HUP RELOADS")
        elif lane == "docs":
            row("help-docs", "Hermes: open the full manual",
                "README VIA XDG-OPEN · ALL CONFIG IN config.json",
                "help-browser", R_MODERATE, 0.30, {"actions": []})
        else:
            help_index()   # unknown lane: the index IS the correction
        return out

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
                "internet-web-browser", R_MODERATE, 0.55,
                {"actions": []})
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

def persist_model(name):
    """F-7: read-modify-write config.json — only litellm.model changes,
    unknown keys preserved. Returns (ok, reason)."""
    try:
        try:
            raw = json.loads(CONF_PATH.read_text())
            if not isinstance(raw, dict):
                raw = {}
        except FileNotFoundError:
            raw = {}
        lit = raw.get("litellm")
        if not isinstance(lit, dict):
            lit = {}
            raw["litellm"] = lit
        lit["model"] = name
        tmp = str(CONF_PATH) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(raw, f, indent=1)
        os.replace(tmp, str(CONF_PATH))
        return True, ""
    except Exception as e:  # never fatal: in-memory switch still sticks
        return False, str(e)


def persist_snippets(snips):
    """F-10: read-modify-write config.json — only `snippets` changes,
    unknown keys preserved (F-7 pattern). Returns (ok, reason)."""
    try:
        try:
            raw = json.loads(CONF_PATH.read_text())
            if not isinstance(raw, dict):
                raw = {}
        except FileNotFoundError:
            raw = {}
        raw["snippets"] = snips
        tmp = str(CONF_PATH) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(raw, f, indent=1)
        os.replace(tmp, str(CONF_PATH))
        return True, ""
    except Exception as e:
        return False, str(e)


ACTIONS_LIST = [
    ("copy", "COPY", "edit-copy"),
    ("askagain", "ASK AGAIN", "view-refresh"),
    ("reshow", "SHOW AGAIN", "help-browser"),
    ("show", "SHOW", "help-browser"),
    ("delete", "DELETE", "edit-delete"),
    ("launch", "LAUNCH", "system-run"),          # §L-5 app rows
    ("pin", "PIN", "bookmark-new"),
    ("unpin", "UNPIN", "list-remove"),
    ("apps", "APPS", "start-here-kde"),          # §L-7 empty-state
    ("fav", "FAVORITES", "bookmarks"),
]


def web_target(conf, text):
    """F-2: substitute the ORIGINAL-CASE question into web_search_url."""
    url = conf.get("web_search_url", "https://duckduckgo.com/?q=%s")
    return url.replace("%s", urllib.parse.quote_plus(text or ""))


class Stats:
    """F-8: adoption counters. Counts ONLY — query text is never stored.

    Written on every event (write-temp + rename, chmod 600) so SIGTERM
    cannot lose data. Hit from run_dispatch (Run-only — Match fires per
    keystroke and would inflate everything).
    """

    KEYS = ("asks", "tasks", "answer_uses", "error_retries", "web_opens",
            "recents_copies", "model_switches", "dictation_hits",
            "ssh_sessions", "snippet_uses", "snippet_edits",
            "app_pins_set", "app_pins_removed", "app_browses")

    def __init__(self, path=None):
        base = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
        self.path = path or os.path.join(base, "hermes-runner", "stats.json")
        self.lock = threading.Lock()
        self.data: dict = {"days": {}}
        try:
            with open(self.path, encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                self.data.update(loaded)
                self.data.setdefault("days", {})
        except (OSError, ValueError):
            pass  # fresh start; never fatal
        self._write()

    def hit(self, name, prefix=None):
        maps = ("handoffs", "app_launches")   # app_launches: §L-5 lifetime
        if name not in self.KEYS and name not in maps:
            return
        day = time.strftime("%Y-%m-%d")
        with self.lock:
            d = self.data["days"].get(day)
            if not isinstance(d, dict):
                d = {}
                self.data["days"][day] = d
            if name in maps:
                m = self.data.get(name)
                if not isinstance(m, dict):
                    m = {}
                    self.data[name] = m
                m[prefix] = int(m.get(prefix, 0)) + 1
                if name == "handoffs":   # per-day map for handoffs only
                    dh = d.get("handoffs")
                    if not isinstance(dh, dict):
                        dh = {}
                        d["handoffs"] = dh
                    dh[prefix] = int(dh.get(prefix, 0)) + 1
            else:
                self.data[name] = int(self.data.get(name, 0)) + 1
                d[name] = int(d.get(name, 0)) + 1
            self._write()

    def _write(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=1, sort_keys=True)
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.path)

    def report(self):
        totals = {k: self.data.get(k, 0) for k in self.KEYS
                  if k in self.data}
        totals["handoffs"] = self.data.get("handoffs", {})
        totals["app_launches"] = self.data.get("app_launches", {})
        return json.dumps({"totals": totals, "days": self.data["days"]},
                          indent=1, sort_keys=True)


def persist_app_pins(pins):
    """§L-5: read-modify-write config.json — only `app_pins` changes,
    unknown keys preserved (persist_snippets pattern). (ok, reason)."""
    try:
        try:
            raw = json.loads(CONF_PATH.read_text())
            if not isinstance(raw, dict):
                raw = {}
        except FileNotFoundError:
            raw = {}
        raw["app_pins"] = pins
        tmp = str(CONF_PATH) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(raw, f, indent=1)
        os.replace(tmp, str(CONF_PATH))
        return True, ""
    except Exception as e:
        return False, str(e)


def toggle_app_pin(app_id, act, name, conf, stats):
    """§L-5: flip membership, persist, notify (B-9 channel)."""
    pins = list(conf.get("_app_pins") or [])
    if act == "pin":
        if app_id not in pins:
            pins.append(app_id)
        key, title = "app_pins_set", "pinned"
    else:
        pins = [p for p in pins if p != app_id]
        key, title = "app_pins_removed", "unpinned"
    ok, why = persist_app_pins(pins)
    if ok:
        conf["_app_pins"] = pins
        if stats:
            stats.hit(key)
        notify(f"Hermes · {title}",
               f"{clip(name or app_id, 60)} · {len(pins)} pins",
               "bookmarks", "low", conf)
    else:
        notify("Hermes · pin not written",
               f"kept in memory · {clip(why, 80)}",
               "dialog-error", "low", conf)


def launch_app(app, conf, stats):
    """§L-6: launch by id via kioclient (gtk-launch fallback). The Exec=
    string is NEVER turned into an argv — KDE's launcher owns it."""
    if shutil.which("kioclient"):
        argv = ["kioclient", "exec", app["path"]]
    elif shutil.which("gtk-launch"):
        argv = ["gtk-launch", app["id"]]
    else:
        notify("Hermes · cannot launch",
               "no kioclient / gtk-launch on PATH",
               "dialog-error", "low", conf)
        return False
    try:
        subprocess.Popen(argv, start_new_session=True, close_fds=True,
                         cwd="/", stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    except OSError as e:
        notify("Hermes · cannot launch", clip(str(e), 80),
               "dialog-error", "low", conf)
        return False
    if stats:
        stats.hit("app_launches", prefix=app["id"])
    return True


def run_dispatch(kind, key, text, act, ctx):
    conf = ctx.conf
    stats = getattr(ctx, "stats", None)   # F-8; absent in old test ctxs

    if kind == "" and act in ("apps", "fav"):
        # §L-7 empty-state action buttons (when plasma renders them):
        # re-drive the KRunner query. Async — see appcat note.
        target = "apps" if act == "apps" else "apps pins"
        log(f"HARNESS-APPACTION {act}")

        def _action_preload(q=target):
            time.sleep(0.25)
            try:
                bus = dbus.SessionBus()
                bus.call_blocking("org.kde.krunner", "/App",
                                  "org.kde.krunner.App", "query", "s", (q,))
            except Exception as e:
                log(f"app action preload failed: {e}")
        threading.Thread(target=_action_preload, daemon=True).start()
        return

    if kind == "ask":
        if act in ("", "askagain"):
            if stats: stats.hit("asks")
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
            if kind == "recent" and stats: stats.hit("recents_copies")
            elif kind == "answer" and stats: stats.hit("answer_uses")
            if entry and conf.get("copy_answers", True) \
                    and clipboard(entry[1]):
                notify("Hermes · copied", "Answer is on the clipboard.",
                       "edit-copy", "low", conf)
            elif entry:
                notify(f"Hermes · {clip(text, 60)}", entry[1],
                       "help-browser", "normal", conf)
        elif act == "askagain":
            if stats: stats.hit("asks")
            ctx.cache.drop(key)
            ctx.fetch_answer(text)
        elif act == "reshow":
            if kind == "answer" and stats: stats.hit("answer_uses")
            if entry:
                notify(f"Hermes · {clip(text, 60)}", entry[1],
                       "help-browser", "normal", conf)
    elif kind == "web":
        # F-2: one verb — Enter opens the browser search; other ids no-op.
        if act == "":
            if stats: stats.hit("web_opens")
            target = web_target(conf, text)
            try:
                subprocess.Popen(["xdg-open", target],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                log("xdg-open missing; web search skipped:", target)
    elif kind == "error":
        if act in ("", "askagain"):
            if stats: stats.hit("error_retries")
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
            if stats: stats.hit("handoffs", prefix=p)
            subprocess.Popen(
                ["xdg-open", h["url"].replace(
                    "%s", urllib.parse.quote_plus(text or key.partition(":")[2]))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif kind == "model":
        # F-7: key is the id tail (canonical alias); re-validate against
        # the allowlist — never trust the wire.
        models = [m for m in conf.get("models", ())
                  if isinstance(m, str) and m.strip()]
        canon = next((m for m in models if m.lower() == key.lower()), None)
        if act == "" and canon:
            conf["litellm"]["model"] = canon
            ok, _why = persist_model(canon)
            if stats: stats.hit("model_switches")
            if ok:
                notify("Hermes · model switched",
                       f"{canon} now answers ai questions",
                       "cpu", "normal", conf)
            else:
                notify("Hermes · switch not saved",
                       f"using {canon} this session · config write failed",
                       "dialog-error", "low", conf)
            log(f"model switch -> {canon} (persisted={ok})")
    elif kind == "model-cur":
        # No dead ids (spec F-7): re-notify the current model.
        if act == "":
            notify("Hermes · model", f"{key} answers ai questions",
                   "cpu", "low", conf)
    elif kind == "model-help":
        pass  # informational row — Run is a no-op by design

    elif kind == "ssh":
        # F-9: Enter opens a terminal. key is the host name; re-resolve
        # from the parsed table — never trust the wire.
        canon = next((h for h in conf.get("_ssh_hosts", ())
                      if h["name"] == key.lower()), None)
        if act == "" and canon:
            if stats: stats.hit("ssh_sessions")
            try:
                subprocess.Popen(
                    ["konsole", "--hold", "-e", "ssh", canon["name"]],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                log("konsole missing; ssh session skipped:", canon["name"])
    elif kind == "snippet":
        # F-10: key is the snippet name; re-resolve from config.
        name = key.lower()
        snip = next((s for s in conf.get("_snippets", ())
                     if s["name"] == name), None)
        if snip and act in ("", "copy"):
            if stats: stats.hit("snippet_uses")
            clipboard(snip["text"])
            notify("Hermes · snippet copied",
                   clip(snip["text"], 120), "edit-copy", "low", conf)
        elif snip and act == "show":
            if stats: stats.hit("snippet_uses")   # credited like reshow
            notify(f"Hermes · {name}", snip["text"],
                   "help-browser", "normal", conf)
        elif snip and act == "delete":
            remaining = [s for s in conf.get("_snippets", ())
                         if s["name"] != name]
            ok, why = persist_snippets(remaining)
            if ok:
                conf["_snippets"] = remaining
                if stats: stats.hit("snippet_edits")
                # recoverable: the full text rides in the notification
                notify("Hermes · snippet deleted",
                       f"{name}\n{snip['text']}",
                       "edit-delete", "normal", conf)
            else:
                notify("Hermes · delete not saved",
                       f"config write failed · {clip(why, 80)}",
                       "dialog-error", "low", conf)
    elif kind == "snippet-save":
        # F-10: key is the name; text is the ORIGINAL-CASE new text.
        # Validate the RAW key — a wire-forged id must not sneak past as a
        # lowercased name (same rule as sanitize_snippets).
        name = key.lower()
        if re.fullmatch(r"[a-z0-9][a-z0-9-]{0,15}", key) and key != "help" \
                and (text or "").strip():
            new = {"name": name, "text": text.strip()[:2000]}
            merged = [s for s in conf.get("_snippets", ())
                      if s["name"] != name] + [new]
            ok, why = persist_snippets(merged)
            if ok:
                conf["_snippets"] = merged
                if stats: stats.hit("snippet_edits")
                notify("Hermes · snippet saved",
                       f";{name} now copies {clip(new['text'], 60)}",
                       "text-x-generic", "low", conf)
            else:
                notify("Hermes · save not written",
                       f"snippet kept in memory · {clip(why, 80)}",
                       "dialog-error", "low", conf)
    elif kind == "helppage":
        if act == "copy":
            clipboard(text)   # payload overridden to the row title
    elif kind == "help-docs":
        if act == "":
            readme = Path(__file__).resolve().parent / "README.md"
            try:
                subprocess.Popen(["xdg-open", str(readme)],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                log("xdg-open missing; docs skipped")

    elif kind == "app":
        # §L-6: launch by id from the enumeration cache only.
        if act in ("pin", "unpin"):
            app = None
            if getattr(ctx, "appstore", None):
                app = ctx.appstore.lookup(key)
            toggle_app_pin(key, act, (app or {}).get("name", ""), conf, stats)
        else:
            app = None
            if getattr(ctx, "appstore", None):
                app = ctx.appstore.lookup(key)
            if app is None:
                log(f"WARN app id not in cache: {key}")
                notify("Hermes · cannot launch",
                       f"unknown app id · {clip(key, 60)}",
                       "dialog-error", "low", conf)
            else:
                launch_app(app, conf, stats)
    elif kind == "appcat":
        # §L-6: drill = re-drive the KRunner query via /App. Async + delayed
        # — a synchronous call back into krunner mid-Run would deadlock.
        slugs = ({m["slug"] for m in ctx.appstore.menu}
                 | {"more", "pins"}          # r3.1 synthetic drill targets
                 if getattr(ctx, "appstore", None) and ctx.appstore.menu
                 else {s for s, _ in apps_model.FALLBACK_LABELS})
        if key in slugs:
            if stats:
                stats.hit("app_browses")
            log(f"HARNESS-APPCAT apps {key}")

            def _preload(slug=key):
                time.sleep(0.25)
                try:
                    bus = dbus.SessionBus()
                    bus.call_blocking("org.kde.krunner", "/App",
                                      "org.kde.krunner.App", "query", "s",
                                      (f"apps {slug}",))
                except Exception as e:
                    log(f"appcat preload failed: {e}")
            threading.Thread(target=_preload, daemon=True).start()
    elif kind in ("apphelp", "apps-root"):
        pass   # §L-4 info/anchor rows — no-op
    elif kind == "task":
        if act in ("", "askagain"):
            if stats: stats.hit("tasks")
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
        self.folded = {}          # row id -> True when minted from a query
                                  # normalize() changed (F-8 dictation credit)
        self.stats = Stats()
        self.appstore = apps_model.AppStore(logger=log)   # §L-2 warm-at-start
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
                     self.conf, self.stats, self.appstore)
        out = []
        # id→payload map: preserve ORIGINAL CASE for ask/task/web/handoff
        # round-trips — derived from the NORMALIZED query (dictated phrases
        # must not carry "hermes about …" into the payload), v0.2.3.
        q = normalize(query or "", self.conf).strip()
        words = q.split(" ", 1)
        payload_text = words[1].strip() if len(words) > 1 else ""
        # F-8: tag non-help rows as dictation-folded when normalize() rewrote
        # the query (compare against the raw query lowercased — case-only
        # changes are not folds).
        folded = (q != (query or "").strip().lower())
        for (mid, title, subtext, icon, catrel, rel, props) in rows:
            if payload_text and (mid.startswith("ask:")
                                 or mid.startswith("task:")
                                 or mid.startswith("web:")
                                 or mid.startswith("handoff:")
                                 or mid.startswith("helppage:")
                                 or mid.startswith("snippet-save:")):
                self.payload[mid] = payload_text
                if len(self.payload) > 256:
                    self.payload.pop(next(iter(self.payload)))
            if mid.startswith("helppage:"):
                # F-11: the copy action copies the example title, not the
                # query that surfaced it.
                self.payload[mid] = title
            if folded and not mid.startswith(
                    ("help-", "model-", "helppage", "snippet", "ssh:")):
                self.folded[mid] = True
                if len(self.folded) > 256:
                    self.folded.pop(next(iter(self.folded)))
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
        # F-8: dictation credit — consumed once per row (per-keystroke Match
        # tagging above just sets the flag).
        if self.folded.pop(mid, None):
            self.stats.hit("dictation_hits")
        run_dispatch(kind, key, text, act, self)

    @dbus.service.method(IFACE, out_signature="a(sss)")
    def Actions(self):
        return list(ACTIONS_LIST)

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
    GLib.idle_add(runner.appstore.warm)   # §L-2: index ready before 1st key
    loop.run()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--stats":
        print(Stats().report())
    else:
        main()
