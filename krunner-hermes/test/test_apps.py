"""Launcher-lane tests — UX-SPEC §L r2. Pure logic; no session bus needed.
Run: /usr/bin/python3 -m unittest test.test_apps -v
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import apps_model                      # noqa: E402
import hermes_runner                   # noqa: E402


def desktop(name, categories="", generic="", keywords="", extra="",
            exec_line="app %u", try_exec=""):
    text = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={name}\n"
        f"GenericName={generic}\n"
        f"Exec={exec_line}\n"
        f"Categories={categories};\n"
        f"Keywords={keywords};\n"
    )
    if try_exec:
        text += f"TryExec={try_exec}\n"
    if extra:
        text += extra + "\n"
    return text


APPS = {
    "firefox.desktop": desktop("Firefox", "Network", "Web Browser",
                               "web;browser"),
    "konsole.desktop": desktop("Konsole", "TerminalEmulator", "Terminal",
                               "shell"),
    "mines.desktop": desktop("KMines", "Game", "Minesweeper", "game"),
    "kate.desktop": desktop("Kate", "Utility;TextEditor", "Text Editor",
                            "text"),
    "org.flatpak.app.desktop": desktop("FlatApp", "Network", "", "flat"),
    "kdenlive.desktop": desktop("Kdenlive", "AudioVideo;Video",
                                "Video Editor", "video"),
    "missioncenter.desktop": desktop("Mission Center", "System",
                                     "System Monitor", "monitor"),
}

MENU_XML = """<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu><Name>Internet</Name><Directory>Internet.directory</Directory>
    <Include><Category>Network</Category></Include></Menu>
  <Menu><Name>Games</Name><Directory>Game.directory</Directory>
    <Include><Category>Game</Category></Include></Menu>
  <Menu><Name>System Tools</Name><Directory>System-Tools.directory</Directory>
    <Include><Category>System</Category></Include>
    <Exclude><Category>X-Blocked</Category></Exclude></Menu>
  <Menu><Name>Multimedia</Name><Directory>Multimedia.directory</Directory>
    <Include><And><Category>AudioVideo</Category>
      <Category>Video</Category></And></Include></Menu>
  <Menu><Name>Accessories</Name><Directory>Utility.directory</Directory>
    <Include><Category>Utility</Category></Include></Menu>
</Menu>
"""

DIRECTORIES = {
    "Internet.directory": "[Desktop Entry]\nType=Directory\n"
                          "Name=Internet\nIcon=applications-internet\n",
    "Game.directory": "[Desktop Entry]\nType=Directory\n"
                      "Name=Games\nIcon=applications-games\n",
    "System-Tools.directory": "[Desktop Entry]\nType=Directory\n"
                              "Name=System Tools\n"
                              "Icon=applications-system\n",
    "Multimedia.directory": "[Desktop Entry]\nType=Directory\n"
                            "Name=Multimedia\nIcon=applications-multimedia\n",
    "Utility.directory": "[Desktop Entry]\nType=Directory\n"
                         "Name=Accessories\nIcon=applications-utilities\n",
}

USER_MENU_XML = """<Menu>
  <Name>Applications</Name>
  <Menu><Name>Internet</Name>
    <Include><Category>X-Fido</Category></Include></Menu>
</Menu>
"""


def write_menu_fixture(tmp):
    """Fixture menu + .directory files; returns (paths, dir_dirs)."""
    root = Path(tmp)
    (root / "menus").mkdir(exist_ok=True)
    (root / "menus" / "applications.menu").write_text(MENU_XML)
    dd = root / "desktop-directories"
    dd.mkdir(exist_ok=True)
    for fn, text in DIRECTORIES.items():
        (dd / fn).write_text(text)
    return ([str(root / "menus" / "applications.menu")], [str(dd)])


def write_kickoff_fixture(tmp, ids):
    """Fixture kactivitymanagerd DB; returns its path."""
    import sqlite3
    p = Path(tmp, "kickoff.db")
    if p.exists():
        p.unlink()
    c = sqlite3.connect(str(p))
    c.execute("CREATE TABLE ResourceLink (usedActivity TEXT, "
              "initiatingAgent TEXT, targettedResource TEXT)")
    for i, rid in enumerate(ids):
        c.execute("INSERT INTO ResourceLink VALUES (?,?,?)",
                  (":global", "org.kde.plasma.favorites.applications",
                   "applications:" + rid))
    # noise rows that must be ignored
    c.execute("INSERT INTO ResourceLink VALUES (?,?,?)",
              (":global", "org.kde.plasma.favorites.applications",
               "activities:something"))
    c.execute("INSERT INTO ResourceLink VALUES (?,?,?)",
              (":an-activity", "org.kde.plasma.favorites.applications",
               "applications:firefox.desktop"))
    c.commit()
    c.close()
    return str(p)


def fixture_store(tmp, apps=None, which=lambda n: "/usr/bin/" + n,
                  kickoff_ids=("firefox.desktop", "mines.desktop")):
    apps = apps if apps is not None else APPS
    d = Path(tmp, "applications")
    d.mkdir(parents=True, exist_ok=True)
    for fn, text in apps.items():
        (d / fn).write_text(text)
    menu_paths, dir_dirs = write_menu_fixture(tmp)
    return apps_model.AppStore(dirs=[str(d)],
                               cache_path=Path(tmp, "apps.json"),
                               which=which,
                               menu_paths=menu_paths,
                               menu_dir_dirs=dir_dirs,
                               kickoff_db=write_kickoff_fixture(
                                   tmp, list(kickoff_ids)))


def rows_by_id(rows):
    return {r["id"]: r for r in rows}


class TestParseDesktop(unittest.TestCase):
    def test_normal(self):
        app = apps_model.parse_desktop(APPS["firefox.desktop"])
        self.assertIsNotNone(app)
        self.assertEqual(app["name"], "Firefox")
        self.assertEqual(app["keywords"], ["web", "browser"])
        self.assertEqual(app["categories"], ["Network"])
        self.assertEqual(app["generic"], "Web Browser")

    def test_skips(self):
        for extra in ("NoDisplay=true", "Hidden=true",
                      "OnlyShowIn=GNOME;", "NotShowIn=KDE;"):
            self.assertIsNone(
                apps_model.parse_desktop(desktop("X", extra=extra)),
                extra)
        self.assertIsNotNone(apps_model.parse_desktop(
            desktop("X", extra="OnlyShowIn=KDE;GNOME;")))
        self.assertIsNone(apps_model.parse_desktop("not ini at all"))
        self.assertIsNone(apps_model.parse_desktop("[Other]\nType=Application\n"))
        self.assertIsNone(apps_model.parse_desktop(
            "[Desktop Entry]\nType=Link\nName=x\n"))
        self.assertIsNone(apps_model.parse_desktop(
            "[Desktop Entry]\nType=Application\n"))  # no Name

    def test_tryexec_kept_for_scan_filter(self):
        app = apps_model.parse_desktop(desktop("X", try_exec="missing-bin"))
        self.assertEqual(app["try_exec"], "missing-bin")


class TestExecDisplay(unittest.TestCase):
    def test_display(self):
        self.assertEqual(apps_model.exec_display("foo %u"), "foo")
        self.assertEqual(apps_model.exec_display("/usr/bin/bar -x %f"), "bar")
        self.assertEqual(apps_model.exec_display(""), "")


class TestSlugFor(unittest.TestCase):
    def test_precedence(self):
        self.assertEqual(apps_model.slug_for(["Network"]), "internet")
        self.assertEqual(apps_model.slug_for(["Game"]), "games")
        self.assertEqual(apps_model.slug_for(["TerminalEmulator"]), "system")
        self.assertEqual(apps_model.slug_for(["Settings", "Utility"]),
                         "settings")   # Settings wins over Utility
        self.assertEqual(apps_model.slug_for([]), "more")
        self.assertEqual(apps_model.slug_for(["Audio", "Video"]), "media")


class TestSanitize(unittest.TestCase):
    def test_pins(self):
        clean, skipped = apps_model.sanitize_pins(
            ["a.desktop", "a.desktop", " ", 5, "b.desktop", None])
        self.assertEqual(clean, ["a.desktop", "b.desktop"])
        self.assertEqual(skipped, 4)
        self.assertEqual(apps_model.sanitize_pins("nope"), ([], 0))

    def test_overrides(self):
        # v0.7: sanitize is shape-only; unknown slugs pass through and are
        # self-healed at build time (menu lookup wins over the override)
        warned = []
        clean, skipped = apps_model.sanitize_cat_overrides(
            {"a.desktop": "games", "b.desktop": "nope", 7: "media"},
            logger=lambda m: warned.append(m))
        self.assertEqual(clean, {"a.desktop": "games", "b.desktop": "nope"})
        self.assertEqual(skipped, 1)
        self.assertEqual(warned, [])


class TestParseQuery(unittest.TestCase):
    def test_modes(self):
        def mode(rest):
            return apps_model.parse_query(rest)["mode"]
        self.assertEqual(mode(""), "root")
        self.assertEqual(mode("pins"), "pins")
        self.assertEqual(mode("games"), "cat")
        self.assertEqual(mode("Games"), "cat")
        self.assertEqual(mode("s"), "catlist")
        self.assertEqual(mode("se fire"), "fuzzy")   # 2 tokens → not catlist
        self.assertEqual(mode("zzz"), "fuzzy")
        self.assertEqual(mode("internet"), "cat")
        p = apps_model.parse_query("Games fire web")
        self.assertEqual((p["mode"], p["slug"], p["filter"]),
                         ("cat", "games", "fire web"))
        self.assertEqual(apps_model.parse_query("s")["slugs"],
                         ["system", "settings"])   # display order: system 4th


class TestBuildRows(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.store = fixture_store(self.tmp.name)
        self.apps = self.store.snapshot()

    def tearDown(self):
        self.tmp.cleanup()

    def build(self, rest, pins=(), freq=None, overrides=None,
              dead_pin_logger=None):
        return apps_model.build_rows(
            self.apps, list(pins), freq or {}, overrides or {}, rest,
            dead_pin_logger=dead_pin_logger)

    def test_root_categories_only(self):
        rows = self.build("")
        self.assertEqual(rows[0]["id"], "apps-root")   # r2.2 anchor
        self.assertEqual((rows[0]["rel"], rows[0]["tier"]), (1.0, "HIGHEST"))
        cats = [r for r in rows if r["id"].startswith("appcat:")]
        # fallback map order: internet, media, games, system, utilities
        # (media present since the kdenlive AudioVideo fixture app)
        self.assertEqual([r["id"] for r in cats],
                         ["appcat:internet", "appcat:media", "appcat:games",
                          "appcat:system", "appcat:utilities"])
        self.assertEqual(cats[0]["sub"], "2 apps")
        self.assertEqual(cats[0]["tier"], "HIGH")   # pixel gate: Moderate
        # sank below native rows for the literal word "apps"
        # r4: stepped 0.84−0.01i — deterministic under the 15-row cap
        self.assertEqual([r["rel"] for r in cats],
                         [0.84, 0.83, 0.82, 0.81, 0.80])

    def test_root_pins_first_then_freq(self):
        # r4: root is the foyer home — favorites + categories ONLY.
        # pins and frequency are NOT root rows (they live in `apps pins`).
        rows = self.build("", pins=["konsole.desktop"],
                          freq={"firefox.desktop": 3, "konsole.desktop": 9,
                                "kate.desktop": 1, "mines.desktop": 0})
        ids = [r["id"] for r in rows]
        self.assertEqual(ids[0], "apps-root")
        self.assertNotIn("app:konsole.desktop", ids)   # pin → not root
        self.assertFalse(any("× ·" in r["sub"] for r in rows))  # no freq
        # the pin still renders in the pins view with its actions
        prows = self.build("pins", pins=["konsole.desktop"])
        self.assertEqual(prows[-1]["id"], "app:konsole.desktop")
        self.assertEqual(prows[-1]["sub"], "pinned · system")
        self.assertEqual(prows[-1]["actions"], ["launch", "unpin"])

    def test_root_no_freq_when_zero(self):
        rows = self.build("", freq={})
        self.assertFalse(any("× ·" in r["sub"] for r in rows))

    def test_pins_view(self):
        rows = self.build("pins", pins=["kate.desktop"])
        self.assertEqual([r["id"] for r in rows], ["app:kate.desktop"])
        rows = self.build("pins", pins=[])
        self.assertEqual(rows[0]["id"], "apphelp")
        self.assertEqual(rows[0]["title"], "No favorites yet")

    def test_dead_pin_skipped_logged(self):
        seen = []
        rows = self.build("", pins=["nope.desktop"],
                          dead_pin_logger=seen.append)
        self.assertFalse(any("nope" in r["id"] for r in rows))
        self.assertEqual(seen, ["nope.desktop"])

    def test_category_view_and_filter(self):
        # r4: drilled category = anchor + bounded app rows
        rows = self.build("games")
        self.assertEqual([r["id"] for r in rows],
                         ["appcat:games", "app:mines.desktop"])
        self.assertEqual(rows[0]["sub"], "1 APPS · TYPE LETTERS TO FILTER")
        self.assertEqual((rows[0]["rel"], rows[0]["tier"]), (1.0, "HIGHEST"))
        self.assertEqual(rows[1]["sub"], "Minesweeper")
        rows = self.build("games mines")
        self.assertEqual([r["id"] for r in rows], ["app:mines.desktop"])
        rows = self.build("games zzz")
        self.assertEqual(rows[0]["id"], "apphelp")

    def test_category_view_capped_with_hint(self):
        # r4 (§L-15): >13 apps → 13 rows + SHOWING hint, never a wall
        import tempfile, os
        d = Path(self.tmp.name, "bigcat")
        d.mkdir()
        for i in range(20):
            (d / f"big{i:02d}.desktop").write_text(
                "[Desktop Entry]\nType=Application\n"
                f"Name=Big App {i:02d}\nExec=big{i}\nCategories=Game;\n")
        store = apps_model.AppStore(dirs=[str(d)],
                                    cache_path=Path(self.tmp.name,
                                                    "big.json"))
        apps = store.snapshot()
        rows = apps_model.build_rows(apps, [], {}, {}, "games")
        ids = [r["id"] for r in rows]
        self.assertEqual(ids[0], "appcat:games")
        self.assertEqual(len([i for i in ids if i.startswith("app:")]), 13)
        self.assertEqual(ids[-1], "apphelp")
        self.assertEqual(rows[-1]["title"],
                         "SHOWING 13 OF 20 · TYPE TO FILTER")

    def test_category_alphabetical_steps(self):
        rows = self.build("internet")
        self.assertEqual([r["title"] for r in rows],
                         ["Internet", "Firefox", "FlatApp"])
        self.assertGreater(rows[1]["rel"], rows[2]["rel"])

    def test_catlist(self):
        rows = self.build("s")
        self.assertEqual([r["id"] for r in rows],
                         ["appcat:system", "appcat:settings"])

    def test_fuzzy_quality_ladder(self):
        exact = rows_by_id(self.build("firefox"))["app:firefox.desktop"]
        self.assertEqual((exact["rel"], exact["tier"]), (1.0, "HIGHEST"))
        prefix = rows_by_id(self.build("fire"))["app:firefox.desktop"]
        self.assertEqual((prefix["rel"], prefix["tier"]), (0.9, "HIGHEST"))
        kw = rows_by_id(self.build("browser"))["app:firefox.desktop"]
        self.assertEqual((kw["rel"], kw["tier"]), (0.55, "MODERATE"))

    def test_fuzzy_and_tokens(self):
        rows = self.build("fire web")           # name-prefix + keyword
        self.assertEqual([r["id"] for r in rows], ["app:firefox.desktop"])
        rows = self.build("fire zzz")           # AND fails
        self.assertEqual(rows[0]["id"], "apphelp")
        rows = self.build("flat")               # keywords-only hit
        self.assertEqual([r["id"] for r in rows],
                         ["app:org.flatpak.app.desktop"])

    def test_overrides(self):
        rows = self.build("development",
                          overrides={"kate.desktop": "development"})
        self.assertEqual([r["id"] for r in rows],
                         ["appcat:development", "app:kate.desktop"])

    def test_pinned_marker_in_fuzzy(self):
        row = rows_by_id(self.build("firefox", pins=["firefox.desktop"]))
        self.assertEqual(row["app:firefox.desktop"]["actions"],
                         ["launch", "unpin"])


class TestAppStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_scan_and_precedence(self):
        d1 = Path(self.tmp.name, "d1"); d2 = Path(self.tmp.name, "d2")
        d1.mkdir(); d2.mkdir()
        (d1 / "x.desktop").write_text(desktop("First"))
        (d2 / "x.desktop").write_text(desktop("Second"))
        store = apps_model.AppStore(dirs=[str(d1), str(d2)],
                                    cache_path=Path(self.tmp.name, "c.json"),
                                    which=lambda n: "/x")
        apps = store.snapshot()
        self.assertEqual(apps[0]["name"], "First")   # first dir wins
        # AppStore realpaths dirs (ostree /home → /var/home)
        self.assertTrue(apps[0]["path"].startswith(
            os.path.realpath(str(d1))))

    def test_tryexec_filter(self):
        apps = dict(APPS)
        apps["picky.desktop"] = desktop("Picky", "Utility",
                                        try_exec="missing-bin")
        d = Path(self.tmp.name, "app-tx"); d.mkdir()
        for fn, text in apps.items():
            (d / fn).write_text(text)
        gone = apps_model.AppStore(dirs=[str(d)],
                                   cache_path=Path(self.tmp.name, "g.json"),
                                   which=lambda n: None).snapshot()
        self.assertFalse(any(a["name"] == "Picky" for a in gone))
        kept = apps_model.AppStore(dirs=[str(d)],
                                   cache_path=Path(self.tmp.name, "k.json"),
                                   which=lambda n: "/usr/bin/" + n).snapshot()
        self.assertTrue(any(a["name"] == "Picky" for a in kept))

    def test_cache_roundtrip_and_hit(self):
        store = fixture_store(self.tmp.name)
        apps = store.snapshot()
        cache = json.loads(Path(self.tmp.name, "apps.json").read_text())
        self.assertEqual(cache["v"], 3)
        self.assertEqual(cache["apps"], apps)
        # cache hit: fingerprint unchanged → no rescan even if scan breaks
        store._scan = lambda: (_ for _ in ()).throw(AssertionError("rescan"))
        self.assertEqual(store.snapshot(), apps)

    def test_mtime_and_set_change_rescan(self):
        store = fixture_store(self.tmp.name)
        first = store.snapshot()
        target = Path(self.tmp.name, "applications", "kate.desktop")
        os.utime(target, ns=(0, 1))                 # bump mtime
        store._scan = lambda: first                 # stale → "rescan" path
        self.assertEqual(store.snapshot(), first)
        # dir set change alone forces reload
        store2 = apps_model.AppStore(
            dirs=[os.path.join(self.tmp.name, "applications"), "/nope"],
            cache_path=Path(self.tmp.name, "apps.json"),
            which=lambda n: "/x")
        store2._load_cache = lambda: None
        self.assertEqual(store2.snapshot(), first)

    def test_lookup(self):
        store = fixture_store(self.tmp.name)
        self.assertEqual(store.lookup("kate.desktop")["name"], "Kate")
        self.assertIsNone(store.lookup("missing.desktop"))


class TestRunnerIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = fixture_store(self.tmp.name)
        import copy
        self.conf = copy.deepcopy(hermes_runner.DEFAULT_CONF)
        self.conf["_app_pins"] = []
        self.conf["_app_cats"] = {}
        self.conf["_handoffs"] = []
        self.conf["_snippets"] = []
        self.conf["_ssh_hosts"] = []
        self.cache = hermes_runner.AnswerCache()

    def route(self, query, stats=None, appstore="default"):
        return hermes_runner.route(
            query, self.cache, set(), {}, self.conf,
            stats, self.store if appstore == "default" else appstore)

    def test_claims(self):
        rows = self.route("apps")
        self.assertTrue(rows)
        self.assertTrue(all(r[0].startswith(("app:", "appcat:", "apps-root"))
                            for r in rows))
        self.assertEqual(rows[0][0], "apps-root")
        self.assertTrue(self.route("APPs"))          # case-insensitive
        rows = self.route("apps games")
        self.assertEqual(rows[0][0], "appcat:games")   # r4 anchor
        self.assertEqual(rows[1][0], "app:mines.desktop")

    def test_no_claim_on_plain_names(self):
        for q in ("firefox", "fire", "ap"):
            rows = self.route(q)
            self.assertFalse(
                any(r[0].startswith(("app:", "appcat:")) for r in rows), q)

    def test_store_missing_info_row(self):
        rows = self.route("apps", appstore=None)
        self.assertEqual(rows[0][0], "apphelp")
        self.assertIn("WARMING", rows[0][2])

    def test_root_order_and_freq(self):
        # r5 foyer tree: root = anchor + FAVORITES BRANCH + categories.
        # No loose favorite/pin/freq rows on the dropdown — every row
        # is a branch that fans out (user directive 2026-11-02).
        self.conf["_app_pins"] = ["konsole.desktop"]
        fake = SimpleNamespace(data={"app_launches":
                                     {"firefox.desktop": 2,
                                      "kate.desktop": 1}})
        rows = self.route("apps", stats=fake)
        ids = [r[0] for r in rows]
        self.assertEqual(ids[0], "apps-root")
        self.assertEqual(ids[1], "appcat:pins")          # Favorites branch
        self.assertFalse(any(i.startswith("app:") for i in ids))
        by = {r[0]: r for r in rows}
        self.assertEqual(by["appcat:pins"][1], "Favorites")
        self.assertIn("2 APPS", by["appcat:pins"][2])    # fixture has 2
        # category rows come from the real menu tree, in menu order,
        # + synthetic 'more' (konsole's TerminalEmulator is unfiled)
        cat_ids = [r[0] for r in rows if r[0].startswith("appcat:")
                   and r[0] != "appcat:pins"]
        self.assertEqual(cat_ids, ["appcat:internet", "appcat:games",
                                   "appcat:system-tools",
                                   "appcat:multimedia",
                                   "appcat:accessories", "appcat:more"])
        self.assertEqual(by["appcat:system-tools"][1], "System Tools")
        self.assertEqual(by["appcat:system-tools"][3],
                         "applications-system")
        # the favorites themselves live behind the branch
        prows = self.route("apps pins")
        self.assertEqual(prows[0][0], "app:firefox.desktop")
        self.assertEqual(prows[0][2], "favorite · internet")

    def test_multiword_category(self):
        rows = self.route("apps system tools")
        # r4: drilled category leads with its anchor row
        self.assertEqual(rows[0][0], "appcat:system-tools")
        self.assertEqual(rows[1][0], "app:missioncenter.desktop")
        rows = self.route("apps system tools monitor")
        self.assertEqual(rows[0][0], "app:missioncenter.desktop")

    def test_pins_view_has_kickoff_block(self):
        self.conf["_app_pins"] = ["kate.desktop"]
        rows = self.route("apps pins")
        self.assertEqual([r[0] for r in rows],
                         ["app:firefox.desktop", "app:mines.desktop",
                          "app:kate.desktop"])

    def test_root_caps_favorites_with_pointer(self):
        # r5: root NEVER lists favorite apps — just the Favorites branch
        # with the full count. The `apps pins` view holds the whole list.
        d = Path(self.tmp.name, "applications")
        for i in range(11):
            (d / "hxf{}.desktop".format(i)).write_text(
                "[Desktop Entry]\nType=Application\nName=HX Fav {}\n"
                "Exec=hxf{}\n".format(i, i))
        apps = self.store.snapshot()          # dir mtime changed → rescan
        kickoff = ["hxf{}.desktop".format(i) for i in range(11)] + \
                  ["firefox.desktop"]
        rows = apps_model.build_rows(
            apps, [], {}, {}, "", menu=self.store.menu, kickoff=kickoff)
        ids = [r["id"] for r in rows]
        self.assertFalse(any(i.startswith("app:") for i in ids))
        fav = [r for r in rows if r["id"] == "appcat:pins"][0]
        self.assertEqual(fav["title"], "Favorites")
        self.assertEqual(fav["sub"], "12 APPS · YOUR KDE MENU FAVORITES")
        # dead ids don't inflate the count
        rows2 = apps_model.build_rows(
            apps, [], {}, {}, "",
            menu=self.store.menu,
            kickoff=kickoff[:11] + ["ghost.desktop"])
        fav2 = [r for r in rows2 if r["id"] == "appcat:pins"][0]
        self.assertEqual(fav2["sub"], "11 APPS · YOUR KDE MENU FAVORITES")
        # synthetic 'more' group renders (11 unfiled fixture apps)
        self.assertIn("appcat:more", ids)
        more = [r for r in rows if r["id"] == "appcat:more"][0]
        self.assertEqual(more["icon"], "applications-other")
        self.assertEqual(more["sub"], "12 apps")   # 11 fixture + konsole
        # the favorites branch holds ALL favorites, uncapped
        allrows = apps_model.build_rows(
            apps, [], {}, {}, "pins", menu=self.store.menu,
            kickoff=kickoff)
        favs_all = [r for r in allrows if r["id"].startswith("app:")]
        self.assertEqual(len(favs_all), 12)

    def test_apps_more_grammar(self):
        rows = self.route("apps more")
        # r4: 'more' drills like any category — anchor + bounded apps
        self.assertEqual(rows[0][0], "appcat:more")
        self.assertTrue(all(r[0].startswith("app:")
                            for r in rows
                            if r[0] not in ("apphelp", "appcat:more")),
                        rows[:3])

    def test_actions_list(self):
        ids = [a[0] for a in hermes_runner.ACTIONS_LIST]
        for want in ("launch", "pin", "unpin", "apps", "fav"):
            self.assertIn(want, ids)


class TestMenuTree(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_parse_fixture_tree(self):
        paths, dd = write_menu_fixture(self.tmp.name)
        menu = apps_model.parse_menu_tree(paths, dd)
        self.assertEqual([m["slug"] for m in menu],
                         ["internet", "games", "system-tools",
                          "multimedia", "accessories"])
        self.assertEqual([m["label"] for m in menu],
                         ["Internet", "Games", "System Tools",
                          "Multimedia", "Accessories"])
        self.assertEqual(menu[0]["icon"], "applications-internet")

    def test_rule_matching_and_exclude(self):
        paths, dd = write_menu_fixture(self.tmp.name)
        menu = apps_model.parse_menu_tree(paths, dd)
        # And-rule: AudioVideo alone is NOT multimedia ("" → "more" upstream)
        self.assertEqual(apps_model.menu_slug_for(
            {"categories": ["AudioVideo"]}, menu), "")
        self.assertEqual(apps_model.menu_slug_for(
            {"categories": ["AudioVideo", "Video"]}, menu), "multimedia")
        # include+exclude: System matches, X-Blocked excluded
        self.assertEqual(apps_model.menu_slug_for(
            {"categories": ["System"]}, menu), "system-tools")
        self.assertEqual(apps_model.menu_slug_for(
            {"categories": ["System", "X-Blocked"]}, menu), "")
        # first-match precedence: Utility+Network → internet wins (menu order)
        self.assertEqual(apps_model.menu_slug_for(
            {"categories": ["Utility", "Network"]}, menu), "internet")

    def test_missing_menu_falls_back_cleanly(self):
        self.assertEqual(apps_model.parse_menu_tree(["/nonexistent"]), [])

    def test_user_menu_merges_over_system(self):
        paths, dd = write_menu_fixture(self.tmp.name)
        user = Path(self.tmp.name, "menus", "user.menu")
        user.write_text(USER_MENU_XML)
        merged = apps_model.parse_menu_tree(paths + [str(user)], dd)
        inet = [m for m in merged if m["slug"] == "internet"][0]
        self.assertTrue(any(kind == "any" and "X-Fido" in need
                            for kind, need in inet["rules"]))

    def test_directory_file_missing_is_tolerated(self):
        # Menu referencing a .directory that doesn't exist: label from Name
        p = Path(self.tmp.name, "menus"); p.mkdir()
        (p / "m.menu").write_text(
            "<Menu><Name>Applications</Name>"
            '<Menu><Name>Weird</Name><Directory>Nope.directory</Directory>'
            "<Include><Category>X</Category></Include></Menu></Menu>")
        menu = apps_model.parse_menu_tree([str(p / "m.menu")])
        self.assertEqual(menu[0]["label"], "Weird")
        self.assertEqual(menu[0]["icon"], "")


class TestKickoffFavorites(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.log = []

    def test_order_and_filtering(self):
        db = write_kickoff_fixture(self.tmp.name,
                                   ["firefox.desktop", "mines.desktop"])
        favs = apps_model.read_kickoff_favorites(db, self.log.append)
        self.assertEqual(favs, ["firefox.desktop", "mines.desktop"])

    def test_missing_db(self):
        self.assertEqual(apps_model.read_kickoff_favorites(
            "/nonexistent.db", self.log.append), [])

    def test_ttl_refresh(self):
        db = write_kickoff_fixture(self.tmp.name, ["kate.desktop"])
        store = fixture_store(self.tmp.name, kickoff_ids=[])
        store.kickoff_db = db
        self.assertEqual(store.kickoff_favorites(), [])
        write_kickoff_fixture(self.tmp.name, ["firefox.desktop",
                                              "kate.desktop"])
        store._kickoff = None                       # force re-read
        self.assertEqual(store.kickoff_favorites(),
                         ["firefox.desktop", "kate.desktop"])


class TestRunDispatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = fixture_store(self.tmp.name)
        import copy
        self.conf = copy.deepcopy(hermes_runner.DEFAULT_CONF)
        self.conf["_app_pins"] = []
        self.conf["_app_cats"] = {}
        self.notifications = []
        self.popens = []
        self.hits = []

    def ctx(self):
        stats = SimpleNamespace(
            hit=lambda name, prefix=None: self.hits.append((name, prefix)))
        return SimpleNamespace(conf=self.conf, stats=stats,
                               appstore=self.store, cache=None)

    def test_launch_kioclient(self):
        import unittest.mock as mock
        with mock.patch.object(hermes_runner.shutil, "which",
                               lambda n: "/usr/bin/" + n), \
             mock.patch.object(hermes_runner.subprocess, "Popen",
                               self._popen) as p:
            hermes_runner.run_dispatch("app", "kate.desktop", "", "", self.ctx())
        argv = self.popens[0][0]
        self.assertEqual(argv, ["kioclient", "exec",
                                os.path.realpath(str(Path(
                                    self.tmp.name, "applications",
                                    "kate.desktop")))])
        self.assertTrue(all("/" not in str(a) or a.startswith("/")
                            for a in argv))
        self.assertEqual(self.hits, [("app_launches", "kate.desktop")])

    def _popen(self, argv, **kw):
        self.popens.append((list(argv), kw))
        return SimpleNamespace()

    def test_appcat_drill_uses_query_single_runner(self):
        # §L-15: drills MUST re-drive via querySingleRunner(hermes, …) —
        # plain query() clears single-runner mode and the category cap
        # squeezes Hermes back to ~1 row behind the native runners.
        import unittest.mock as mock
        import time as _time
        calls = []

        class FakeBus:
            def call_blocking(self, svc, path, iface, method, sig, args):
                calls.append((method, sig, args))

        with mock.patch.object(hermes_runner.dbus, "SessionBus",
                               lambda: FakeBus()):
            hermes_runner.run_dispatch("appcat", "games", "", "",
                                       self.ctx())
            # the re-drive fires from a daemon thread after 0.25 s —
            # keep the patch armed until it does
            deadline = _time.time() + 2
            while not calls and _time.time() < deadline:
                _time.sleep(0.05)
        self.assertEqual(calls, [("querySingleRunner", "ss",
                                  ("hermes", "apps games"))])

    def test_launch_gtk_fallback(self):
        import unittest.mock as mock
        with mock.patch.object(hermes_runner.shutil, "which",
                               lambda n: None if n == "kioclient"
                               else "/usr/bin/" + n), \
             mock.patch.object(hermes_runner.subprocess, "Popen", self._popen):
            hermes_runner.run_dispatch(
                "app", "org.flatpak.app.desktop", "", "", self.ctx())
        self.assertEqual(self.popens[0][0],
                         ["gtk-launch", "org.flatpak.app.desktop"])

    def test_launch_none_available(self):
        import unittest.mock as mock
        with mock.patch.object(hermes_runner.shutil, "which",
                               lambda n: None), \
             mock.patch.object(hermes_runner, "notify", self._notify), \
             mock.patch.object(hermes_runner.subprocess, "Popen", self._popen):
            hermes_runner.run_dispatch("app", "kate.desktop", "", "",
                                       self.ctx())
        self.assertEqual(self.notifications[0][0], "Hermes · cannot launch")
        self.assertEqual(self.popens, [])

    def test_unknown_id(self):
        import unittest.mock as mock
        with mock.patch.object(hermes_runner, "notify", self._notify), \
             mock.patch.object(hermes_runner.subprocess, "Popen", self._popen):
            hermes_runner.run_dispatch("app", "nope.desktop", "", "",
                                       self.ctx())
        self.assertIn("unknown app id", self.notifications[0][1])
        self.assertEqual(self.popens, [])

    def test_pin_roundtrip(self):
        conf_file = Path(self.tmp.name, "config.json")
        conf_file.write_text(json.dumps({"answer_prefix": "ai",
                                         "custom_key": 1}))
        import unittest.mock as mock
        with mock.patch.object(hermes_runner, "CONF_PATH", conf_file), \
             mock.patch.object(hermes_runner, "notify", self._notify):
            hermes_runner.run_dispatch("app", "kate.desktop", "", "pin",
                                       self.ctx())
            self.assertEqual(self.conf["_app_pins"], ["kate.desktop"])
            saved = json.loads(conf_file.read_text())
            self.assertEqual(saved["app_pins"], ["kate.desktop"])
            self.assertEqual(saved["custom_key"], 1)   # keys preserved
            self.assertEqual(self.hits, [("app_pins_set", None)])
            hermes_runner.run_dispatch("app", "kate.desktop", "", "unpin",
                                       self.ctx())
            self.assertEqual(self.conf["_app_pins"], [])
            self.assertEqual(
                json.loads(conf_file.read_text())["app_pins"], [])
            self.assertEqual(self.hits[-1], ("app_pins_removed", None))

    def test_appcat_credits_and_thread(self):
        import unittest.mock as mock
        import time as _time
        # shrink the redrive delay and WAIT INSIDE THE PATCH: the drill
        # thread must boom while _boom is armed, never under a later
        # test's SessionBus patch (leaked-thread race, found r4)
        with mock.patch.object(hermes_runner, "dbus",
                               SimpleNamespace(SessionBus=self._boom)), \
             mock.patch.object(hermes_runner,
                               "KRUNNER_REDRIVE_DELAY", 0.05):
            hermes_runner.run_dispatch("appcat", "games", "", "", self.ctx())
            _time.sleep(0.2)
        self.assertIn(("app_browses", None), self.hits)

    def test_appcat_invalid_slug_ignored(self):
        import unittest.mock as mock
        with mock.patch.object(hermes_runner, "dbus",
                               SimpleNamespace(SessionBus=self._boom)):
            hermes_runner.run_dispatch("appcat", "rm -rf", "", "", self.ctx())
        self.assertNotIn(("app_browses", None), self.hits)

    def test_apphelp_noop(self):
        hermes_runner.run_dispatch("apphelp", "", "", "", self.ctx())

    def test_empty_state_actions(self):
        import unittest.mock as mock
        import time as _time
        # same leaked-thread guard as test_appcat_credits_and_thread
        with mock.patch.object(hermes_runner, "dbus",
                               SimpleNamespace(SessionBus=self._boom)), \
             mock.patch.object(hermes_runner,
                               "KRUNNER_REDRIVE_DELAY", 0.05):
            hermes_runner.run_dispatch("", "", "", "apps", self.ctx())
            _time.sleep(0.2)

    def _boom(self):
        raise RuntimeError("no bus in tests")

    def _notify(self, summary, body, *a, **kw):
        self.notifications.append((summary, body))


class TestStats(unittest.TestCase):
    def test_maps_and_counters(self):
        with tempfile.TemporaryDirectory() as tmp:
            st = hermes_runner.Stats(path=os.path.join(tmp, "s.json"))
            st.hit("app_launches", prefix="a.desktop")
            st.hit("app_launches", prefix="a.desktop")
            st.hit("app_launches", prefix="b.desktop")
            st.hit("app_pins_set")
            st.hit("app_browses")
            self.assertEqual(st.data["app_launches"],
                             {"a.desktop": 2, "b.desktop": 1})
            self.assertEqual(st.data["app_pins_set"], 1)
            rep = st.report()
            self.assertIn("app_launches", rep)
            self.assertIn("app_browses", rep)


if __name__ == "__main__":
    unittest.main()
