from concurrent.futures import ThreadPoolExecutor
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
sys.path.insert(0, str(PROJECT))
import journal
import scanner
import workspace
from test_journal import measured_app, snapshot


def unresolved_installations(apps, env=None):
    return {"scannedAt": 1000, "groups": [], "apps": [
        {"id": app["id"], "groupKey": "", "status": "unknown", "reason": "Unowned fixture launcher"} for app in apps],
        "totalBytes": 0, "knownApps": 0, "unresolvedApps": len(apps), "issues": []}


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = {"HOME": str(self.home), "XDG_DATA_DIRS": str(self.home / "system")}
        self.roots, _ = scanner.locations(self.env)
        self.applications = self.home / "launchers"
        self.applications.mkdir()
        self.addCleanup(patch.stopall)
        patch("scanner.locations", return_value=(self.roots, [str(self.applications)])).start()
        self.install = patch("workspace.resolve_installations", side_effect=unresolved_installations).start()

    def desktop(self, desktop="example.desktop", extra=""):
        path = self.applications / desktop
        path.write_text("[Desktop Entry]\nType=Application\nName=Example\n" + extra)
        return path

    def mapping(self, name="specific", desktop="example.desktop", category="cache"):
        path = self.home / name
        path.mkdir(exist_ok=True)
        return {"id": desktop, "path": str(path), "category": category}

    def request(self, op, **fields):
        return workspace.handle({"op": op, **fields}, self.env)

    def test_load_does_not_discover_measure_or_resolve_packages(self):
        with patch("workspace.inventory", side_effect=AssertionError("discovery forbidden")), patch("scanner.measure", side_effect=AssertionError("walk forbidden")):
            view = self.request("load")
        self.install.assert_not_called()
        self.assertEqual(view["refreshedAt"], 0)
        self.assertEqual(view["history"], [])
        self.assertEqual(view["installations"]["scannedAt"], 0)
        self.assertFalse(view["settings"]["historyEnabled"])
        self.assertFalse((self.home / ".config").exists())

    def test_settings_persist_disable_alerts_and_require_history(self):
        with self.assertRaises(journal.JournalError):
            self.request("settings", patch={"alertsEnabled": True})
        view = self.request("settings", patch={"historyEnabled": True, "alertsEnabled": True, "thresholdBytes": 1048576})
        self.assertTrue(view["settings"]["alertsEnabled"])
        view = self.request("settings", patch={"historyEnabled": False})
        self.assertFalse(view["settings"]["alertsEnabled"])
        self.assertEqual(self.request("load")["settings"], view["settings"])
        with self.assertRaises(journal.JournalError):
            self.request("settings", patch={"historyEnabled": 1})
        with self.assertRaises(journal.JournalError):
            self.request("settings", patch={"unexpected": True})

    def test_mapping_upsert_remove_preserves_disappeared_paths_and_requires_inventory(self):
        self.desktop()
        mapping = self.mapping()
        view = self.request("mapping-save", mapping=mapping)
        self.assertEqual(view["mappings"], [mapping])
        updated = dict(mapping, category="data")
        self.assertEqual(self.request("mapping-save", mapping=updated)["mappings"], [updated])
        Path(mapping["path"]).rmdir()
        self.assertEqual(self.request("load")["mappings"], [updated])
        updated = dict(updated, category="state")
        self.assertEqual(self.request("mapping-save", mapping=updated)["mappings"], [updated])
        self.assertEqual(self.request("mapping-remove", id=mapping["id"], path=mapping["path"])["mappings"], [])
        with self.assertRaises(journal.JournalError):
            self.request("mapping-save", mapping=self.mapping("other", "missing.desktop"))
        with self.assertRaises(journal.JournalError):
            self.request("mapping-save", mapping={"id": "../example.desktop", "path": str(self.home / "other"), "category": "cache"})

    def test_real_scanner_uses_saved_mapping_and_user_category(self):
        self.desktop()
        mapping = self.mapping()
        (Path(mapping["path"]) / "data").write_bytes(b"actual content")
        self.request("mapping-save", mapping=mapping)
        apps = scanner.scan(self.env, io.StringIO(), application_dirs=[str(self.applications)], rules={})
        self.assertEqual(apps[0]["mappedBytes"], len(b"actual content"))
        self.assertEqual(apps[0]["categories"]["cache"], len(b"actual content"))
        self.assertEqual(apps[0]["paths"][0]["reason"], "user")
        self.assertEqual(apps[0]["paths"][0]["path"], mapping["path"])

    def test_record_disabled_still_provides_current_cache_insight_without_state(self):
        app = measured_app(self.home / "cache-file", 19)
        view = self.request("record", snapshot=snapshot([app]))
        self.assertEqual(view["history"], [])
        self.assertEqual(view["insights"]["cache"][0]["bytes"], 19)
        self.assertEqual(view["growth"][0]["reason"], "no-baseline")
        self.assertFalse((Path(journal.paths(self.env)[1]) / "history.json").exists())
        self.assertEqual(view["notifications"], [])

    def test_deep_record_uses_stable_overview_insights_without_merging_scopes(self):
        overview = snapshot([measured_app(self.home / "first-cache", 10),
                             measured_app(self.home / "second-cache", 20, desktop="second.desktop")], 1000)
        deep = snapshot([measured_app(self.home / "first-cache", 500)], 2000, mode="deep")
        self.request("settings", patch={"historyEnabled": True})
        view = self.request("record", snapshot=deep, overview=overview)
        self.assertEqual([(row["id"], row["bytes"]) for row in view["insights"]["cache"]],
                         [("second.desktop", 20), ("example.desktop", 10)])
        self.assertEqual(len(view["history"]), 1)
        self.assertEqual(view["history"][0]["mode"], "deep")
        self.assertEqual(view["history"][0]["mappedBytes"], 500)
        self.assertEqual(view["growth"][0]["mode"], "deep")
        self.assertEqual(self.request("load")["insights"]["cache"], [])
        with self.assertRaises(journal.JournalError):
            self.request("record", snapshot=deep, overview=deep)
        invalid = copy.deepcopy(overview)
        invalid["apps"][0]["mappedBytes"] = 999
        with self.assertRaises(journal.JournalError):
            self.request("record", snapshot=deep, overview=invalid)

    def test_deep_insights_fall_back_only_to_saved_overview(self):
        overview = snapshot([measured_app(self.home / "cache-file", 10)], 1000)
        deep = snapshot([measured_app(self.home / "cache-file", 200)], 2000, mode="deep")
        self.assertEqual(self.request("record", snapshot=deep)["insights"]["cache"], [])
        self.request("settings", patch={"historyEnabled": True})
        self.request("record", snapshot=overview)
        view = self.request("record", snapshot=deep)
        self.assertEqual(view["insights"]["cache"][0]["bytes"], 10)
        self.assertEqual([item["mappedBytes"] for item in view["history"]], [10, 200])

    def test_record_alerts_are_new_only_and_clearing_preserves_mappings_and_app_data(self):
        self.desktop()
        mapping = self.mapping()
        self.request("mapping-save", mapping=mapping)
        self.request("settings", patch={"historyEnabled": True, "alertsEnabled": True, "thresholdBytes": 1048576})
        path = self.home / "data-file"
        first = snapshot([measured_app(path, 3)], 1000)
        second = snapshot([measured_app(path, 1048579)], 2000)
        self.request("record", snapshot=first)
        view = self.request("record", snapshot=second)
        self.assertEqual(len(view["notifications"]), 1)
        self.assertEqual(view["notifications"][0]["delta"], 1048576)
        self.assertEqual(self.request("record", snapshot=second)["notifications"], [])
        self.assertEqual(self.request("view", snapshot=second)["notifications"], [])
        self.assertEqual(self.request("settings", patch={"thresholdBytes": 2097152}, snapshot=second)["notifications"], [])
        self.assertEqual(len(self.request("load")["alerts"]), 1)
        view = self.request("clear-history")
        self.assertEqual(view["history"], [])
        self.assertEqual(view["alerts"], [])
        self.assertEqual(view["mappings"], [mapping])
        self.assertTrue(view["settings"]["historyEnabled"])
        self.assertEqual(path.stat().st_size, 1048579)
        self.assertTrue(Path(mapping["path"]).is_dir())

    def test_concurrent_replays_persist_one_alert(self):
        self.request("settings", patch={"historyEnabled": True, "alertsEnabled": True, "thresholdBytes": 1048576})
        path = self.home / "concurrent-data"
        first = snapshot([measured_app(path, 1)], 1000)
        second = snapshot([measured_app(path, 1048577)], 2000)
        self.request("record", snapshot=first)
        barrier = threading.Barrier(2)
        def record():
            barrier.wait()
            return self.request("record", snapshot=second)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: record(), range(2)))
        self.assertEqual(sum(len(view["notifications"]) for view in results), 1)
        state = self.request("load")
        self.assertEqual(len(state["history"]), 2)
        self.assertEqual(len(state["alerts"]), 1)

    def test_leftovers_use_exact_absent_rules_and_never_claim_uninstalled(self):
        path = Path(self.roots["cache"]) / "leftover"
        path.mkdir(parents=True)
        (path / "contents").write_bytes(b"1234567")
        rules = {"absent": {"cache": ["leftover"]}}
        rows, warnings = workspace.possible_leftovers([], self.roots, [], True, rules=rules)
        self.assertEqual(warnings, [])
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["id"], rows[0]["bytes"], rows[0]["status"]), ("absent.desktop", 7, "complete"))
        installed = [{"id": "absent.desktop", "paths": []}]
        self.assertEqual(workspace.possible_leftovers(installed, self.roots, [], True, rules=rules)[0], [])

    def test_incomplete_inventory_and_mapping_suppress_all_leftover_claims(self):
        mapping = self.mapping(desktop="absent.desktop")
        for complete, mapped in ((False, True), (True, False)):
            with self.subTest(complete=complete), patch("scanner.measure", side_effect=AssertionError("must not measure")):
                rows, warnings = workspace.possible_leftovers([], self.roots, [mapping], complete, mapped, rules={})
            self.assertEqual(rows, [])
            self.assertTrue(warnings)
        self.applications.joinpath("broken.desktop").write_text("not desktop metadata")
        with patch("workspace.RULES", {"absent": {"cache": ["possible"]}}):
            view = self.request("view")
        self.assertEqual(view["leftovers"], [])
        self.assertTrue(any("discovery was incomplete" in warning for warning in view["warnings"]))

    def test_any_live_overlap_suppresses_candidates_and_absent_duplicates_count_once(self):
        mapping = self.mapping(desktop="absent.desktop")
        root = Path(mapping["path"])
        (root / "child").mkdir()
        for live_path in (str(root), str(root / "child"), str(root.parent)):
            for confidence in ("known", "possible", "shared"):
                apps = [{"id": "installed.desktop", "paths": [{"path": live_path, "confidence": confidence}]}]
                rows, _ = workspace.possible_leftovers(apps, self.roots, [mapping], True, rules={})
                self.assertEqual(rows, [])
        second = dict(mapping, id="also-absent.desktop")
        nested = dict(mapping, id="nested-absent.desktop", path=str(root / "child"))
        rows, _ = workspace.possible_leftovers([], self.roots, [mapping, second, nested], True, rules={})
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["path"], mapping["path"])

    def test_leftover_unknown_and_partial_measurements_remain_honest(self):
        mapping = self.mapping(desktop="absent.desktop")
        measured = scanner.measure(mapping["path"], scanner.Budget())
        for status, size in (("denied", None), ("missing", None), ("symlink", None), ("error", None), ("partial", 4)):
            with self.subTest(status=status), patch("scanner.measure", return_value=dict(measured, status=status, bytes=size)):
                rows, _ = workspace.possible_leftovers([], self.roots, [mapping], True, rules={})
            self.assertEqual((rows[0]["status"], rows[0]["bytes"]), (status, size))
        with patch("workspace.LEFTOVER_LIMITS", scanner.Limits(entries=0)):
            rows, warnings = workspace.possible_leftovers([], self.roots, [mapping], True, rules={})
        self.assertEqual(rows[0]["status"], "partial")
        self.assertTrue(warnings)

    def test_cli_outputs_one_bounded_real_response_and_errors(self):
        output = io.StringIO()
        status = workspace.main(io.BytesIO(b'{"op":"load"}\n'), output, self.env)
        self.assertEqual(status, 0)
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertTrue(json.loads(output.getvalue())["ok"])
        self.assertLessEqual(len(output.getvalue().encode()), workspace.MAX_MESSAGE)
        for raw in (b"not json\n", b'{"op":"record"}\n', b'{"op":"settings","patch":{"thresholdBytes":1e309}}\n',
                    b'{"op":"load","extra":true}\n', b'{"op":"load","op":"view"}\n', b"x" * (workspace.MAX_MESSAGE + 1)):
            with self.subTest(raw=raw[:80]):
                output = io.StringIO()
                self.assertNotEqual(workspace.main(io.BytesIO(raw), output, self.env), 0)
                result = json.loads(output.getvalue())
                self.assertFalse(result["ok"])
                self.assertTrue(result["error"])
                self.assertLessEqual(len(output.getvalue()), 8192)

    def test_corrupt_history_is_not_silently_replaced_by_clear(self):
        self.request("clear-history")
        target = Path(journal.paths(self.env)[1]) / "history.json"
        target.write_text('{"version":1,"snapshots":[{}],"alerts":[]}')
        before = target.read_bytes()
        for op in ("load", "clear-history", "view"):
            with self.subTest(op=op), self.assertRaises(journal.JournalError):
                self.request(op)
        self.assertEqual(target.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
