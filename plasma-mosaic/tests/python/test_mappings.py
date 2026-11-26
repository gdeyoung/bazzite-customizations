import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
SPEC = importlib.util.spec_from_file_location("mapping_scanner", ROOT / "scanner.py")
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
scanner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = scanner
SPEC.loader.exec_module(scanner)


class MappingOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.applications = self.home / "applications"
        self.applications.mkdir()
        # Non-default XDG roots catch accidental hard-coded ~/.config paths.
        self.env = {"HOME": str(self.home),
                    "XDG_CONFIG_HOME": str(self.home / "preferences"),
                    "XDG_DATA_HOME": str(self.home / "data"),
                    "XDG_CACHE_HOME": str(self.home / "cache"),
                    "XDG_STATE_HOME": str(self.home / "state")}
        self.roots, _ = scanner.locations(self.env)

    def desktop(self, stem, name):
        (self.applications / (stem + ".desktop")).write_text(
            "[Desktop Entry]\nType=Application\nName=" + name + "\n")

    def file(self, category, relative, contents=b"owned"):
        path = Path(self.roots[category]) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def scan(self):
        return scanner.scan(self.env, io.StringIO(),
                            application_dirs=[str(self.applications)])

    def test_eight_families_measure_documented_roots_not_display_names(self):
        # Fixtures are actual upstream storage layouts, not generated from RULES.
        examples = [
            ("btop", "config", "btop/themes/custom.theme"),
            ("htop", "state", "htop/htop_history"),
            ("com.github.johnfactotum.Foliate", "data", "com.github.johnfactotum.Foliate/book.json"),
            ("blender", "cache", "blender/asset-library-index"),
            ("gimp", "config", "GIMP/2.10/gimprc"),
            ("vlc", "config", "vlc/vlcrc"),
            ("org.inkscape.Inkscape", "config", "inkscape/preferences.xml"),
            ("thunderbird", "home", ".thunderbird/profiles.ini"),
        ]
        for index, (stem, category, relative) in enumerate(examples):
            self.desktop(stem, "Localized title " + str(index))
            self.file(category, relative, bytes(index + 1))
        apps = {app["id"]: app for app in self.scan()}
        for index, (stem, category, _) in enumerate(examples):
            with self.subTest(stem=stem):
                app = apps[stem + ".desktop"]
                self.assertEqual(app["mappedBytes"], index + 1)
                self.assertEqual(len(app["paths"]), 1)
                item = app["paths"][0]
                self.assertEqual(item["confidence"], "known")
                self.assertEqual(item["category"], "data" if category == "home" else category)
                self.assertIn(stem, item["evidence"])
                self.assertTrue(item["source"].startswith("https://"))

    def test_display_name_cannot_impersonate_exact_desktop_id(self):
        self.desktop("unrelated.monitor", "btop")
        self.file("config", "btop/btop.conf")
        app = self.scan()[0]
        self.assertEqual(app["mappedBytes"], 0)
        self.assertEqual(len(app["paths"]), 1)
        self.assertEqual(app["paths"][0]["confidence"], "possible")
        self.assertEqual(app["paths"][0]["source"], "")

    def test_name_collision_with_exact_owner_is_shared_not_double_counted(self):
        self.desktop("btop", "Resource monitor")
        self.desktop("unrelated.monitor", "btop")
        self.file("config", "btop/btop.conf")
        apps = self.scan()
        self.assertEqual(len(apps), 2)
        self.assertEqual(sum(app["mappedBytes"] for app in apps), 0)
        for app in apps:
            self.assertEqual(len(app["paths"]), 1)
            self.assertEqual(app["paths"][0]["confidence"], "shared")
            self.assertEqual(app["paths"][0]["reason"], "shared")

    def test_shared_desktop_databases_and_vendor_parents_are_not_owned(self):
        self.desktop("com.github.johnfactotum.Foliate", "Foliate")
        self.desktop("org.gnome.Nautilus", "Files")
        self.desktop("firefox", "Firefox")
        self.file("config", "dconf/user", b"shared desktop settings")
        self.file("config", "gtk-3.0/settings.ini", b"shared toolkit settings")
        self.file("home", ".mozilla/other-application/profile", b"not Firefox")
        self.file("home", ".mozilla/firefox/profile/prefs.js", b"firefox")
        apps = {app["id"]: app for app in self.scan()}
        self.assertEqual(apps["firefox.desktop"]["mappedBytes"], 7)
        self.assertEqual(apps["org.gnome.Nautilus.desktop"]["paths"], [])
        self.assertEqual(apps["com.github.johnfactotum.Foliate.desktop"]["paths"], [])
        self.assertEqual(len(apps["firefox.desktop"]["paths"]), 1)

    def test_parent_name_match_excludes_child_rule_but_not_prefix_sibling(self):
        self.desktop("firefox", "Firefox")
        self.desktop("unrelated.vendor", ".mozilla")
        self.desktop("btop", "Resource monitor")
        self.desktop("unrelated.backup", "btop-backup")
        self.file("home", ".mozilla/firefox/prefs.js")
        # Name matches are only considered at XDG roots, so use cache/mozilla.
        self.file("cache", "mozilla/firefox/entry")
        self.desktop("unrelated.cache", "mozilla")
        self.file("config", "btop/btop.conf", b"123")
        self.file("config", "btop-backup/archive", b"other")
        apps = {app["id"]: app for app in self.scan()}
        firefox_cache = next(item for item in apps["firefox.desktop"]["paths"]
                             if item["category"] == "cache")
        self.assertEqual(firefox_cache["confidence"], "shared")
        self.assertEqual(apps["unrelated.cache.desktop"]["mappedBytes"], 0)
        self.assertEqual(apps["btop.desktop"]["mappedBytes"], 3)
        self.assertEqual(apps["unrelated.backup.desktop"]["mappedBytes"], 0)


if __name__ == "__main__":
    unittest.main()
