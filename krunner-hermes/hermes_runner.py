#!/usr/bin/env python3
"""Hermes KRunner DBus runner — 'ai <q>' asks LiteLLM, 'hr <task>' fires Hermes.

Zero-compile Plasma 6 runner: implements org.kde.krunner1 (Match/Run/Actions)
on the session bus; discovered via the .desktop file's X-Plasma-API=DBus keys.
Interface signatures verified live on Plasma 6.7.5 (busctl introspect of the
KWin WindowsRunner, 2026-10-26):
    Match(s)  -> a(sssuda{sv})
    Run(ss)   -> ()
    Actions() -> a(sss)

Design rules:
  - Match() NEVER blocks longer than a few ms: the LLM fetch runs in a
    background thread; the answer is delivered as a desktop notification and
    cached so any re-match of the same query shows it inline (KRunner only
    re-queries on text change — documented behavior, not a bug).
  - Stdlib + python-dbus only (both in the Bazzite base image RPMs:
    python3-dbus, python3-gobject). No pip, no venv.
  - No secrets in code or repo: the LiteLLM key is read at runtime from an
    env var or parsed from a local file (config: api_key_env / api_key_file).

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
import urllib.request
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

BUS_NAME = "org.kde.runners.hermes"
OBJ_PATH = "/hermes"
IFACE = "org.kde.krunner1"

# QueryMatch::Type ints. 1 = ExactMatch is certain; the informational/helper
# values are best-effort (any non-zero int renders fine; grouping only).
T_EXACT, T_INFO, T_HELPER = 1, 70, 90

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
    "notify_icon": "help-browser",
}

CONF_PATH = Path(os.environ.get(
    "HERMES_RUNNER_CONF", "~/.config/hermes-runner/config.json")).expanduser()
CACHE_DIR = Path("~/.cache/hermes-runner").expanduser()

# ---------------------------------------------------------------- utilities

def log(*a):
    print(f"[hermes-runner {time.strftime('%H:%M:%S')}]", *a, file=sys.stderr)


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
    return conf


def litellm_key(conf):
    env = conf["litellm"].get("api_key_env", "")
    if env and os.environ.get(env):
        return os.environ[env]
    keyfile = Path(conf["litellm"].get("api_key_file", "")).expanduser()
    if keyfile.is_file():  # KEY=value lines
        m = re.search(rf'^\s*(?:export\s+)?{env}="?([^"\n]+)"?',
                      keyfile.read_text(), re.M)
        if m:
            return m.group(1).strip()
    return ""


def notify(summary, body, conf):
    body = (body or "")[: conf.get("max_answer_chars", 700)]
    if not conf.get("notify", True):
        log("notify (suppressed):", summary)
        return
    try:
        subprocess.Popen(["notify-send", "-a", "Hermes", "-i",
                          conf.get("notify_icon", "help-browser"),
                          summary, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        log("notify-send missing; notification skipped:", summary)


def clipboard(text):
    try:
        bus = dbus.SessionBus()
        bus.call_blocking("org.kde.klipper", "/klipper", "org.kde.klipper.klipper",
                          "setClipboardContents", "s", (text,))
        return True
    except Exception as e:
        log("clipboard failed:", e)
        return False


# ----------------------------------------------------------------- model(s)

class AnswerCache:
    """query-hash -> (answer, timestamp). Bounded, thread-safe."""
    def __init__(self, size=32):
        self.lock, self.map, self.size = threading.Lock(), {}, size

    def get(self, q):
        with self.lock:
            return self.map.get(q)

    def put(self, q, answer):
        with self.lock:
            if len(self.map) >= self.size:
                self.map.pop(next(iter(self.map)))
            self.map[q] = (answer, time.time())


class HermesRunner(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJ_PATH)
        self.conf = load_conf()
        self.cache = AnswerCache()
        self.fetching = set()
        self.fetch_lock = threading.Lock()

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
                self.cache.put(qh, answer)
                notify(f"Hermes: {question[:60]}", answer, conf)
            except Exception as e:
                answer = f"(ask failed: {e})"
                self.cache.put(qh, answer)
                notify(f"Hermes: ask failed — {question[:40]}", str(e), conf)
            finally:
                with self.fetch_lock:
                    self.fetching.discard(qh)
        threading.Thread(target=work, daemon=True).start()

    # ---- 'hr <task>' lane: one-shot hermes -z turn ----
    def fire_task(self, task):
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        logf = CACHE_DIR / f"task-{int(time.time())}.log"
        exe = shutil.which("hermes", path=os.path.expanduser(
            "~/.local/bin") + ":" + os.environ.get("PATH", ""))
        if not exe:
            exe = str(Path("~/.hermes/hermes-agent/venv/bin/hermes").expanduser())
        if not Path(exe).exists():
            notify("Hermes task failed", f"hermes executable not found ({exe})", self.conf)
            return
        with logf.open("w") as fh:
            proc = subprocess.Popen([exe, "-z", task], stdout=fh,
                                    stderr=subprocess.STDOUT,
                                    start_new_session=True)
        def watch(pid):
            time.sleep(2)
            for _ in range(900):  # up to ~15 min
                try:
                    os.kill(pid, 0)  # raises when the process is gone
                except OSError:
                    break
                time.sleep(1)
            tail = ""
            try:
                tail = logf.read_text()[-400:].strip()
            except Exception:
                pass
            notify(f"Hermes task done: {task[:50]}", tail or "(no output)", self.conf)
        threading.Thread(target=watch, args=(proc.pid,), daemon=True).start()

    # ------------------------------------------------------------ krunner1
    @dbus.service.method(IFACE, in_signature="s",
                         out_signature="a(sssuda{sv})")
    def Match(self, query):
        conf = self.conf
        q = query.strip()
        low = q.lower()
        out = []

        def match(mid, text, icon, mtype, relevance, subtext=None, multi=False):
            props = {}
            if subtext is not None:
                props["subtext"] = dbus.String(subtext)
            if multi:
                props["multiLine"] = dbus.Boolean(True)
            return (dbus.String(mid), dbus.String(text), dbus.String(icon),
                    dbus.UInt32(mtype), dbus.Double(relevance), props)

        ap = conf["answer_prefix"] + " "
        tp = conf["task_prefix"] + " "

        if low.startswith(ap):
            question = q[len(ap):].strip()
            if not question:
                out.append(match("hermes-help-ai",
                                 "Ask Hermes — type your question after 'ai '",
                                 "help-browser", T_INFO, 0.5))
                return out
            warm = self.cache.get(question.lower())
            if warm:
                out.append(match(f"answer:{question.lower()}",
                                 warm[0], "help-browser", T_INFO, 0.95,
                                 subtext="Enter: copy · from LiteLLM "
                                         f"({self.conf['litellm']['model']})",
                                 multi=True))
            else:
                self.fetch_answer(question)
                out.append(match(f"ask:{question.lower()}",
                                 f"Ask Hermes: {question}",
                                 "help-browser", T_EXACT, 1.0,
                                 subtext="answer arrives as a notification; "
                                         "retypes show it inline"))
            return out

        if low.startswith(tp):
            task = q[len(tp):].strip()
            if task:
                out.append(match(f"task:{task.lower()}", f"Hermes task: {task}",
                                 "system-run", T_EXACT, 1.0,
                                 subtext="Enter runs one unattended "
                                         "hermes -z turn; result as notification"))
            return out

        if low in ("hermes", "hermes help", "hr", "ai"):
            out.append(match("hermes-help-1",
                             "Hermes: ask with 'ai <question>'", "help-browser",
                             T_HELPER, 0.9,
                             subtext="one-row answer via LiteLLM "
                                     f"({self.conf['litellm']['model']})"))
            out.append(match("hermes-help-2",
                             "Hermes: task with 'hr <task>'", "system-run",
                             T_HELPER, 0.9,
                             subtext="fires an unattended hermes agent turn"))
        return out

    @dbus.service.method(IFACE, in_signature="ss")
    def Run(self, id, actionId):
        conf = self.conf
        mid = str(id)
        if mid.startswith("answer:"):
            if conf.get("copy_answers", True):
                warm = self.cache.get(mid[len("answer:"):])
                if warm and clipboard(warm[0]):
                    notify("Hermes", "Answer copied to clipboard", conf)
                    return
            notify("Hermes", self.cache.get(mid[len("answer:"):], ("", 0))[0], conf)
        elif mid.startswith("task:"):
            self.fire_task(mid[len("task:"):])
        # ask:* rows: fetch already running; nothing to do on Enter.

    @dbus.service.method(IFACE, out_signature="a(sss)")
    def Actions(self):
        return []


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
