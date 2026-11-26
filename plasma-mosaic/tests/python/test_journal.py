import copy
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
sys.path.insert(0, str(PROJECT))
import journal
import scanner


def snapshot(apps, at=1000, mode="overview", inventory_complete=True, limited=False, partial=False):
    return {"mode": mode, "targetId": apps[0]["id"] if mode == "deep" else "", "scannedAt": at,
            "inventoryComplete": inventory_complete, "limited": limited, "partial": partial, "apps": apps}


def measured_app(path, size, desktop="example.desktop", category="cache", status="complete", issues=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    item = scanner.candidate(str(path), category, "known", "user", str(path.parent), "User assignment", "")
    item.update(scanner.measure(str(path), scanner.Budget()))
    if status != "complete":
        item["status"] = status
        item["issues"] = issues or ["limit"]
    elif issues:
        item["issues"] = issues
    return {"id": desktop, "name": desktop[:-8], "icon": "", "paths": [item], "mappedBytes": size,
            "categories": {key: size if key == category else 0 for key in journal.CATEGORIES},
            "status": "partial" if status != "complete" else "complete", "scannedAt": 1000}


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = {"HOME": str(self.home), "XDG_DATA_DIRS": str(self.home / "system")}
        self.root = self.home / "app-cache"

    def app(self, size, **kwargs):
        return measured_app(self.root, size, **kwargs)

    def summaries(self, before, after, **kwargs):
        return journal.summarize(snapshot(before, 1000, **kwargs)), journal.summarize(snapshot(after, 2000, **kwargs))

    def test_default_load_creates_no_state_and_relative_xdg_falls_back(self):
        env = {**self.env, "XDG_CONFIG_HOME": "relative", "XDG_STATE_HOME": "relative"}
        self.assertEqual(journal.read_settings(env), journal.DEFAULT_SETTINGS)
        self.assertEqual(journal.read_history(env)["snapshots"], [])
        self.assertFalse((self.home / ".config").exists())
        config, state = journal.paths(env)
        self.assertEqual(config, str(self.home / ".config/omarchy/mosaic"))
        self.assertEqual(state, str(self.home / ".local/state/omarchy/mosaic"))

    def test_settings_roundtrip_private_files_and_history_disabled(self):
        with journal.transaction(self.env) as store:
            value = dict(store.settings, thresholdBytes=journal.MIN_THRESHOLD)
            store.save_settings(value)
            self.assertEqual(store.record(journal.summarize(snapshot([self.app(8)]))), [])
        self.assertEqual(journal.read_settings(self.env)["thresholdBytes"], journal.MIN_THRESHOLD)
        config, state = map(Path, journal.paths(self.env))
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((config / "settings.json").stat().st_mode), 0o600)
        self.assertFalse((state / "history.json").exists())

    def test_corrupt_settings_and_history_are_not_reset_or_overwritten(self):
        with journal.transaction(self.env) as store:
            store.save_settings(store.settings)
            store.save_history()
        config, state = map(Path, journal.paths(self.env))
        for target, reader in ((config / "settings.json", journal.read_settings), (state / "history.json", journal.read_history)):
            original = target.read_bytes()
            target.write_bytes(b"{corrupt")
            with self.assertRaises(journal.JournalError):
                reader(self.env)
            with self.assertRaises(journal.JournalError):
                with journal.transaction(self.env):
                    self.fail("Corrupt state must not reach an update")
            self.assertEqual(target.read_bytes(), b"{corrupt")
            target.write_bytes(original)

    def test_duplicate_json_fields_and_nonfinite_numbers_are_rejected(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}'):
            with self.subTest(raw=raw), self.assertRaises(journal.JournalError):
                journal.decode(raw)

    def test_denied_state_and_symlinks_are_explicit_errors(self):
        with patch("journal.os.open", side_effect=PermissionError("denied")):
            with self.assertRaises(journal.JournalError):
                journal.read_settings(self.env)
        config = Path(journal.paths(self.env)[0])
        config.parent.mkdir(parents=True)
        elsewhere = self.home / "elsewhere"
        elsewhere.mkdir()
        config.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaises(journal.JournalError):
            journal.read_settings(self.env)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_existing_settings_cannot_be_world_readable_or_hardlinked(self):
        with journal.transaction(self.env) as store:
            store.save_settings(store.settings)
        target = Path(journal.paths(self.env)[0]) / "settings.json"
        target.chmod(0o644)
        with self.assertRaises(journal.JournalError):
            journal.read_settings(self.env)
        target.chmod(0o600)
        os.link(target, self.home / "linked-settings")
        with self.assertRaises(journal.JournalError):
            journal.read_settings(self.env)

    def test_mapping_rejects_broad_virtual_relative_and_symlink_paths(self):
        roots, _ = scanner.locations(self.env)
        target = self.home / "specific"
        target.mkdir()
        link = self.home / "alias"
        link.symlink_to(target, target_is_directory=True)
        (target / "file").write_bytes(b"x")
        fifo = self.home / "pipe"
        os.mkfifo(fifo)
        for path in ("/", str(self.home), roots["config"], roots["data"], "/usr", "/usr/share", "/proc/version",
                     "relative", str(target / ".." / "specific"), str(link), str(link / "file"), str(fifo)):
            with self.subTest(path=path), self.assertRaises(journal.JournalError):
                journal.validate_mapping({"id": "example.desktop", "path": path, "category": "data"}, self.env)
        valid = {"id": "example.desktop", "path": str(target), "category": "data"}
        self.assertEqual(journal.validate_mapping(valid, self.env), valid)
        target.joinpath("file").unlink()
        target.rmdir()
        self.assertEqual(journal.validate_mapping(valid, self.env, existing=True), valid)
        with self.assertRaises(journal.JournalError):
            journal.validate_mapping(valid, self.env)

    def test_mapping_and_threshold_limits(self):
        settings = copy.deepcopy(journal.DEFAULT_SETTINGS)
        for threshold in (0, journal.MIN_THRESHOLD - 1, journal.MAX_THRESHOLD + 1, True, 1.5):
            with self.subTest(threshold=threshold), self.assertRaises(journal.JournalError):
                journal.validate_settings(dict(settings, thresholdBytes=threshold), self.env)
        mappings = [{"id": "example.desktop", "path": str(self.home / f"root-{i}"), "category": "cache"} for i in range(25)]
        with self.assertRaises(journal.JournalError):
            journal.validate_settings(dict(settings, customMappings=mappings), self.env)
        with self.assertRaises(journal.JournalError):
            journal.validate_settings(dict(settings, customMappings=[mappings[0], mappings[0]]), self.env)
        with self.assertRaises(journal.JournalError):
            journal.validate_settings(dict(settings, alertsEnabled=True), self.env)

    def test_exact_growth_shrinkage_and_scope_separation(self):
        first, second = self.summaries([self.app(10)], [self.app(30)])
        row = journal.comparisons(second, first)[0]
        self.assertEqual((row["comparable"], row["delta"], row["previousAt"]), (True, 20, 1000))
        third = journal.summarize(snapshot([self.app(5)], 3000))
        self.assertEqual(journal.comparisons(third, second)[0]["delta"], -25)
        deep = journal.summarize(snapshot([self.app(50)], 4000, mode="deep"))
        row = journal.comparisons(deep, second)[0]
        self.assertIsNone(row["delta"])
        self.assertEqual(row["reason"], "no-baseline")
        rows = journal.growth([first, second, deep])
        self.assertEqual({row["mode"] for row in rows}, {"overview", "deep"})

    def test_partial_scan_is_not_skipped_as_the_previous_baseline(self):
        first = journal.summarize(snapshot([self.app(10)], 1000))
        second = journal.summarize(snapshot([self.app(15, status="partial")], 2000, partial=True))
        third = journal.summarize(snapshot([self.app(30)], 3000))
        row = journal.growth([first, second, third])[0]
        self.assertEqual(row["previousAt"], 2000)
        self.assertEqual(row["reason"], "incomplete")
        self.assertIsNone(row["delta"])
        self.assertIsNone(journal.comparisons(second, first)[0]["delta"])

    def test_complete_application_can_compare_in_partial_overview(self):
        first_apps = [self.app(10), measured_app(self.home / "other", 2, desktop="other.desktop", status="partial")]
        second_apps = [self.app(20), measured_app(self.home / "other", 3, desktop="other.desktop", status="partial")]
        first, second = self.summaries(first_apps, second_apps, partial=True, limited=True)
        rows = {row["id"]: row for row in journal.comparisons(second, first)}
        self.assertTrue(first["partial"])
        self.assertEqual(rows["example.desktop"]["delta"], 10)
        self.assertFalse(rows["other.desktop"]["comparable"])

    def test_incomplete_preceding_owner_and_hardlinks_disable_accounting(self):
        first_apps = [measured_app(self.home / "first", 1, desktop="first.desktop", status="partial"), self.app(10)]
        second_apps = [measured_app(self.home / "first", 2, desktop="first.desktop", status="partial"), self.app(20)]
        first, second = self.summaries(first_apps, second_apps, partial=True)
        row = next(row for row in journal.comparisons(second, first) if row["id"] == "example.desktop")
        self.assertEqual(row["reason"], "accounting-uncertain")
        first, second = self.summaries([self.app(10, issues=["hardlink"])], [self.app(30)])
        self.assertEqual(journal.comparisons(second, first)[0]["reason"], "accounting-uncertain")
        first, second = self.summaries([self.app(10)], [self.app(20)], inventory_complete=False)
        self.assertFalse(journal.comparisons(second, first)[0]["comparable"])

    def test_ownership_and_global_accounting_changes_invalidate_deltas(self):
        first, second = self.summaries([self.app(10)], [self.app(20, category="data")])
        self.assertEqual(journal.comparisons(second, first)[0]["reason"], "ownership-changed")
        first = journal.summarize(snapshot([self.app(10)], 1000))
        second = journal.summarize(snapshot([self.app(20), measured_app(self.home / "other", 2, desktop="other.desktop")], 2000))
        self.assertEqual(journal.comparisons(second, first)[0]["reason"], "accounting-changed")

    def test_unknown_is_not_zero_and_malformed_totals_are_rejected(self):
        app = self.app(0)
        app.update(paths=[], mappedBytes=0, categories=dict.fromkeys(journal.CATEGORIES, 0), status="unmapped")
        first, second = self.summaries([app], [self.app(30)])
        self.assertIsNone(first["apps"][0]["bytes"])
        self.assertEqual(journal.comparisons(second, first)[0]["reason"], "unmapped")
        app = self.app(10)
        app["mappedBytes"] = 11
        with self.assertRaises(journal.JournalError):
            journal.summarize(snapshot([app]))
        app = self.app(10)
        app["paths"][0]["issues"] = ["cancelled"]
        with self.assertRaises(journal.JournalError):
            journal.summarize(snapshot([app]))

    def test_alert_threshold_boundary_replay_and_retention(self):
        first = journal.summarize(snapshot([self.app(1)], 1000))
        second = journal.summarize(snapshot([self.app(1 + journal.MIN_THRESHOLD)], 2000))
        with journal.transaction(self.env) as store:
            store.save_settings(dict(store.settings, historyEnabled=True, alertsEnabled=True, thresholdBytes=journal.MIN_THRESHOLD))
            self.assertEqual(store.record(first), [])
            alerts = store.record(second)
            self.assertEqual(len(alerts), 1)
            self.assertEqual(alerts[0]["delta"], journal.MIN_THRESHOLD)
        with journal.transaction(self.env) as store:
            self.assertEqual(store.record(second), [])
            self.assertEqual(store.record(first), [])
            self.assertEqual(len(store.state["alerts"]), 1)
            self.assertEqual(len(store.state["snapshots"]), 2)
            conflict = copy.deepcopy(second)
            conflict["apps"][0]["name"] = "changed"
            with self.assertRaises(journal.JournalError):
                store.record(conflict)
            below = journal.summarize(snapshot([self.app(2 * journal.MIN_THRESHOLD)], 3000))
            self.assertEqual(store.record(below), [])
            for at in range(4000, 68000, 1000):
                summary = copy.deepcopy(below)
                summary["at"] = at
                summary["key"] = journal.scan_key("overview", "", at)
                store.record(summary)
        state = journal.read_history(self.env)
        self.assertEqual(len(state["snapshots"]), 60)
        self.assertLessEqual(len(journal.encode(state)), journal.MAX_HISTORY_BYTES)
        self.assertEqual(state["snapshots"][-1]["at"], 67000)

    def test_encoded_history_budget_and_alert_retention_are_enforced(self):
        template = journal.summarize(snapshot([self.app(1)], 1000))
        scans = []
        for at in range(1000, 11000, 1000):
            item = copy.deepcopy(template)
            item["at"], item["key"] = at, journal.scan_key("overview", "", at)
            scans.append(item)
        with journal.transaction(self.env) as store:
            store.state["snapshots"] = scans
            cap = len(journal.encode(dict(store.state, snapshots=scans[-2:])))
            with patch("journal.MAX_HISTORY_BYTES", cap):
                store.save_history()
                saved = journal.read_history(self.env)
                self.assertEqual(saved["snapshots"], scans[-2:])
                self.assertLessEqual(len(journal.encode(saved)), cap)
            store.state["alerts"] = [
                {"key": journal.digest(["event", i]), "id": "example.desktop", "name": "Example",
                 "delta": journal.MIN_THRESHOLD, "at": 1000 + i, "thresholdBytes": journal.MIN_THRESHOLD}
                for i in range(55)]
            store.save_history()
        self.assertEqual(len(journal.read_history(self.env)["alerts"]), 50)
        self.assertEqual(journal.read_history(self.env)["alerts"][0]["at"], 1005)

    def test_global_mapping_count_and_utf16_metadata_bounds(self):
        mappings = [{"id": f"app-{i}.desktop", "path": str(self.home / f"root-{i}"), "category": "data"}
                    for i in range(129)]
        settings = dict(journal.DEFAULT_SETTINGS, customMappings=mappings[:128])
        self.assertEqual(len(journal.validate_settings(settings, self.env)["customMappings"]), 128)
        with self.assertRaises(journal.JournalError):
            journal.validate_settings(dict(settings, customMappings=mappings), self.env)
        app = self.app(1)
        app["name"] = "\U0001d11e" * 128
        self.assertEqual(journal.summarize(snapshot([app]))["apps"][0]["name"], app["name"])
        app["name"] += "\U0001d11e"
        with self.assertRaises(journal.JournalError):
            journal.summarize(snapshot([app]))

    def test_atomic_replace_failure_preserves_original_settings(self):
        with journal.transaction(self.env) as store:
            store.save_settings(store.settings)
        target = Path(journal.paths(self.env)[0]) / "settings.json"
        original = target.read_bytes()
        with self.assertRaises(journal.JournalError):
            with journal.transaction(self.env) as store, patch("journal.os.replace", side_effect=OSError("replace failed")):
                store.save_settings(dict(store.settings, historyEnabled=True))
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(sorted(path.name for path in target.parent.iterdir()), [".lock", "settings.json"])


if __name__ == "__main__":
    unittest.main()
