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
}


def fixture_store(tmp, apps=None, which=lambda n: "/usr/bin/" + n):
    apps = apps if apps is not None else APPS
    d = Path(tmp, "applications")
    d.mkdir(parents=True, exist_ok=True)
    for fn, text in apps.items():
        (d / fn).write_text(text)
    return apps_model.AppStore(dirs=[str(d)],
                               cache_path=Path(tmp, "apps.json"),
                               which=which)


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
        warned = []
        clean, skipped = apps_model.sanitize_cat_overrides(
            {"a.desktop": "games", "b.desktop": "nope", 7: "media"},
            logger=lambda m: warned.append(m))
        self.assertEqual(clean, {"a.desktop": "games"})
        self.assertEqual(skipped, 2)
        self.assertEqual(len(warned), 2)


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
        self.assertEqual([r["id"] for r in cats],
                         ["appcat:internet", "appcat:games",
                          "appcat:system", "appcat:utilities"])
        self.assertEqual(cats[0]["sub"], "2 apps")
        self.assertEqual(cats[0]["tier"], "HIGH")   # pixel gate: Moderate
        # sank below native rows for the literal word "apps"
        self.assertEqual(cats[0]["rel"], 0.85)

    def test_root_pins_first_then_freq(self):
        rows = self.build("", pins=["konsole.desktop"],
                          freq={"firefox.desktop": 3, "konsole.desktop": 9,
                                "kate.desktop": 1, "mines.desktop": 0})
        ids = [r["id"] for r in rows]
        self.assertEqual(ids[0], "apps-root")
        self.assertEqual(ids[1], "app:konsole.desktop")
        self.assertEqual(rows[1]["sub"], "pinned · system")
        self.assertEqual(rows[1]["actions"], ["launch", "unpin"])
        self.assertEqual(rows[1]["rel"], 0.95)
        # freq: konsole excluded (pinned), mines excluded (0), top-6 order
        self.assertEqual(ids[2], "app:firefox.desktop")
        self.assertEqual(rows[2]["sub"], "3× · internet")
        self.assertEqual(rows[2]["rel"], 0.90)
        self.assertEqual(ids[3], "app:kate.desktop")

    def test_root_no_freq_when_zero(self):
        rows = self.build("", freq={})
        self.assertFalse(any("× ·" in r["sub"] for r in rows))

    def test_pins_view(self):
        rows = self.build("pins", pins=["kate.desktop"])
        self.assertEqual([r["id"] for r in rows], ["app:kate.desktop"])
        rows = self.build("pins", pins=[])
        self.assertEqual(rows[0]["id"], "apphelp")
        self.assertEqual(rows[0]["title"], "No pins yet")

    def test_dead_pin_skipped_logged(self):
        seen = []
        rows = self.build("", pins=["nope.desktop"],
                          dead_pin_logger=seen.append)
        self.assertFalse(any("nope" in r["id"] for r in rows))
        self.assertEqual(seen, ["nope.desktop"])

    def test_category_view_and_filter(self):
        rows = self.build("games")
        self.assertEqual([r["id"] for r in rows], ["app:mines.desktop"])
        self.assertEqual(rows[0]["sub"], "Minesweeper")
        rows = self.build("games mines")
        self.assertEqual([r["id"] for r in rows], ["app:mines.desktop"])
        rows = self.build("games zzz")
        self.assertEqual(rows[0]["id"], "apphelp")

    def test_category_alphabetical_steps(self):
        rows = self.build("internet")
        self.assertEqual([r["title"] for r in rows], ["Firefox", "FlatApp"])
        self.assertGreater(rows[0]["rel"], rows[1]["rel"])

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
        self.assertEqual([r["id"] for r in rows], ["app:kate.desktop"])

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
        self.assertEqual(cache["v"], 2)
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
        self.assertEqual(rows[0][0], "app:mines.desktop")

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
        self.conf["_app_pins"] = ["konsole.desktop"]
        fake = SimpleNamespace(data={"app_launches":
                                     {"firefox.desktop": 2}})
        rows = self.route("apps", stats=fake)
        ids = [r[0] for r in rows]
        self.assertEqual(ids[0], "apps-root")
        self.assertEqual(ids[1], "app:konsole.desktop")
        self.assertIn("app:firefox.desktop", ids)

    def test_actions_list(self):
        ids = [a[0] for a in hermes_runner.ACTIONS_LIST]
        for want in ("launch", "pin", "unpin", "apps", "fav"):
            self.assertIn(want, ids)


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
        with mock.patch.object(hermes_runner, "dbus",
                               SimpleNamespace(SessionBus=self._boom)):
            hermes_runner.run_dispatch("appcat", "games", "", "", self.ctx())
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
        with mock.patch.object(hermes_runner, "dbus",
                               SimpleNamespace(SessionBus=self._boom)):
            hermes_runner.run_dispatch("", "", "", "apps", self.ctx())

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
