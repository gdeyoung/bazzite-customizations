"""Pure launcher-lane logic — UX-SPEC §L (r2, verdict deleg_23359d89).

Stdlib only, no dbus/GLib. Filesystem access confined to AppStore (dirs,
which, logger injectable for tests). hermes_runner.py wires rows into
route() and Run dispatch; nothing here spawns a process.
"""

import configparser
import json
import os
import re
import shutil
import threading
import time
from pathlib import Path

CACHE_VERSION = 2
CACHE_NAME = "apps.json"

# L-3: precedence-ordered main-category map (first match wins).
CATEGORY_PRECEDENCE = [
    ("Settings", "settings"), ("System", "system"),
    ("TerminalEmulator", "system"), ("Game", "games"),
    ("Network", "internet"), ("AudioVideo", "media"), ("Audio", "media"),
    ("Video", "media"), ("Graphics", "graphics"), ("Office", "office"),
    ("Development", "development"), ("Utility", "utilities"),
    ("TextEditor", "utilities"), ("Education", "learning"),
    ("Science", "learning"),
]

# L-3: slugs in fixed display order.
CATEGORY_LABELS = [
    ("internet", "Internet"), ("media", "Media"), ("games", "Games"),
    ("system", "System"), ("settings", "Settings"),
    ("development", "Development"), ("graphics", "Graphics"),
    ("office", "Office"), ("utilities", "Utilities"),
    ("learning", "Learning"), ("more", "More"),
]
SLUGS = [s for s, _ in CATEGORY_LABELS]
_LABEL_LOOKUP = {label.lower(): s for s, label in CATEGORY_LABELS}

_PLACEHOLDER_RE = re.compile(r"%[a-zA-Z]")


def default_dirs():
    """L-2 scan dirs in id-precedence order, deduped, XDG extras appended."""
    home = os.path.expanduser("~")
    dirs = [
        f"{home}/.local/share/applications",
        "/usr/local/share/applications",
        "/usr/share/applications",
        f"{home}/.local/share/flatpak/exports/share/applications",
        "/var/lib/flatpak/exports/share/applications",
    ]
    for d in (os.environ.get("XDG_DATA_DIRS") or "").split(":"):
        d = d.strip()
        if d:
            dirs.append(os.path.join(d, "applications"))
    out, seen = [], set()
    for d in dirs:
        r = os.path.realpath(os.path.expanduser(d))
        if r not in seen:
            seen.add(r)
            out.append(r)
    return out


def parse_desktop(text):
    """L-2: one .desktop file → app dict, or None when skippable.

    Skip rules: bad INI / no [Desktop Entry], Type != Application,
    NoDisplay, Hidden, NotShowIn=KDE, OnlyShowIn set without KDE,
    empty Name. ids keep the .desktop suffix (caller sets it).
    """
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cp.read_string(text)
    except configparser.Error:
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    e = cp["Desktop Entry"]

    if (e.get("Type", "").strip() != "Application"
            or e.getboolean("NoDisplay", False)
            or e.getboolean("Hidden", False)):
        return None
    notshow = [v.strip() for v in e.get("NotShowIn", "").split(";") if v.strip()]
    if "KDE" in notshow:
        return None
    onlyshow = [v.strip() for v in e.get("OnlyShowIn", "").split(";") if v.strip()]
    if onlyshow and "KDE" not in onlyshow:
        return None
    name = e.get("Name", "").strip()
    if not name:
        return None
    kw = e.get("Keywords", "")
    return {
        "name": name,
        "generic": e.get("GenericName", "").strip(),
        "comment": e.get("Comment", "").strip(),
        "icon": e.get("Icon", "").strip(),
        "exec": e.get("Exec", "").strip(),
        "keywords": [k.strip() for k in kw.split(";") if k.strip()],
        "categories": [c.strip() for c in e.get("Categories", "").split(";")
                       if c.strip()],
        "try_exec": e.get("TryExec", "").strip(),
    }


def exec_display(exec_str):
    """Executable basename for subtext: first token, %placeholders cut."""
    tok = (exec_str or "").split()
    if not tok:
        return ""
    tok = _PLACEHOLDER_RE.sub("", tok[0])
    return os.path.basename(tok) if "/" in tok else tok


def slug_for(categories):
    """L-3 precedence mapping; no match → 'more'."""
    have = {c for c in (categories or [])}
    for main, slug in CATEGORY_PRECEDENCE:
        if main in have:
            return slug
    return "more"


def sanitize_pins(raw, logger=None):
    """L-8 load-time: array of strings, deduped preserving first."""
    out, seen, skipped = [], set(), 0
    for v in raw if isinstance(raw, list) else []:
        if not isinstance(v, str):
            skipped += 1
            continue
        v = v.strip()
        if not v or v in seen:
            skipped += 1
            continue
        seen.add(v)
        out.append(v)
    return out, skipped


def sanitize_cat_overrides(raw, logger=None):
    """L-8 load-time: {desktop-id: slug}; unknown slug → skipped + WARN."""
    out, skipped = {}, 0
    for k, v in (raw.items() if isinstance(raw, dict) else []):
        if not isinstance(k, str) or not isinstance(v, str) or v not in SLUGS:
            skipped += 1
            if logger:
                logger(f"app_categories entry skipped: {k!r}={v!r}")
            continue
        out[k] = v
    return out, skipped


def parse_query(rest):
    """L-4 token grammar (r2). Returns a tagged dict:
    {"mode": "root"|"pins"|"cat"|"catlist"|"fuzzy",
     "slug": str, "filter": str, "slugs": [str], "tokens": [str]}
    """
    tokens = (rest or "").split()
    out = {"mode": "fuzzy", "slug": "", "filter": "",
           "slugs": [], "tokens": tokens}
    if not tokens:
        out["mode"] = "root"
        return out
    low = tokens[0].lower()
    if low == "pins":
        out["mode"] = "pins"
        return out
    if low in _LABEL_LOOKUP or low in SLUGS:
        out["mode"] = "cat"
        out["slug"] = _LABEL_LOOKUP.get(low, low)
        out["filter"] = " ".join(tokens[1:])
        return out
    if len(tokens) == 1:
        hits = [s for s, label in CATEGORY_LABELS
                if s.startswith(low) or label.lower().startswith(low)]
        if hits:
            out["mode"] = "catlist"
            out["slugs"] = hits
            return out
    return out


def _corpus(app):
    return " ".join([app["name"], app["generic"], app["comment"],
                     " ".join(app["keywords"]), app.get("exec_display", "")])


def _match_quality(app, tokens):
    """(quality, base_rel) — exact 3/1.0, prefix 2/0.9, substring 1/0.55,
    no-match None. Multi-token = AND across the corpus (L-4)."""
    name = app["name"].lower()
    corpus = _corpus(app).lower()
    best = 99
    for t in tokens:
        tl = t.lower()
        if tl == name:
            q = 3
        elif name.startswith(tl):
            q = 2
        elif tl in corpus:
            q = 1
        else:
            return None
        best = min(best, q)
    base = {3: 1.0, 2: 0.9, 1: 0.55}[best]
    return best, base


def app_row(app, slug, pinned, rel, tier):
    return {
        "id": f"app:{app['id']}",
        "title": app["name"],
        "sub": app["generic"] or app.get("exec_display", ""),
        "icon": app["icon"] or "application-x-executable",
        "tier": tier, "rel": round(rel, 3),
        "actions": ["launch", "unpin" if pinned else "pin"],
        "slug": slug,
    }


def build_rows(apps, pins, freq, overrides, rest, dead_pin_logger=None):
    """L-4/L-5 row list. apps: parsed + cached entries with id/path set.
    pins: ordered ids; freq: {id: n}; overrides: {id: slug}.
    Returns dicts: id/title/sub/icon/tier/rel/actions/slug.
    Tiers: HIGHEST / HIGH / MODERATE (mapped to ints in hermes_runner).
    """
    by_id = {a["id"]: a for a in apps}

    def slug_of(app):
        return overrides.get(app["id"]) or slug_for(app["categories"])

    for pid in pins:
        if pid not in by_id and dead_pin_logger:
            dead_pin_logger(pid)

    parsed = parse_query(rest)
    mode = parsed["mode"]
    if mode in ("root", "pins"):
        rows = []
        if mode == "root":
            # r2.2 anchor: bare 'apps' outranks native rows NAMED "apps"
            # only with a 1.0/HIGHEST row leading the group (pixel apps3)
            rows.append({"id": "apps-root",
                         "title": "Apps — favorites & categories",
                         "sub": "HERMES LAUNCHER · ↓ ARROWS TO BROWSE · "
                                "ENTER DRILLS",
                         "icon": "start-here-kde", "tier": "HIGHEST",
                         "rel": 1.0, "actions": [], "slug": ""})
        for pid in pins:
            app = by_id.get(pid)
            if app:
                rows.append(app_row(app, slug_of(app), True, 0.95, "HIGH"))
                rows[-1]["sub"] = f"pinned · {slug_of(app)}"   # §L-4
        if mode == "pins" and not rows:
            return [{"id": "apphelp", "title": "No pins yet",
                     "sub": "select an app → PIN action",
                     "icon": "help-browser", "tier": "MODERATE",
                     "rel": 0.5, "actions": [], "slug": ""}]
        if mode == "pins":
            return rows
        # root: pins done; frequency (count ≥1, excluding pins, top 6)
        counts = [(a["id"], freq.get(a["id"], 0)) for a in apps]
        ranked = sorted((t for t in counts if t[1] >= 1
                         and t[0] not in pins and t[0] in by_id),
                        key=lambda t: (-t[1], by_id[t[0]]["name"].lower(),
                                       t[0]))[:6]
        for i, (aid, n) in enumerate(ranked):
            app = by_id[aid]
            rows.append(app_row(app, slug_of(app), False,
                                max(0.80, 0.90 - 0.02 * i), "HIGH"))
            rows[-1]["sub"] = f"{n}× · {slug_of(app)}"
        # category rows in display order (High band: pixel gate apps1 —
        # Moderate sank our rows below native matches for the word "apps")
        for slug, label in CATEGORY_LABELS:
            n = sum(1 for a in apps if slug_of(a) == slug)
            if n:
                rows.append({"id": f"appcat:{slug}", "title": label,
                             "sub": f"{n} apps", "icon": "folder",
                             "tier": "HIGH", "rel": 0.85,
                             "actions": [], "slug": slug})
        return rows

    if mode == "catlist":
        rows = []
        for slug in parsed["slugs"]:
            label = dict(CATEGORY_LABELS).get(slug, slug)
            n = sum(1 for a in apps if slug_of(a) == slug)
            rows.append({"id": f"appcat:{slug}", "title": label,
                         "sub": f"{n} apps", "icon": "folder",
                         "tier": "HIGH", "rel": 0.85, "actions": [],
                         "slug": slug})
        return rows

    # cat view or fuzzy: filter apps, quality ladder + deterministic order
    if mode == "cat":
        slug, filt = parsed["slug"], parsed["filter"]
        pool = [a for a in apps if slug_of(a) == slug]
        tokens = filt.split()
    else:
        pool, tokens = apps, parsed["tokens"]
    matched = []
    for a in pool:
        if not tokens:
            matched.append((1, 0.55, a))          # unfiltered: name-asc walk
            continue
        q = _match_quality(a, tokens)
        if q:
            matched.append((q[0], q[1], a))
    matched.sort(key=lambda t: (-t[0], t[2]["name"].lower(), t[2]["id"]))
    rows, tier_for = [], {3: "HIGHEST", 2: "HIGHEST", 1: "MODERATE"}
    for i, (q, base, a) in enumerate(matched):
        rel = max(0.05, base - 0.01 * i)   # stepped: deterministic order
        rows.append(app_row(a, slug_of(a), a["id"] in pins, rel,
                            tier_for[q]))
    if not rows:
        rows.append({"id": "apphelp", "title": "No apps match",
                     "sub": "try a category, e.g. apps games",
                     "icon": "help-browser", "tier": "MODERATE",
                     "rel": 0.5, "actions": [], "slug": ""})
    return rows


class AppStore:
    """L-2 enumeration + cache. Thread-safe; mtime+set gated; never fatal."""

    def __init__(self, dirs=None, cache_path=None, which=None, logger=None):
        self.dirs = [os.path.realpath(os.path.expanduser(d))
                     for d in (dirs if dirs is not None else default_dirs())]
        base = os.environ.get("XDG_CACHE_HOME",
                              os.path.expanduser("~/.cache"))
        self.cache_path = Path(cache_path if cache_path is not None
                               else os.path.join(base, "hermes-runner",
                                                 CACHE_NAME))
        self.which = which or shutil.which
        self.logger = logger or (lambda *a: None)
        self.lock = threading.Lock()
        self._apps = None
        self._fingerprint = None

    def fingerprint(self):
        out = {}
        for d in self.dirs:
            try:
                out[d] = os.stat(d).st_mtime_ns
            except OSError:
                pass           # missing dir: absent from the map (set check)
        return out

    def _scan(self):
        merged = {}
        for d in self.dirs:
            try:
                names = sorted(os.listdir(d))
            except OSError:
                continue
            for fn in names:
                if not fn.endswith(".desktop"):
                    continue
                if fn in merged:
                    continue        # id precedence: first dir wins (L-2)
                try:
                    text = Path(d, fn).read_text(encoding="utf-8",
                                                 errors="replace")
                except OSError:
                    continue
                app = parse_desktop(text)
                if not app:
                    continue
                if app["try_exec"] and not self.which(app["try_exec"]):
                    continue
                app["id"] = fn
                app["path"] = os.path.join(d, fn)
                app["exec_display"] = exec_display(app["exec"])
                merged[fn] = app
        apps = sorted(merged.values(),
                      key=lambda a: (a["name"].lower(), a["id"]))
        return apps

    def _load_cache(self):
        try:
            data = json.loads(self.cache_path.read_text(encoding="utf-8"))
            if (isinstance(data, dict) and data.get("v") == CACHE_VERSION
                    and data.get("dirs") == self.fingerprint()
                    and isinstance(data.get("apps"), list)):
                return data["apps"]
        except (OSError, ValueError):
            pass
        return None

    def _write_cache(self, apps):
        try:
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = str(self.cache_path) + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"v": CACHE_VERSION, "dirs": self.fingerprint(),
                           "apps": apps}, f)
            os.replace(tmp, str(self.cache_path))
        except OSError as e:
            self.logger(f"apps cache write failed: {e}")

    def warm(self):
        """Startup warm (L-2): scan or cache-load once, eagerly."""
        t0 = time.time()
        self.snapshot()
        self.logger(f"apps index warmed: {len(self._apps or [])} apps "
                    f"in {time.time() - t0:.2f}s")

    def snapshot(self):
        """Current app list; rescan at most once per call when stale."""
        with self.lock:
            fp = self.fingerprint()
            if self._apps is not None and self._fingerprint == fp:
                return self._apps
            apps = self._load_cache()
            if apps is None:
                apps = self._scan()
                self._write_cache(apps)
            self._apps, self._fingerprint = apps, fp
            return apps

    def lookup(self, app_id):
        for a in self.snapshot():
            if a["id"] == app_id:
                return a
        return None
