#!/usr/bin/python3
"""
foyer.py — user-space Foyer daemon (no rpm-ostree, no compiled C++).

Architecture (R1.2 user-space contract):
    PySide6 (system rpm, links the SAME Qt 6.11 as the desktop) hosts
    FoyerRoot.qml inside FoyerWindow.qml — a LayerShellQt Layer.Top surface
    (org.kde.layershell QML module, shipped on the host). The daemon stays
    resident (systemd user unit, Type=dbus) so summon = window.show() on a
    warm engine — the krunner pattern without being krunner.

DBus surface (gdeyoung.foyer):
    toggle() / showUI() / hideUI()   — the hotkey targets
    driveState(s)                    — state-driver channel (harness + tests)

The bridge is signal-only: QML never calls into Python, Python never pokes
QML objects; FoyerWindow.qml wires bridge signals to FoyerRoot.gotoState.

Verify in the nested-kwin harness (harness/run-foyer-daemon.sh) — never on
the live session first.
"""
import glob
import json
import os
import socket
import sys
import time

from PySide6.QtCore import (QObject, Property, QCoreApplication, QEvent, Qt,
                            Signal, Slot, QUrl, QPointF)
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtDBus import QDBusConnection

HERE = os.path.dirname(os.path.abspath(__file__))

# --- environment pinning (must precede QGuiApplication construction) --------
# Fractional scaling on a layer-shell surface produced a ~5% hit-test skew
# on the 5120x1440@105% host (clicks landed one row low): run physical 1:1
# and scale the card ourselves (bridge.cardScale). setdefault so a harness
# may still override explicitly.
os.environ.setdefault("QT_ENABLE_HIGHDPI_SCALING", "0")
os.environ.setdefault("QT_SCALE_FACTOR", "1")
os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")

BUS_NAME = "gdeyoung.foyer"
BUS_PATH = "/gdeyoung/foyer"

HARNESS = os.environ.get("FOYER_D_RW") == "1"   # nested-harness marker

# XDG main category -> foyer label (first hit wins; order = priority)
_CATMAP = [
    ("Game", "Games"), ("Network", "Internet"), ("AudioVideo", "Media"),
    ("Graphics", "Graphics"), ("Office", "Office"), ("Utility", "Utilities"),
    ("Development", "Development"), ("Science", "Science"),
    ("Education", "Education"), ("System", "System"),
]
_DESKTOP_DIRS = (
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
)


def scan_apps():
    """Real launcher data: .desktop scan -> categories with real app lists.

    This is the 'live providers' phase the frozen FoyerData.js always
    promised — boot category counts and category contents come from the
    system, not a design-time snapshot. Returns a JSON string.
    """
    import configparser

    seen = {}
    for d in _DESKTOP_DIRS:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            key = os.path.basename(f)
            if key in seen and d == _DESKTOP_DIRS[0]:
                continue  # user/system dirs override /usr/share on revisit
            # KDE settings modules: kcm_*.desktop are 83/84 NoDisplay=true by
            # spec (correct for app menus, wrong for us — Kickoff surfaces
            # them in search). Bypass NoDisplay for kcm_ files, bucket them
            # under Settings. Hidden stays skipped (spec: retired entries).
            is_kcm = key.startswith("kcm_")
            try:
                cp = configparser.ConfigParser(interpolation=None,
                                               strict=False)
                with open(f, encoding="utf-8", errors="ignore") as fh:
                    cp.read_file(fh)
                if not cp.has_section("Desktop Entry"):
                    continue
                de = cp["Desktop Entry"]
                if de.get("Type", "Application") != "Application":
                    continue
                if de.getboolean("NoDisplay", False) and not is_kcm:
                    continue
                if de.getboolean("Hidden", False):
                    continue
                name = de.get("Name", "").strip()
                exec_ = de.get("Exec", "").strip()
                if not name or not exec_:
                    continue
                label = "Settings" if is_kcm else "Other"
                if not is_kcm:
                    cats = (de.get("Categories", "") + ";").split(";")
                    for cid, lab in _CATMAP:
                        if cid in cats:
                            label = lab
                            break
                # spec visibility: NotShowIn hits the current desktop → skip;
                # OnlyShowIn set and current desktop absent → skip
                cur = {s.strip() for s in os.environ.get(
                    "XDG_CURRENT_DESKTOP", "").split(":") if s.strip()}
                nsi = (de.get("NotShowIn", "") + ";").split(";")
                if cur & {s.strip() for s in nsi if s.strip()}:
                    continue
                osi = {s.strip() for s in
                       (de.get("OnlyShowIn", "") + ";").split(";") if s.strip()}
                if osi and not (cur & osi):
                    continue
                seen[key] = (label, name, de.get("GenericName", "").strip(),
                             de.get("Keywords", "").replace(";", " ").strip(),
                             f)
            except Exception:
                continue

    buckets = {}
    for label, name, generic, kws, path in seen.values():
        buckets.setdefault(label, []).append(
            {"name": name, "generic": generic, "keywords": kws,
             "bucket": label, "path": path})
    out = []
    for label, apps in buckets.items():
        if label == "Other" and len(out) >= 9:   # keep the rail tidy
            continue
        apps.sort(key=lambda a: a["name"].lower())
        out.append({"id": label, "label": label, "apps": apps})
    out.sort(key=lambda c: c["label"].lower())
    return json.dumps(out)


# real Qt key delivery (QEvent.KeyPress/Release on the window — delivered
# to the focus object, i.e. the EXACT path a physical keypress takes,
# field Keys-handlers and TextInput cursor logic included)
_REALKEYS = {
    "down": Qt.Key.Key_Down, "up": Qt.Key.Key_Up,
    "left": Qt.Key.Key_Left, "right": Qt.Key.Key_Right,
    "backspace": Qt.Key.Key_Backspace,
    "enter": Qt.Key.Key_Return, "escape": Qt.Key.Key_Escape,
}



# ---- live lanes: ssh aliases, recents, favorites, fleet probe ----------
_SSH_CONFIG = os.path.expanduser("~/.ssh/config")


def parse_ssh_config():
    """Host aliases from ~/.ssh/config — literal names only (no patterns)."""
    hosts, cur = [], None
    try:
        with open(_SSH_CONFIG, errors="ignore") as fh:
            for line in fh:
                s = line.strip()
                low = s.lower()
                if low.startswith("host "):
                    alias = next((n for n in s[5:].split()
                                  if not any(c in n for c in "*?!")), None)
                    cur = {"alias": alias, "ip": "", "note": ""} if alias else None
                    if cur:
                        hosts.append(cur)
                elif cur is not None and low.startswith("hostname "):
                    cur["ip"] = s.split(None, 1)[1].strip()
                elif cur is not None and low.startswith(("user ", "port ")):
                    k, _, v = s.partition(" ")
                    cur["note"] += f"{k.lower()}={v.strip()} " if v.strip() else ""
    except OSError:
        return []
    for h in hosts:
        h["note"] = h["note"].strip()
    return hosts


def scan_recents(limit=12):
    """Recently-used files from the XBEL log: name, app, age, file url."""
    path = os.path.expanduser("~/.local/share/recently-used.xbel")
    if not os.path.exists(path):
        return []
    import xml.etree.ElementTree as ET
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return []
    ns = {"b": "http://www.freedesktop.org/standards/desktop-bookmarks"}
    out = []
    for bm in tree.getroot().findall("bookmark"):
        href = bm.get("href", "")
        app = bm.find("b:application", ns)
        out.append({"modified": bm.get("modified", ""),
                    "name": os.path.basename(
                        __import__("urllib.parse", fromlist=["parse"])
                        .unquote(href.split("://", 1)[-1])) or href,
                    "detail": (app.get("name", "") if app is not None else ""),
                    "path": href})
    out.sort(key=lambda r: r["modified"], reverse=True)
    for i, r in enumerate(out):
        r["detail"] = (r["detail"] or "file") + (" · recent" if i < 3 else "")
    return out[:limit]


_FAV_PATH = os.path.expanduser("~/.local/share/foyer/favorites.json")
_FAV_MAX = 30


def parse_favorites(apps_index):
    """Kickoff favorites (kickoffrc) resolved against the app scan."""
    path = os.path.expanduser("~/.config/kickoffrc")
    if not os.path.exists(path):
        return []
    cp = configparser.ConfigParser()
    try:
        with open(path, errors="ignore") as fh:
            cp.read_file(fh)
    except Exception:
        return []
    if not cp.has_section("Favorites"):
        return []
    raw = cp.get("Favorites", "personal", fallback="")
    if not raw:
        raw = cp.get("Favorites", "favorites", fallback="")
    out = []
    for tok in raw.split(","):
        tok = tok.strip()
        if not tok or not tok.startswith("applications:"):
            continue
        did = tok.split(":", 1)[1]
        if did in apps_index:
            out.append(did)
        if len(out) >= 12:
            break
    return out


def _fav_ids(apps_index):
    """Foyer-owned favorites: load favorites.json, one-time Kickoff seed."""
    if os.path.exists(_FAV_PATH):
        try:
            with open(_FAV_PATH) as fh:
                ids = json.load(fh)
            if isinstance(ids, list):
                return [i for i in ids if isinstance(i, str)][:_FAV_MAX]
        except Exception:
            pass
        return []
    ids = [os.path.basename(r["path"]) if "path" in r else r
           for r in parse_favorites(apps_index)]
    _fav_write(ids)
    return ids


def _fav_write(ids):
    """Atomic write: a crash mid-write must never lose the pin list."""
    import tempfile
    os.makedirs(os.path.dirname(_FAV_PATH), exist_ok=True)
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(_FAV_PATH),
                                   prefix=".favorites-", suffix=".tmp")
        with os.fdopen(fd, "w") as fh:
            json.dump(ids, fh)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, _FAV_PATH)
    except OSError as exc:
        print(f"foyer[fav] WRITE FAILED: {exc}", file=sys.stderr, flush=True)


def _fav_rows(ids, apps_index):
    """desktop-id rows in stored order; drop ids the scan can't resolve."""
    return [apps_index[i] for i in ids if i in apps_index]


def _apps_index(scan_json):
    """desktop-id -> {name, path} map from the scan buckets."""
    if isinstance(scan_json, str):
        scan_json = json.loads(scan_json)
    idx = {}
    for cat in scan_json:
        for a in cat.get("apps", []):
            base = os.path.basename(a["path"])
            idx[base] = {"name": a["name"], "path": a["path"],
                         "generic": a.get("generic", "")}
    return idx


def _probe_host(ip, res, i):
    import socket, time as _t
    t0 = _t.time()
    try:
        s = socket.create_connection((ip, 22), timeout=0.6)
        s.close()
        res[i] = (True, int((_t.time() - t0) * 1000))
    except Exception:
        res[i] = (False, -1)


def probe_fleet(hosts):
    """Parallel TCP:22 liveness probe — honest UP/DOWN with real ms."""
    import threading
    res = [None] * len(hosts)
    ts = []
    for i, h in enumerate(hosts):
        t = threading.Thread(target=_probe_host,
                             args=(h.get("ip") or h["alias"], res, i),
                             daemon=True)
        t.start()
        ts.append(t)
    for t in ts:
        t.join(timeout=1.5)
    out = []
    import datetime
    stamp = datetime.datetime.now().strftime("%H:%M")
    for i, h in enumerate(hosts):
        up, ms = res[i] if res[i] else (False, -1)
        out.append({"alias": h["alias"], "ip": h.get("ip", ""),
                    "up": up, "ms": ms})
    return out, stamp


def post_real_key(win, k):
    mods = Qt.KeyboardModifier.NoModifier
    if k.startswith("ctrl+"):
        mods = Qt.KeyboardModifier.ControlModifier
        k = k.split("+", 1)[1]
    kk = _REALKEYS.get(k)
    text = None
    if kk is None:
        if len(k) == 1:            # printable char: the real typing path
            text = k
            if mods != Qt.KeyboardModifier.NoModifier:
                kk = getattr(Qt.Key, "Key_" + k.upper(), None)
                text = None        # combos match on key+modifier, not text
        else:
            return
    if kk is None and text is None:
        return
    try:    # QA trace: who receives real keys (focus theft detector)
        fo = win.focusObject()
        cn = ""
        try:
            cn = fo.metaObject().className()
        except Exception:
            pass
        print(f"foyer[key] {k} -> {cn} '{fo.objectName()}'", file=sys.stderr,
              flush=True)
    except Exception:
        pass
    pre = post = ""
    try:
        pre = _STATE_READER() or ""      # type: ignore[misc]
    except Exception:
        pass
    for typ in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
        if text is None:
            QCoreApplication.sendEvent(
                win, QKeyEvent(typ, int(kk or 0), mods))
        else:
            QCoreApplication.sendEvent(
                win, QKeyEvent(typ, int(Qt.Key.Key_unknown),
                               Qt.KeyboardModifier.NoModifier, text))
    try:
        post = _STATE_READER() or ""     # type: ignore[misc]
    except Exception:
        pass
    cur = ln = -1
    try:
        from PySide6.QtQuick import QQuickItem
        r = win.findChild(QQuickItem, "foyerRoot")
        if r is not None:
            pv = r.property("caret")
            cur = int(pv) if pv is not None else -1
            pv = r.property("queryLen")
            ln = int(pv) if pv is not None else -1
    except Exception:
        pass
    print(f"foyer[nav] {k}: {pre!r} -> {post!r} cur={cur} len={ln}",
          file=sys.stderr, flush=True)


_STATE_READER = lambda: ""   # set by main() once the window exists


def _system_action(name):
    """Whitelisted session commands — the row subtext names consequences."""
    cmds = {
        "lock": ("loginctl", ["lock-session"]),
        "sleep": ("systemctl", ["suspend"]),
        "logout": ("loginctl",
                   ["terminate-session", os.environ.get("XDG_SESSION_ID", "")]),
        "reboot": ("systemctl", ["reboot"]),
        "poweroff": ("systemctl", ["poweroff"]),
    }
    if name not in cmds:
        print(f"foyer[system] REJECT {name!r}", file=sys.stderr, flush=True)
        return
    if HARNESS:
        bridge._launch_log.append(f"system:{name}")   # assertable, not run
        return
    prog, args = cmds[name]
    if name == "logout" and not args[-1]:
        print("foyer[system] logout: no session id", file=sys.stderr,
              flush=True)
        return
    from PySide6.QtCore import QProcess
    QProcess.startDetached(prog, [a for a in args if a])
    print(f"foyer[system] {name}", file=sys.stderr, flush=True)


def _open_ssh(alias):
    """Open a terminal tab to a real alias from ~/.ssh/config."""
    import re as _re
    if not _re.fullmatch(r"[A-Za-z0-9._-]+", alias or ""):
        print(f"foyer[ssh] REJECT {alias!r}", file=sys.stderr, flush=True)
        return
    if HARNESS:
        bridge._launch_log.append(f"ssh:{alias}")
        return
    from PySide6.QtCore import QProcess
    for term in (("/usr/bin/konsole", ["-e", "ssh", alias]),):
        if os.path.exists(term[0]):
            QProcess.startDetached(term[0], term[1])
            return
    print("foyer[ssh] no terminal found", file=sys.stderr, flush=True)


def _run_update(which):
    """Read-only rpm-ostree output into the UPDATE view (never deploys)."""
    if HARNESS:
        bridge._updateOut = (
            "harness: rpm-ostree status (canned)\n"
            "State: idle\nDeployments:\n● ostree://.../bazzite (booted)")
        bridge.updateOutChanged.emit()
        return
    from PySide6.QtCore import QProcess

    def _proc():
        pr = QProcess()
        pr.readyReadStandardOutput.connect(
            lambda: bridge._set_update_out(
                bytes(pr.readAllStandardOutput()).decode("utf-8", "ignore")))
        pr.finished.connect(
            lambda rc, st: bridge._set_update_out(
                bridge._update_out_raw + f"\n[exit {rc}]"))
        args = (["status"] if which == "status"
                else ["upgrade", "--check"])
        from PySide6.QtCore import QTimer
        QTimer.singleShot(20000, lambda: pr.kill() if pr.state()
                          != QProcess.ProcessState.NotRunning else None)
        pr.start("/usr/bin/rpm-ostree", args)
        bridge._set_update_out(f"$ rpm-ostree {' '.join(args)}\n…")

    import threading
    threading.Timer(0, _proc).start()


# ------------------------------------------------------------- Loop-2 config
# ~/.config/foyer/config.json — settings levers + AI lane. Seeded harness
# HOME keeps tests off the real file; ask_exe swaps the LLM for a stub.
_FOYER_DIR = os.path.expanduser("~/.config/foyer")
_FOYER_CONFIG = os.path.join(_FOYER_DIR, "config.json")
_RECENT_PATH = os.path.expanduser(
    "~/.local/share/foyer/recent-questions.json")

_FOYER_DEFAULTS = {
    "card_scale": None,           # None = auto (1.45 on super-ultrawide)
    "card_opacity": 100,
    "card_anchor": "center",
    "fuzzy": False,
    "ai": {
        "base_url": "http://192.168.1.243:4000/v1",
        "model": "local-fast",
        "api_key_env": "ZHW_PROXY_API_KEY",
        "api_key_file": "~/.hermes/secrets/infra.env",
        "timeout_s": 45,
        "temperature": 0.1,
        "max_tokens": 400,
        "max_chars": 2000,
        "ask_exe": "",
    },
}


def _load_config():
    conf = json.loads(json.dumps(_FOYER_DEFAULTS))   # deep default copy
    try:
        with open(_FOYER_CONFIG, errors="ignore") as fh:
            user = json.load(fh)
        if isinstance(user, dict):
            for k, v in user.items():
                if k == "ai" and isinstance(v, dict):
                    conf["ai"].update(v)
                else:
                    conf[k] = v
    except (OSError, ValueError):
        pass
    return conf


def _save_config(conf):
    os.makedirs(_FOYER_DIR, exist_ok=True)
    tmp = _FOYER_CONFIG + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(conf, fh, indent=1)
    os.replace(tmp, _FOYER_CONFIG)


def _load_recent():
    try:
        with open(_RECENT_PATH, errors="ignore") as fh:
            v = json.load(fh)
        return v if isinstance(v, list) else []
    except (OSError, ValueError):
        return []


def _ask_key(conf):
    """API key from the env-style secrets file (never logged)."""
    import re
    env_name = conf.get("api_key_env", "ZHW_PROXY_API_KEY")
    try:
        with open(os.path.expanduser(conf.get("api_key_file", "")),
                  errors="ignore") as fh:
            for line in fh:
                m = re.match(rf"\s*(?:export\s+)?{env_name}=(\S+)", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return ""


# ------------------------------------------------ Loop-2: AI + settings rows
def _apply_setting(name):
    """Cycle a settings lever, persist, and publish live properties."""
    conf = bridge._config
    if name == "reset":
        keep_ai = conf.get("ai", {})
        conf.clear()
        conf.update(json.loads(json.dumps(_FOYER_DEFAULTS)))
        conf["ai"] = keep_ai
    elif name == "scale":
        steps = [None, 1.45, 1.38, 1.33, 1.60]
        cur = conf.get("card_scale")
        conf["card_scale"] = steps[(steps.index(cur) + 1) % len(steps)
                                   if cur in steps else 1]
    elif name == "opacity":
        steps = [100, 96, 90, 85]
        conf["card_opacity"] = steps[(steps.index(conf.get("card_opacity"))
                                      + 1) % len(steps)]
    elif name == "anchor":
        steps = ["center", "top", "bottom"]
        conf["card_anchor"] = steps[(steps.index(conf.get("card_anchor"))
                                     + 1) % len(steps)]
    elif name == "fuzzy":
        conf["fuzzy"] = not conf.get("fuzzy", False)
    else:
        return
    _save_config(conf)
    cs = conf.get("card_scale")
    bridge._cardScale = float(cs) if cs else 1.0     # None -> auto in main()
    bridge._cardOpacity = float(conf.get("card_opacity", 100))
    bridge._cardAnchor = str(conf.get("card_anchor", "center"))
    bridge._fuzzy = bool(conf.get("fuzzy", False))
    for sig in ("cardScaleChanged", "cardOpacityChanged",
                "cardAnchorChanged", "fuzzyChanged"):
        getattr(bridge, sig).emit()


def _toggle_favorite(path):
    """Pin/unpin an app. Takes a desktop-file path or bare id; persists."""
    did = os.path.basename(path) if "/" in path else path
    if did in bridge._favIds:
        bridge._favIds.remove(did)
    else:
        bridge._favIds.append(did)
        if len(bridge._favIds) > _FAV_MAX:
            bridge._favIds = bridge._favIds[-_FAV_MAX:]
    _fav_write(bridge._favIds)
    bridge._favsJson = json.dumps(
        _fav_rows(bridge._favIds, bridge._appsIndex))
    bridge.favsJsonChanged.emit()
    print(f"foyer[fav] {did} -> "
          f"{'pinned' if did in bridge._favIds else 'unpinned'} "
          f"(n={len(bridge._favIds)})", file=sys.stderr, flush=True)


def _move_favorite(idx, delta):
    """Reorder favorites: move item at idx by delta (+1 down, -1 up)."""
    ids = bridge._favIds
    j = idx + delta
    if 0 <= idx < len(ids) and 0 <= j < len(ids):
        ids[idx], ids[j] = ids[j], ids[idx]
        _fav_write(ids)
        bridge._favsJson = json.dumps(
            _fav_rows(ids, bridge._appsIndex))
        bridge.favsJsonChanged.emit()
        print(f"foyer[fav] move {idx}->{j} (n={len(ids)})", file=sys.stderr,
              flush=True)


def _ask_cancel():
    """Esc/hide mid-stream: stop consuming, keep what arrived."""
    bridge._aiCancel = True


def _do_copy(text):
    if HARNESS:
        bridge._launch_log.append(f"clip:{text[:40]}")
        return
    ok = False
    try:
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        cb.setText(text)
        ok = cb.text() == text          # silent-failure check (Wayland)
    except Exception:
        pass
    if not ok:
        # klipper D-Bus fallback — the path krunner-hermes uses in prod
        import subprocess
        try:
            subprocess.run(
                ["busctl", "--user", "call", "org.kde.klipper", "/klipper",
                 "org.kde.klipper.klipper", "setClipboardContents",
                 "s", text], timeout=3, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as exc:
            print(f"foyer: clipboard set failed ({exc})", file=sys.stderr)


def _do_continue(question):
    if HARNESS:
        bridge._launch_log.append(f"continue:{question[:40]}")
        return
    _do_copy(question)   # the question rides along in the clipboard
    from PySide6.QtCore import QProcess
    QProcess.startDetached("gio", ["launch",
                                   os.path.expanduser(
                                       "~/.local/share/applications/"
                                       "com.nousresearch.hermes.desktop")])


def _recent_add(q):
    bridge._recent = [q] + [x for x in bridge._recent if x != q][:7]
    os.makedirs(os.path.dirname(_RECENT_PATH), exist_ok=True)
    with open(_RECENT_PATH, "w") as fh:
        json.dump(bridge._recent, fh)
    bridge._recentJson = json.dumps(bridge._recent)
    bridge.recentJsonChanged.emit()


def _ask(question):
    """Stream an answer into the AI lane (stub process or LiteLLM SSE)."""
    q = question.strip()
    if not q:
        return
    conf = bridge._config.get("ai", {})
    bridge._aiQuestion = q
    bridge._aiStream = ""
    bridge._aiDone = False
    bridge._aiCancel = False
    for sig in ("aiQuestionChanged", "aiStreamChanged", "aiDoneChanged"):
        getattr(bridge, sig).emit()

    def append(text):
        bridge._aiStream = (bridge._aiStream + text)[
            :int(conf.get("max_chars", 2000))]
        bridge.aiStreamChanged.emit()

    def work():
        import time as _time
        started = _time.time()
        try:
            if conf.get("ask_exe"):
                import subprocess
                p = subprocess.Popen([conf["ask_exe"]], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True)
                for line in p.stdout:
                    if bridge._aiCancel:
                        break
                    append(line)
                p.wait(timeout=5)
            else:
                import urllib.request
                url = conf["base_url"].rstrip("/") + "/chat/completions"
                payload = json.dumps({
                    "model": conf.get("model", "local-fast"),
                    "messages": [{"role": "user", "content": q}],
                    "max_tokens": int(conf.get("max_tokens", 400)),
                    "temperature": float(conf.get("temperature", 0.1)),
                    "stream": True,
                }).encode()
                req = urllib.request.Request(url, data=payload, headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {_ask_key(conf)}",
                })
                # per-read timeout doubles as first-token timeout: a
                # stalled proxy raises after 12 s with no bytes
                with urllib.request.urlopen(
                        req, timeout=min(12, int(conf.get("timeout_s", 45)))) as r:
                    truncated = False
                    for raw in r:
                        if bridge._aiCancel:
                            break
                        if _time.time() - started > int(conf.get(
                                "timeout_s", 45)):
                            append("\n...(timed out)")
                            break
                        line = raw.decode("utf-8", "ignore").strip()
                        if not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        if data == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data)["choices"][0]
                            delta = chunk.get("delta", {}).get("content", "")
                            if chunk.get("finish_reason") == "length":
                                truncated = True
                        except (ValueError, KeyError, IndexError):
                            continue
                        if delta:
                            append(delta)
                    if truncated:
                        append("\n...(truncated at max tokens - raise "
                               "ai.max_tokens in config)")
        except Exception as exc:
            if not bridge._aiCancel:
                append(f"\n\u26a0 ask failed: {exc}")
        finally:
            bridge._aiDone = True
            bridge.aiDoneChanged.emit()
            if bridge._aiStream:
                _recent_add(q)   # completed or cancelled-with-text asks

    import threading
    threading.Thread(target=work, daemon=True).start()


class Bridge(QObject):
    """QML↔daemon channel (signals out, dbus slots in)."""

    gotoState = Signal(str)
    keyDriven = Signal(str)
    keyRealDriven = Signal(str)
    launchRequested = Signal(str)
    systemActionRequested = Signal(str)
    openSshRequested = Signal(str)
    updateRunRequested = Signal(str)
    fleetProbeRequested = Signal()
    fleetJsonChanged = Signal()
    favsJsonChanged = Signal()
    updateOutChanged = Signal()
    # Loop-2: AI lane + settings levers
    askRequested = Signal(str)
    askCancelRequested = Signal()
    favoriteToggleRequested = Signal(str)
    favoriteMoveRequested = Signal(int, int)
    copyRequested = Signal(str)
    continueRequested = Signal(str)
    settingChanged = Signal(str)
    cardScaleChanged = Signal()
    cardOpacityChanged = Signal()
    cardAnchorChanged = Signal()
    fuzzyChanged = Signal()
    aiQuestionChanged = Signal()
    aiStreamChanged = Signal()
    aiDoneChanged = Signal()
    aiModelChanged = Signal()
    recentJsonChanged = Signal()

    def __init__(self):
        super().__init__()
        self._launch_log = []   # harness: recorded (not executed) launches
        # multi-monitor: horizontal shift so the card centers on the PRIMARY
        # screen rather than the combined virtual desktop (see main()).
        self._cardOffsetX = 0
        # super-ultrawide (aspect >= 2.6): upscale the 920x640 card so it
        # doesn't read tiny on a 5120-wide panel; 1.0 elsewhere.
        self._cardScale = 1.0
        self._appsJson = scan_apps()
        self._appsIndex = _apps_index(self._appsJson)
        self._sshJson = json.dumps(parse_ssh_config())
        self._recentsJson = json.dumps(scan_recents())
        self._favIds = _fav_ids(self._appsIndex)
        self._favsJson = json.dumps(_fav_rows(self._favIds, self._appsIndex))
        self._fleetJson = ""
        self._updateOut = ""
        self._fleetHosts = parse_ssh_config()   # one inventory, two lanes
        # Loop-2: persisted settings + live AI lane state
        self._config = _load_config()
        cs = self._config.get("card_scale")
        self._cardScale = float(cs) if cs else 1.0
        self._cardOpacity = float(self._config.get("card_opacity", 100))
        self._cardAnchor = str(self._config.get("card_anchor", "center"))
        self._fuzzy = bool(self._config.get("fuzzy", False))
        self._aiQuestion = ""
        self._aiStream = ""
        self._aiDone = True
        self._aiCancel = False
        self._aiModel = self._config.get("ai", {}).get("model", "")
        self._recent = _load_recent()
        self._recentJson = json.dumps(self._recent)

    def _read_cardOffsetX(self):
        return self._cardOffsetX

    cardOffsetX = Property(int, _read_cardOffsetX, constant=True)

    def _read_cardScale(self):
        return self._cardScale

    cardScale = Property(float, _read_cardScale, notify=cardScaleChanged)

    def _read_cardOpacity(self):
        return self._cardOpacity

    cardOpacity = Property(float, _read_cardOpacity,
                           notify=cardOpacityChanged)

    def _read_cardAnchor(self):
        return self._cardAnchor

    cardAnchor = Property(str, _read_cardAnchor, notify=cardAnchorChanged)

    def _read_fuzzy(self):
        return self._fuzzy

    fuzzy = Property(bool, _read_fuzzy, notify=fuzzyChanged)

    def _read_aiQuestion(self):
        return self._aiQuestion

    aiQuestion = Property(str, _read_aiQuestion, notify=aiQuestionChanged)

    def _read_aiStream(self):
        return self._aiStream

    aiStream = Property(str, _read_aiStream, notify=aiStreamChanged)

    def _read_aiDone(self):
        return self._aiDone

    aiDone = Property(bool, _read_aiDone, notify=aiDoneChanged)

    def _read_aiModel(self):
        return self._aiModel

    aiModel = Property(str, _read_aiModel, notify=aiModelChanged)

    def _read_recentJson(self):
        return self._recentJson

    recentJson = Property(str, _read_recentJson, notify=recentJsonChanged)

    def _read_appsJson(self):
        return self._appsJson

    appsJson = Property(str, _read_appsJson, constant=True)

    def _read_sshJson(self):
        return self._sshJson

    sshJson = Property(str, _read_sshJson, constant=True)

    def _read_recentsJson(self):
        return self._recentsJson

    recentsJson = Property(str, _read_recentsJson, constant=True)

    def _read_favsJson(self):
        return self._favsJson

    favsJson = Property(str, _read_favsJson, notify=favsJsonChanged)

    def _read_fleetJson(self):
        return self._fleetJson

    fleetJson = Property(str, _read_fleetJson, notify=fleetJsonChanged)

    def _read_updateOut(self):
        return self._updateOut

    updateOut = Property(str, _read_updateOut, notify=updateOutChanged)

    @Slot()
    def toggle(self):
        self.toggleRequested.emit()

    @Slot()
    def showUI(self):
        self.showRequested.emit()

    @Slot()
    def hideUI(self):
        self.hideRequested.emit()

    @Slot(result=str)
    def getFavsJson(self):
        return self._favsJson

    @Slot(str)
    def qmlTrace(self, s):
        print(f"foyer[qml] {s}", file=sys.stderr, flush=True)

    @Slot(result=str)
    def getShowMs(self):
        return json.dumps({"ms": _SHOW_MS})

    @Slot(str)
    def driveState(self, state):
        print(f"foyer[drv] {state}", file=sys.stderr, flush=True)
        self.gotoState.emit(state)

    @Slot(str)
    def driveKey(self, key):
        """Verification channel: routes a logical key (down/up/left/right/
        enter) into the QML nav layer — same code path a real keypress
        takes after the field's Keys handlers forward it."""
        self.keyDriven.emit(key)

    @Slot(str)
    def driveKeyReal(self, key):
        """Verification channel: posts a REAL Qt KeyPress/KeyRelease pair
        on the window (delivered to the focus object). This is the exact
        delivery path a physical keypress takes — field Keys-handlers,
        TextInput cursor logic and all. QA must use this one."""
        self.keyRealDriven.emit(key)

    @Slot(result=str)
    def launchLog(self):
        """Harness assertion channel: execs recorded but not spawned."""
        return json.dumps(self._launch_log)

    @Slot(result=str)
    def harnessMode(self):
        """QA gate: '1' when running under the nested harness (launches
        are recorded, not spawned). check-nav must never press ⏎ on app
        rows against a live daemon — it would launch real apps."""
        return "1" if HARNESS else "0"

    def _set_update_out(self, text):
        import re
        text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)   # no ANSI
        self._update_out_raw = getattr(self, "_update_out_raw", "")
        self._updateOut = text[-8192:]                          # cap 8 KiB
        self.updateOutChanged.emit()

    @Slot()
    def probeFleet(self):
        """Re-probe fleet liveness (also callable over dbus for tests)."""
        self._do_probe()

    @Slot(result=str)
    def getUpdateOut(self):
        """Test surface: current UPDATE view output text."""
        return self._updateOut

    @Slot(result=str)
    def getFleetJson(self):
        """Test surface: last fleet probe result as JSON."""
        return self._fleetJson

    @Slot(result=str)
    def getAiState(self):
        """Test surface: {q, len, done} for the AI lane drills."""
        return json.dumps({"q": self._aiQuestion,
                           "len": len(self._aiStream),
                           "done": self._aiDone})

    @Slot(result=str)
    def getConfig(self):
        """Test surface: current persisted settings + AI config."""
        return json.dumps(self._config)

    def _do_probe(self):
        import threading

        def work():
            try:
                rows, stamp = probe_fleet(self._fleetHosts)
                self._fleetJson = json.dumps({"stamp": stamp, "hosts": rows})
                self.fleetJsonChanged.emit()
            except Exception as exc:  # keep the thread from dying silently
                print(f"foyer[probe] THREAD ERROR {exc!r}",
                      file=sys.stderr, flush=True)

        threading.Thread(target=work, daemon=True).start()

    # set by main() once the window exists: () -> "state zone i n cols rail"
    stateReader = None  # type: ignore[assignment]

    @Slot(result=str)
    def navState(self):
        """QA introspection: full keyboard-nav state as one string."""
        return self.stateReader() if self.stateReader else ""  # type: ignore[misc]

    # internal wiring signals (connected to the window by main())
    toggleRequested = Signal()
    showRequested = Signal()
    hideRequested = Signal()


def main():
    global bridge
    app = QGuiApplication(sys.argv)
    app.setApplicationName("foyer")
    app.setDesktopFileName("gdeyoung-foyer")
    app.setApplicationVersion("0.2.0")

    bridge = Bridge()
    bridge.systemActionRequested.connect(_system_action)
    bridge.openSshRequested.connect(_open_ssh)
    bridge.updateRunRequested.connect(_run_update)
    bridge.fleetProbeRequested.connect(bridge._do_probe)
    bridge.askRequested.connect(_ask)
    bridge.askCancelRequested.connect(_ask_cancel)
    bridge.favoriteToggleRequested.connect(_toggle_favorite)
    bridge.favoriteMoveRequested.connect(_move_favorite)
    bridge.copyRequested.connect(_do_copy)
    bridge.continueRequested.connect(_do_continue)
    bridge.settingChanged.connect(_apply_setting)

    # Multi-monitor fix: kwin assigns the layer surface the FULL combined
    # output; an un-offset card would center on the monitor seam. Shift the
    # card to the PRIMARY screen's center. Computed before QML loads so the
    # constant property binds with the right value (single-monitor → 0).
    try:
        prim = app.primaryScreen()
        if prim is not None:
            vg = prim.virtualGeometry()
            bridge._cardOffsetX = prim.geometry().center().x() - vg.center().x()
            # With QT_ENABLE_HIGHDPI_SCALING=0 these are PHYSICAL pixels.
            w, h = vg.width(), vg.height()
            if bridge._config.get("card_scale") is None and w / h >= 2.6:
                bridge._cardScale = 1.45
                bridge.cardScaleChanged.emit()
    except Exception as exc:  # cosmetic; never block startup
        print(f"foyer: screen geometry fallback ({exc})", file=sys.stderr)

    engine = QQmlApplicationEngine()
    engine.addImportPath("/usr/lib64/qt6/qml")  # system KDE QML modules
    engine.rootContext().setContextProperty("bridge", bridge)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "FoyerWindow.qml")))
    if not engine.rootObjects():
        print("foyer: FoyerWindow.qml failed to load", file=sys.stderr)
        return 1
    win = engine.rootObjects()[0]

    def _read_nav():
        from PySide6.QtQuick import QQuickItem
        r = win.findChild(QQuickItem, "foyerRoot")
        if r is None:
            return "no-root"
        vals = [str(r.property(p)) for p in
                ("state", "zone", "lensIndex", "lensCount", "lensCols", "railIndex",
                 "activeCatId")]
        return " ".join(v if v not in ("None", "") else "?" for v in vals)

    bridge.stateReader = _read_nav
    global _STATE_READER
    _STATE_READER = _read_nav

    bridge.toggleRequested.connect(
        lambda: win.hide() if win.isVisible() else _show(win))
    bridge.showRequested.connect(lambda: _show(win))
    bridge.hideRequested.connect(win.hide)
    win.frameSwapped.connect(lambda: _frame_shown(win))

    def _wd_ping():
        """Keep systemd WatchdogSec fed so a hung event loop restarts us."""
        path = os.environ.get("NOTIFY_SOCKET")
        if not path:
            return
        if path.startswith("@"):
            path = "\0" + path[1:]
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            s.connect(path)
            s.send(b"WATCHDOG=1")
            s.close()
        except OSError:
            pass

    from PySide6.QtCore import QTimer as _QTimer
    _wd = _QTimer()
    _wd.timeout.connect(_wd_ping)
    _wd.start(3000)   # unit WatchdogSec=10; ping every 3 s
    bridge.keyRealDriven.connect(lambda k: post_real_key(win, k))

    def _launch(path):
        # Launch by desktop FILE via gio — spec-compliant Exec handling
        # (field codes, quoting, Terminal, DBusActivatable), no shell, no
        # injection surface. Council item: never hand-parse Exec.
        if HARNESS:
            bridge._launch_log.append(path)   # assertable, never spawned
            return
        from PySide6.QtCore import QProcess
        if path.startswith("http://") or path.startswith("https://"):
            # typed-view WEB row: hand URLs to the system handler, not gio
            if QProcess.startDetached("/usr/bin/xdg-open", [path]):
                return
        if os.path.exists("/usr/bin/gio"):
            ok = QProcess.startDetached("/usr/bin/gio", ["launch", path])
        else:   # last-ditch fallback (logged loudly)
            print(f"foyer: gio missing; cannot launch {path}",
                  file=sys.stderr, flush=True)
            ok = False
        if ok:
            win.hide()
        else:
            print(f"foyer: launch failed: {path}", file=sys.stderr,
                  flush=True)

    bridge.launchRequested.connect(_launch)

    conn = QDBusConnection.sessionBus()
    if not conn.registerService(BUS_NAME):
        print("foyer: another instance owns " + BUS_NAME, file=sys.stderr)
        return 2
    # Fedora PySide6 has no QClassInfo; the interface-name overload pins it.
    ok = conn.registerObject(BUS_PATH, BUS_NAME, bridge,
                             QDBusConnection.ExportAllSlots)
    if not ok:
        print("foyer: registerObject failed", file=sys.stderr)
        return 3

    if "--show" in sys.argv:
        _show(win)

    # harness diagnostics: late window state (post-map)
    from PySide6.QtCore import QTimer
    QTimer.singleShot(3000, lambda: _dump(win, "t+3s"))

    return app.exec()


_SHOW_T0 = 0.0
_SHOW_MS = None


def _show(win):
    global _SHOW_T0, _SHOW_MS
    if not win.isVisible():
        _SHOW_T0 = time.monotonic()
        _SHOW_MS = None
    win.show()
    win.raise_()
    win.requestActivate()
    _dump(win, "show")


def _frame_shown(win):
    """First afterAnimating post-show — warm-show latency sample."""
    global _SHOW_MS
    if _SHOW_T0 and _SHOW_MS is None:
        _SHOW_MS = round((time.monotonic() - _SHOW_T0) * 1000, 1)
        print(f"foyer[showlat] t={_SHOW_MS}ms", file=sys.stderr, flush=True)


def _dump(win, tag):
    print("foyer[%s] vis=%s w=%s h=%s x=%s y=%s" % (
        tag, win.isVisible(), win.width(), win.height(), win.x(), win.y()),
        file=sys.stderr, flush=True)
    # card geometry in WINDOW coordinates (diagnostics; exact, no pixels)
    try:
        from PySide6.QtQuick import QQuickItem
        box = win.findChild(QQuickItem, "cardBox")
        r = win.findChild(QQuickItem, "foyerRoot")
        if box is not None and r is not None:
            bp = box.mapToScene(QPointF(0, 0))
            print("foyer[%s] cardBox %.0fx%.0f at (%.0f,%.0f) | foyerRoot "
                  "%.0fx%.0f u=%.2f t=%.2f" % (
                      tag, box.width(), box.height(), bp.x(), bp.y(),
                      r.width(), r.height(),
                      float(r.property("u") or 0), float(r.property("t") or 0)),
                  file=sys.stderr, flush=True)
    except Exception as exc:
        print(f"foyer[{tag}] cardBox probe failed: {exc}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
