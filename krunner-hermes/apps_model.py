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
import sqlite3
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path

CACHE_VERSION = 3
CACHE_NAME = "apps.json"
KCM_CACHE_NAME = "kcms.json"
KCM_TTL_S = 3600

SYSTEM_MENU = "/etc/xdg/menus/applications.menu"
USER_MENU = "~/.config/menus/applications.menu"
DIRECTORY_DIRS = ("/usr/share/desktop-directories",
                  "~/.local/share/desktop-directories")
KICKOFF_DB = ("~/.local/share/kactivitymanagerd/resources/database")
KICKOFF_AGENT = "org.kde.plasma.favorites.applications"
# r6 (§L-18): System Settings modules — the native systemsettings runner
# is invisible in single-runner mode, so the tree hosts its own fan-out.
KCM_DIRS = ("/usr/share/applications", "~/.local/share/applications")

# Fallback only (menu file missing/unparseable) — v0.6 behavior.
CATEGORY_PRECEDENCE = [
    ("Settings", "settings"), ("System", "system"),
    ("TerminalEmulator", "system"), ("Game", "games"),
    ("Network", "internet"), ("AudioVideo", "media"), ("Audio", "media"),
    ("Video", "media"), ("Graphics", "graphics"), ("Office", "office"),
    ("Development", "development"), ("Utility", "utilities"),
    ("TextEditor", "utilities"), ("Education", "learning"),
    ("Science", "learning"),
]
FALLBACK_LABELS = [
    ("internet", "Internet"), ("media", "Media"), ("games", "Games"),
    ("system", "System"), ("settings", "Settings"),
    ("development", "Development"), ("graphics", "Graphics"),
    ("office", "Office"), ("utilities", "Utilities"),
    ("learning", "Learning"), ("more", "More"),
]
# Bazzita/Fedora KDE ships no plain Utility.directory/.  files — the menu's
# <Directory> references go unresolved, so icon= falls back here. These are
# the same breeze applications-* names Kickoff uses for these groups.
ICON_FALLBACKS = {
    "accessories": "applications-accessories",
    "development": "applications-development",
    "education": "applications-education",
    "games": "applications-games",
    "graphics": "applications-graphics",
    "internet": "applications-internet",
    "multimedia": "applications-multimedia",
    "office": "applications-office",
    "system-tools": "applications-system",
    "system": "applications-system",
    "settings": "preferences-system",
    "media": "applications-multimedia",
    "utilities": "applications-utilities",
    "learning": "applications-education",
    "other": "applications-other",
    "more": "applications-other",
}


def icon_for_slug(slug, menu_icon=""):
    """Menu icon if resolved, else the breeze applications-* fallback."""
    return menu_icon or ICON_FALLBACKS.get(slug, "folder")

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


def _slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def _read_directory_file(name, dir_dirs):
    """Name/Icon from a .directory file, or ('', '') if unresolvable."""
    if not name:
        return "", ""
    for base in dir_dirs:
        p = os.path.join(os.path.expanduser(base), name)
        try:
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            cp.read_string(Path(p).read_text(encoding="utf-8",
                                             errors="replace"))
            sec = cp["Desktop Entry"] if cp.has_section("Desktop Entry") \
                else None
            if sec:
                return (sec.get("Name", "").strip(),
                        sec.get("Icon", "").strip())
        except (OSError, configparser.Error):
            continue
    return "", ""


def _collect_rules(include_el):
    """Include block → list of rules; a rule = (kind, categories).

    kind 'any' (bare Category / Or) or 'all' (And).
    """
    rules = []
    for el in include_el:
        if el.tag == "Category" and el.text:
            rules.append(("any", {el.text.strip()}))
        elif el.tag == "Or":
            cats = {c.text.strip() for c in el.findall("Category") if c.text}
            if cats:
                rules.append(("any", cats))
        elif el.tag == "And":
            cats = {c.text.strip() for c in el.findall("Category") if c.text}
            if cats:
                rules.append(("all", cats))
    return rules


def parse_menu_tree(menu_paths, dir_dirs=None):
    """applications.menu (system + optional user) → ordered menu list.

    Each entry: {slug, label, icon, rules, excludes}. Menus merge by
    slug across files (user Include rules extend, Excludes append).
    Returns [] when nothing parses → caller uses the fallback map.
    """
    dir_dirs = dir_dirs or DIRECTORY_DIRS
    menus = {}

    def add_or_merge(slug, label, icon, rules, excludes):
        if slug in menus:
            menus[slug]["rules"].extend(rules)
            menus[slug]["excludes"].update(excludes)
        else:
            menus[slug] = {"slug": slug, "label": label or slug.title(),
                           "icon": icon, "rules": rules,
                           "excludes": set(excludes)}

    for path in menu_paths:
        try:
            root = ET.parse(os.path.expanduser(path)).getroot()
        except (OSError, ET.ParseError):
            continue
        # XDG menu files: the ROOT element is <Menu><Name>Applications…>.
        # Tolerate (non-spec) wrappers that bury it one level down.
        tops = [root] if root.tag == "Menu" else root.findall("Menu")
        for top in tops:
            if (top.findtext("Name") or "").strip() != "Applications":
                # only the Applications tree is Kickoff's app section
                continue
            for m in top.findall("Menu"):
                if m.get("deleted") == "true" or m.get("hidden") == "true":
                    continue
                label, icon = _read_directory_file(
                    m.findtext("Directory"), dir_dirs)
                name = (m.findtext("Name") or "").strip()
                if not label and name:
                    label = name
                rules = []
                for inc in m.findall("Include"):
                    rules.extend(_collect_rules(inc))
                excludes = {c.text.strip() for c in m.findall(
                    "Exclude/Category") if c.text}
                if not rules and not excludes:
                    continue
                add_or_merge(_slugify(name or label), label, icon,
                             rules, excludes)
    return list(menus.values())


def menu_slug_for(app, menu):
    """App → first matching menu slug (XML order), or '' if none."""
    cats = set(app.get("categories") or [])
    for m in menu:
        if cats & m["excludes"]:
            continue
        for kind, need in m["rules"]:
            if kind == "any" and cats & need:
                return m["slug"]
            if kind == "all" and need <= cats:
                return m["slug"]
    return ""


def read_kickoff_favorites(db_path=None, logger=None):
    """Kickoff favorites (kactivitymanagerd SQLite), read-only, ordered.

    Returns [] on any error — never fatal, never a write.
    """
    p = os.path.expanduser(db_path or KICKOFF_DB)
    try:
        c = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=2.0)
        try:
            rows = c.execute(
                "SELECT targettedResource FROM ResourceLink "
                "WHERE initiatingAgent = ? AND usedActivity = ':global' "
                "ORDER BY rowid", (KICKOFF_AGENT,)).fetchall()
        finally:
            c.close()
        out = []
        for (r,) in rows:
            if r and r.startswith("applications:"):
                out.append(r[len("applications:"):])
        return out
    except (sqlite3.Error, OSError) as e:
        if logger:
            logger(f"kickoff favorites unreadable: {e}")
        return []


def slug_for(categories, menu=None):
    """Menu-aware slug; fallback precedence map when no menu tree."""
    if menu:
        return menu_slug_for({"categories": categories or []}, menu) or "more"
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
    """L-8 load-time: {desktop-id: slug}; strings only — unknown slugs
    are self-healing at build time (menu lookup wins)."""
    out, skipped = {}, 0
    for k, v in (raw.items() if isinstance(raw, dict) else []):
        if not isinstance(k, str) or not isinstance(v, str) or not v.strip():
            skipped += 1
            continue
        out[k] = v.strip()
    return out, skipped


def _norm_word(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def parse_kcms(dirs=KCM_DIRS, cache_path=None, ttl=KCM_TTL_S, now=None):
    """§L-18 r6: System Settings modules. Cache-first (Match is I/O-free):
    kcms.json beside apps.json; mtime+TTL gated; never fatal — [] on any
    failure. Returns [{"id","name","icon"}] sorted by name."""
    now = now if now is not None else time.time()
    if cache_path:
        cp = Path(cache_path).expanduser()
        try:
            if cp.exists() and now - cp.stat().st_mtime < ttl:
                data = json.loads(cp.read_text() or "[]")
                if isinstance(data, list):
                    return data
        except Exception:
            pass
    mods = {}
    for d in dirs:
        for f in sorted(Path(d).expanduser().glob("kcm*.desktop")):
            # KCMs are NOT menu apps: 83/84 host kcm*.desktop carry
            # NoDisplay=true (right for Kickoff, wrong here — System
            # Settings modules are opened via kcmshell/systemsettings,
            # never from an app menu). So: do NOT reuse parse_desktop's
            # NoDisplay skip; only require a Name and skip Hidden.
            try:
                cp = configparser.ConfigParser(interpolation=None,
                                               strict=False)
                cp.read_string(f.read_text(errors="replace"))
                e = cp["Desktop Entry"] if cp.has_section(
                    "Desktop Entry") else None
            except Exception:
                e = None
            if not e:
                continue
            try:
                if e.getboolean("Hidden", False):
                    continue
            except ValueError:
                pass
            name = (e.get("Name") or "").strip()
            if not name:
                continue
            mods[f.stem] = {"id": f.stem,
                            "name": name,
                            "icon": (e.get("Icon") or "").strip()
                                    or "preferences-system",
                            "path": str(f)}
    rows = sorted(mods.values(), key=lambda m: (m["name"].lower(), m["id"]))
    if cache_path:
        try:
            Path(cache_path).expanduser().write_text(json.dumps(rows))
        except Exception:
            pass
    return rows


# r6 (§L-18) foyer root branches — Apps · Settings · System · Update · About.
# Stepped 0.95→0.91 under the 1.0 anchor; Update/About are DIRECT actions.
FOYER_BRANCHES = [
    {"id": "foyer-apps", "title": "Apps",
     "sub": "FAVORITES · ALL CATEGORIES · THE FULL APP TREE",
     "icon": "applications-all", "rel": 0.95},
    {"id": "foyer-settings", "title": "Settings",
     "sub": "SYSTEM SETTINGS MODULES · TYPE TO FILTER",
     "icon": "preferences-system", "rel": 0.94},
    {"id": "foyer-system", "title": "System",
     "sub": "LOCK · SLEEP · LOG OUT · REBOOT · SHUT DOWN",
     "icon": "preferences-system", "rel": 0.93},
    {"id": "update-run", "title": "Update",
     "sub": "RUNS UJUST UPDATE IN KONSOLE · ENTER STARTS NOW",
     "icon": "system-software-update", "rel": 0.92},
    {"id": "about-copy", "title": "About",
     "sub": "SYSTEM SUMMARY · ENTER COPIES TO CLIPBOARD",
     "icon": "dialog-information", "rel": 0.91},
]

# r6: `apps system` drill. Subtext IS the confirmation (no KRunner dialog)
# — destructive rows name the consequence (verdict r6-1).
POWER_ROWS = [
    {"id": "power:lock", "title": "Lock Screen",
     "sub": "ENTER LOCKS NOW", "icon": "system-lock-screen"},
    {"id": "power:sleep", "title": "Sleep",
     "sub": "ENTER SLEEPS NOW", "icon": "system-suspend"},
    {"id": "power:logout", "title": "Log Out",
     "sub": "ENTER LOGS OUT NOW · CLOSES OPEN APPS",
     "icon": "system-log-out"},
    {"id": "power:reboot", "title": "Reboot",
     "sub": "ENTER REBOOTS NOW · CLOSES OPEN APPS",
     "icon": "system-reboot"},
    {"id": "power:shutdown", "title": "Shut Down",
     "sub": "ENTER SHUTS DOWN NOW · CLOSES OPEN APPS",
     "icon": "system-shutdown"},
]


def parse_query(rest, menu=None, allow_reserved=True):
    """L-4 token grammar (r3: menu-driven labels, multi-word names).
    Returns {"mode": "root"|"pins"|"cat"|"catlist"|"fuzzy",
     "slug": str, "filter": str, "slugs": [str], "tokens": [str]}
    """
    entries = ([(m["slug"], m["label"]) for m in menu]
               if menu else FALLBACK_LABELS)
    # r3.1: synthetic 'more' group = apps no menu rule claims (L-12)
    if menu:
        entries = entries + [("more", "More")]
    lookup = {}
    for slug, label in entries:
        lookup[_norm_word(slug)] = slug
        lookup[_norm_word(label)] = slug

    tokens = (rest or "").split()
    out = {"mode": "fuzzy", "slug": "", "filter": "",
           "slugs": [], "tokens": tokens}
    if not tokens:
        out["mode"] = "root"
        return out
    low = tokens[0].lower()
    # r6 (§L-18): foyer branch drills — reserved FIRST, before category
    # lookup ("settings"/"system" would otherwise prefix-match the
    # system-tools category and land in catlist).
    if allow_reserved and low == "browse":
        out.update(mode="browse", tokens=tokens[1:])
        return out
    if allow_reserved and low == "settings":
        out.update(mode="settings", filter=" ".join(tokens[1:]))
        return out
    if allow_reserved and low == "system":
        out.update(mode="system", filter=" ".join(tokens[1:]))
        return out
    if low == "pins":
        out["mode"] = "pins"
        return out
    # multi-word first: "system tools" / "system-tools"
    if len(tokens) >= 2:
        two = _norm_word(" ".join(tokens[:2]))
        if two in lookup:
            out["mode"] = "cat"
            out["slug"] = lookup[two]
            out["filter"] = " ".join(tokens[2:])
            return out
    if _norm_word(low) in lookup:
        out["mode"] = "cat"
        out["slug"] = lookup[_norm_word(low)]
        out["filter"] = " ".join(tokens[1:])
        return out
    if len(tokens) == 1:
        hits = [m["slug"] for m in (menu if menu else
                                    [{"slug": s, "label": l}
                                     for s, l in FALLBACK_LABELS])
                if _norm_word(m["slug"]).startswith(_norm_word(low))
                or _norm_word(m["label"]).startswith(_norm_word(low))]
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


def build_rows(apps, pins, freq, overrides, rest, menu=None, kickoff=None,
               dead_pin_logger=None, kcms=None, _no_reserved=False):
    """L-4/L-5 row list (r3: menu tree + kickoff favorites).

    apps: parsed + cached entries with id/path set. pins: ordered ids
    (hermes config). kickoff: ordered ids (Kickoff favorites, read-only).
    freq: {id: n}; overrides: {id: slug}; menu: menu-tree list or None.
    Returns dicts: id/title/sub/icon/tier/rel/actions/slug.
    Tiers: HIGHEST / HIGH / MODERATE (mapped to ints in hermes_runner).
    """
    by_id = {a["id"]: a for a in apps}
    kickoff = kickoff or []
    menu_slugs = {m["slug"] for m in menu} if menu else set()

    def slug_of(app):
        ov = overrides.get(app["id"])
        if ov and (not menu or ov in menu_slugs):
            return ov
        if menu:
            return menu_slug_for(app, menu) or "more"
        return slug_for(app["categories"])

    def cat_row(m, n):
        return {"id": f"appcat:{m['slug']}", "title": m["label"],
                "sub": f"{n} apps",
                "icon": icon_for_slug(m["slug"], m["icon"]),
                "tier": "HIGH", "rel": 0.85, "actions": [],
                "slug": m["slug"]}

    def label_for(slug):
        if menu:
            for m in menu:
                if m["slug"] == slug:
                    return m["label"]
            return slug.title()
        return dict(FALLBACK_LABELS).get(slug, slug.title())

    for pid in kickoff + pins:
        if pid not in by_id and dead_pin_logger:
            dead_pin_logger(pid)

    parsed = parse_query(rest, menu, allow_reserved=not _no_reserved)
    mode = parsed["mode"]

    if mode == "root":
        # r6 (§L-18): foyer root = anchor + FIVE branch rows only —
        # no loose apps, favorites, or KCMs on the dropdown (standing
        # directive). Typed filtering of branches happens BELOW (typed
        # queries parse as cat/catlist/fuzzy, never "root").
        rows = [{"id": "apps-root", "title": "Apps",
                 "sub": "PICK A BRANCH · ARROWS TO BROWSE · ENTER OPENS",
                 "icon": "start-here-kde", "tier": "HIGHEST",
                 "rel": 1.0, "actions": [], "slug": ""}]
        for b in FOYER_BRANCHES:
            rows.append({"id": b["id"], "title": b["title"], "sub": b["sub"],
                         "icon": b["icon"], "tier": "HIGH", "rel": b["rel"],
                         "actions": [], "slug": ""})
        return rows

    if parsed["tokens"] and len(parsed["tokens"]) == 1 \
            and mode in ("cat", "catlist", "fuzzy"):
        # r6 (§L-18): one typed token that prefix-matches a BRANCH NAME
        # filters the foyer root ("apps set" → Settings). Multi-token
        # stays a category/app search ("apps games min" = Mines).
        pre = _norm_word(parsed["tokens"][0])
        hit = [b for b in FOYER_BRANCHES
               if _norm_word(b["title"]).startswith(pre)]
        if hit:
            rows = [{"id": "apps-root", "title": "Apps",
                     "sub": "PICK A BRANCH · ARROWS TO BROWSE · "
                            "ENTER OPENS",
                     "icon": "start-here-kde", "tier": "HIGHEST",
                     "rel": 1.0, "actions": [], "slug": ""}]
            for b in hit:
                rows.append({"id": b["id"], "title": b["title"],
                             "sub": b["sub"], "icon": b["icon"],
                             "tier": "HIGH", "rel": b["rel"],
                             "actions": [], "slug": ""})
            return rows

    if mode == "settings":
        # r6 (§L-18): KCM fan-out, same shape as app categories — anchor
        # with COMPUTED N (never hardcoded; verdict r6-3) + 13 rows +
        # SHOWING footer when truncated. Match stays I/O-free: kcms come
        # from the caller's cache.
        kcms = kcms or []
        filt = (parsed.get("filter") or "").split()
        pool = kcms
        if filt:
            fl = " ".join(filt).lower()
            pool = [m for m in kcms if fl in m["name"].lower()]
        rows = [{"id": "settings-root", "title": "Settings",
                 "sub": f"{len(kcms)} MODULES · TYPE LETTERS TO FILTER",
                 "icon": "preferences-system", "tier": "HIGHEST",
                 "rel": 1.0, "actions": [], "slug": "settings"}]
        if not filt:
            pool = pool[:13]
        for i, m in enumerate(pool):
            rows.append({"id": f"setting:{m['id']}", "title": m["name"],
                         "sub": "SYSTEM SETTINGS MODULE · ENTER OPENS",
                         "icon": m["icon"], "tier": "HIGH",
                         "rel": round(0.84 - 0.01 * i, 2), "actions": [],
                         "slug": "settings"})
        if not filt and len(kcms) > 13:
            rows.append({"id": "apphelp",
                         "title": f"SHOWING 13 OF {len(kcms)} · "
                                  f"TYPE TO FILTER",
                         "sub": "KRUNNER SHOWS 15 ROWS · TYPING IS THE "
                                "SCROLL",
                         "icon": "help-browser", "tier": "MODERATE",
                         "rel": 0.3, "actions": [], "slug": ""})
        if len(rows) == 1:
            if not _no_reserved:
                # typed filter matched no KCM — e.g. "settings tools" was
                # never a settings query. Re-parse as a normal app query.
                return build_rows(apps, pins, freq, overrides, rest,
                                  menu=menu, kickoff=kickoff,
                                  kcms=kcms, _no_reserved=True)
            rows.append({"id": "apphelp", "title": "No modules match",
                         "sub": "system settings · try fewer letters",
                         "icon": "help-browser", "tier": "MODERATE",
                         "rel": 0.5, "actions": [], "slug": ""})
        return rows

    if mode == "system":
        # r6 (§L-18): anchor carries the no-confirm warning (verdict r6-2);
        # five stepped rows; no SHOWING footer (5 ≤ 13).
        filt = (parsed.get("filter") or "").lower()
        pool = POWER_ROWS
        if filt:
            pool = [p for p in POWER_ROWS
                    if p["title"].lower().replace(" ", "").startswith(
                        filt.replace(" ", ""))
                    or filt in p["title"].lower()]
        rows = [{"id": "system-root", "title": "System",
                 "sub": "5 POWER ACTIONS · NO CONFIRMATION DIALOG",
                 "icon": "preferences-system", "tier": "HIGHEST",
                 "rel": 1.0, "actions": [], "slug": "system"}]
        for i, p in enumerate(pool):
            rows.append({"id": p["id"], "title": p["title"], "sub": p["sub"],
                         "icon": p["icon"], "tier": "HIGH",
                         "rel": round(0.84 - 0.01 * i, 2), "actions": [],
                         "slug": "system"})
        if len(rows) == 1 and not _no_reserved:
            # filter matched no power row — "system tools" is the
            # system-tools CATEGORY. Re-parse as a normal app query.
            return build_rows(apps, pins, freq, overrides, rest,
                              menu=menu, kickoff=kickoff,
                              kcms=kcms, _no_reserved=True)
        return rows

    if mode in ("browse", "pins"):
        rows = []
        if mode == "browse":
            # r6: the r5 app tree lives BEHIND the Apps branch now — anchor
            # re-drives this view (apps-browse Run), Favorites branch first.
            rows.append({"id": "apps-browse",
                         "title": "Apps",
                         "sub": "FOYER APPS · FAVORITES + CATEGORIES",
                         "icon": "start-here-kde", "tier": "HIGHEST",
                         "rel": 1.0, "actions": [], "slug": ""})
        # Kickoff favorites — KDE's list, read-only (launch-only).
        # r5/r6: on browse they appear ONLY as the Favorites branch row;
        # the full list lives behind it (`apps pins` view).
        resolvable = [k for k in kickoff if k in by_id]
        if mode == "browse" and resolvable:
            rows.append({"id": "appcat:pins",
                         "title": "Favorites",
                         "sub": f"{len(resolvable)} APPS · YOUR KDE "
                                f"MENU FAVORITES",
                         "icon": "emblem-favorite", "tier": "HIGH",
                         "rel": 0.95, "actions": [], "slug": "pins"})
        shown = resolvable if mode == "pins" else []
        for i, kid in enumerate(shown):
            app = by_id[kid]
            r = app_row(app, slug_of(app), False,
                        0.95 - 0.005 * i, "HIGH")
            r["sub"] = f"favorite · {slug_of(app)}"
            r["actions"] = ["launch"]
            rows.append(r)
        # r4: hermes pins render ONLY in `apps pins` (root = foyer home)
        if mode == "pins":
            for pid in pins:
                app = by_id.get(pid)
                if app:
                    rows.append(app_row(app, slug_of(app), True,
                                        0.95, "HIGH"))
                    rows[-1]["sub"] = f"pinned · {slug_of(app)}"
        if mode == "pins" and not rows:
            return [{"id": "apphelp", "title": "No favorites yet",
                     "sub": "add in the KDE menu, or select an app → PIN",
                     "icon": "help-browser", "tier": "MODERATE",
                     "rel": 0.5, "actions": [], "slug": ""}]
        if mode == "pins":
            return rows
        # r4: frequency rows dropped from the root (foyer home shape);
        # freq data still feeds `apps pins` sorting elsewhere.
        # category rows in menu order — stepped 0.84−0.01i so KRunner's
        # 15-row cut keeps a deterministic prefix of the menu order.
        cat_i = 0
        if menu:
            for m in menu:
                n = sum(1 for a in apps if slug_of(a) == m["slug"])
                if n:
                    rows.append(cat_row(m, n))
                    rows[-1]["rel"] = round(0.84 - 0.01 * cat_i, 2)
                    cat_i += 1
            # r3.1: synthetic catch-all so unfiled apps stay browsable
            n_more = sum(1 for a in apps if slug_of(a) == "more")
            if n_more:
                rows.append({"id": "appcat:more", "title": "More",
                             "sub": f"{n_more} apps",
                             "icon": icon_for_slug("more"),
                             "tier": "HIGH", "rel": 0.74, "actions": [],
                             "slug": "more"})
        else:
            for slug, label in FALLBACK_LABELS:
                n = sum(1 for a in apps if slug_of(a) == slug)
                if n:
                    rows.append({"id": f"appcat:{slug}", "title": label,
                                 "sub": f"{n} apps",
                                 "icon": icon_for_slug(slug),
                                 "tier": "HIGH",
                                 "rel": round(0.84 - 0.01 * cat_i, 2),
                                 "actions": [], "slug": slug})
                    cat_i += 1
        return rows

    if mode == "catlist":
        rows = []
        wanted = parsed["slugs"]
        if menu:
            for m in menu:
                if m["slug"] in wanted:
                    n = sum(1 for a in apps if slug_of(a) == m["slug"])
                    rows.append(cat_row(m, n))
            if "more" in wanted:
                n = sum(1 for a in apps if slug_of(a) == "more")
                if n:
                    rows.append({"id": "appcat:more", "title": "More",
                                 "sub": f"{n} apps",
                                 "icon": icon_for_slug("more"),
                                 "tier": "HIGH", "rel": 0.85,
                                 "actions": [], "slug": "more"})
        else:
            for slug in wanted:
                n = sum(1 for a in apps if slug_of(a) == slug)
                rows.append({"id": f"appcat:{slug}",
                             "title": label_for(slug),
                             "sub": f"{n} apps",
                             "icon": icon_for_slug(slug),
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
    # r4 (§L-15): a drilled category is BOUNDED, never a wall — KRunner
    # cannot scroll (hard 15-row render budget), so emit an anchor + at
    # most 13 apps + a filter hint; typing narrows within the category.
    if mode == "cat" and not parsed.get("filter"):
        label = label_for(slug)
        n_pool = len(pool)
        if n_pool:
            rows.append({"id": f"appcat:{slug}", "title": label,
                         "sub": f"{n_pool} APPS · TYPE LETTERS TO FILTER",
                         "icon": icon_for_slug(slug), "tier": "HIGHEST",
                         "rel": 1.0, "actions": [], "slug": slug})
            matched = matched[:13]
    for i, (q, base, a) in enumerate(matched):
        rel = max(0.05, base - 0.01 * i)   # stepped: deterministic order
        rows.append(app_row(a, slug_of(a), a["id"] in pins, rel,
                            tier_for[q]))
    if (mode == "cat" and not parsed.get("filter")
            and len(pool) > 13):
        rows.append({"id": "apphelp",
                     "title": f"SHOWING 13 OF {len(pool)} · TYPE TO FILTER",
                     "sub": "KRUNNER SHOWS 15 ROWS · TYPING IS THE SCROLL",
                     "icon": "help-browser", "tier": "MODERATE",
                     "rel": 0.3, "actions": [], "slug": ""})
    if not rows:
        rows.append({"id": "apphelp", "title": "No apps match",
                     "sub": "try a category, e.g. apps games",
                     "icon": "help-browser", "tier": "MODERATE",
                     "rel": 0.5, "actions": [], "slug": ""})
    return rows


class AppStore:
    """L-2 enumeration + cache. Thread-safe; mtime+set gated; never fatal."""

    def __init__(self, dirs=None, cache_path=None, which=None, logger=None,
                 menu_paths=None, menu_dir_dirs=None, kickoff_db=None):
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
        # v0.7: the real Kickoff tree + favorites (both read-only sources)
        paths = menu_paths if menu_paths is not None else (
            [SYSTEM_MENU] +
            ([os.path.expanduser(USER_MENU)]
             if os.path.exists(os.path.expanduser(USER_MENU)) else []))
        self.menu = parse_menu_tree(paths, menu_dir_dirs)
        if not self.menu:
            self.logger("menu tree unparsed — falling back to "
                        "category heuristics")
        self.kickoff_db = kickoff_db
        self._kickoff = None
        self._kickoff_ts = 0.0

    def kickoff_favorites(self):
        """Kickoff favorites with a 5 s TTL (cheap, refresh-correct)."""
        now = time.time()
        if self._kickoff is None or now - self._kickoff_ts > 5.0:
            self._kickoff = read_kickoff_favorites(self.kickoff_db,
                                                   self.logger)
            self._kickoff_ts = now
        return self._kickoff

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
