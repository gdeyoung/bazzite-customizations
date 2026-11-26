from collections import Counter
from contextlib import contextmanager
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
sys.path.insert(0, str(PROJECT))
SPEC = importlib.util.spec_from_file_location("app_data_scanner", PROJECT / "scanner.py")
scanner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = scanner
SPEC.loader.exec_module(scanner)


class ScannerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.user = self.home / "user-apps"
        self.system = self.home / "system-apps"
        self.user.mkdir()
        self.system.mkdir()
        self.env = {"HOME": str(self.home), "XDG_DATA_DIRS": str(self.home / "system")}
        self.roots, _ = scanner.locations(self.env)

    def desktop(self, directory, filename, name="Example", extra=""):
        path = directory / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("[Desktop Entry]\nType=Application\nName=" + name + "\n" + extra)
        return path

    def data(self, category, name, content=b"12345"):
        path = Path(self.roots[category]) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def assert_partition(self, result):
        breakdown = result["breakdown"]
        self.assertLessEqual(len(breakdown["children"]), 12)
        for child in breakdown["children"]:
            self.assertEqual(set(child), {"name", "bytes", "status", "issues"})
            self.assertLessEqual(len(child["name"].encode("utf-16-le", "surrogatepass")) // 2, 255)
            self.assertNotIn("/", child["name"])
        if result["bytes"] is not None:
            self.assertEqual(result["bytes"], breakdown["directBytes"] + breakdown["otherBytes"]
                             + sum(child["bytes"] or 0 for child in breakdown["children"]))
        self.assertLessEqual(len(result["skippedSamples"]), 8)
        for sample in result["skippedSamples"]:
            self.assertIn(sample["reason"], result["skippedCounts"])
            self.assertLessEqual(len(sample["relative"].encode("utf-16-le", "surrogatepass")) // 2, 512)

    def assert_measurement(self, result, status, size, issues):
        self.assertEqual({key: result[key] for key in ("status", "bytes", "issues")},
                         {"status": status, "bytes": size, "issues": issues})
        self.assertGreater(result["measuredAt"], 0)
        self.assert_partition(result)

    def run_scan(self, rules=None, limits=None, selected_id=None, clock=None, custom_mappings=None):
        stream = io.StringIO()
        kwargs = {"application_dirs": [str(self.user), str(self.system)],
                  "rules": rules, "selected_id": selected_id, "custom_mappings": custom_mappings}
        if clock is not None:
            kwargs["clock"] = clock
        apps = scanner.scan(self.env, stream, limits, **kwargs)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertTrue(all(len(line.encode()) + 1 <= scanner.MAX_LINE for line in stream.getvalue().splitlines()))
        self.assertIsInstance(records[0]["inventoryComplete"], bool)
        self.assertEqual(records[0], {"type": "begin", "version": 3, "totalApps": len(apps),
                                     "inventoryComplete": records[0]["inventoryComplete"],
                                     "totalPaths": sum(len(app["paths"]) for app in apps),
                                     "mode": "deep" if selected_id is not None else "overview",
                                     "targetId": selected_id if selected_id is not None else ""})
        self.assertEqual(records[-1]["type"], "done")
        inventory = [record["app"] for record in records if record["type"] == "app"]
        self.assertEqual(len(inventory), len(apps))
        self.assertEqual([r["type"] for r in records[1:len(apps) + 1]], ["app"] * len(apps))
        assembled = {app["id"]: copy.deepcopy(app) for app in inventory}
        completed, measured = set(), set()
        for app in inventory:
            self.assertEqual(app["scannedAt"], 0)
            self.assertFalse(any(key.startswith("_") for key in app))
            for item in app["paths"]:
                self.assertEqual(item["status"], "pending")
                self.assertIsNone(item["bytes"])
                self.assertEqual(item["measuredAt"], 0)
                self.assertEqual(item["breakdown"], scanner.empty_breakdown())
                self.assertEqual(item["skippedCounts"], {})
                self.assertEqual(item["skippedSamples"], [])
                self.assertTrue(item["evidence"])
        for record in records:
            if record["type"] == "path":
                app, item = assembled[record["id"]], record["path"]
                key = (app["id"], item["path"])
                self.assertNotIn(key, measured)
                measured.add(key)
                self.assertNotEqual(item["status"], "pending")
                self.assertGreater(item["measuredAt"], 0)
                self.assert_partition(item)
                index = next(i for i, p in enumerate(app["paths"]) if p["path"] == item["path"])
                app["paths"][index] = item
                if item["confidence"] == "known" and item["bytes"] is not None:
                    app["mappedBytes"] += item["bytes"]
                    app["categories"][item["category"]] += item["bytes"]
            elif record["type"] == "appDone":
                self.assertNotIn(record["id"], completed)
                completed.add(record["id"])
                app = assembled[record["id"]]
                self.assertTrue(all(item["status"] != "pending" for item in app["paths"]))
                app["status"], app["scannedAt"] = record["status"], record["scannedAt"]
                self.assertGreater(app["scannedAt"], 0)
        self.assertEqual(completed, set(assembled))
        self.assertEqual(list(assembled.values()), apps)
        return apps, records

    def test_xdg_user_precedence_hidden_and_nested_ids(self):
        self.desktop(self.system, "one.desktop", "System")
        self.desktop(self.user, "one.desktop", "User")
        self.desktop(self.system, "hidden.desktop")
        self.desktop(self.user, "hidden.desktop", extra="Hidden=true\n")
        self.desktop(self.user, "nested/tool.desktop", "Nested")
        apps, _ = self.run_scan({})
        self.assertEqual([(a["id"], a["name"]) for a in apps], [("nested-tool.desktop", "Nested"), ("one.desktop", "User")])
        self.assertTrue(all(a["status"] == "unmapped" for a in apps))
        roots, dirs = scanner.locations({**self.env, "XDG_CONFIG_HOME": "relative", "XDG_DATA_HOME": str(self.home / "custom")})
        self.assertEqual(roots["config"], str(self.home / ".config"))
        self.assertEqual(dirs[0], str(self.home / "custom/applications"))

    def test_raw_discovery_preserves_winning_desktop_provenance_only_until_mapping(self):
        self.desktop(self.system, "one.desktop", "System")
        winning = self.desktop(self.user, "one.desktop", "User", "X-Flatpak=org.example.One\n")
        budget = scanner.Budget()
        apps = scanner.discover([str(self.user), str(self.system)], budget)
        self.assertTrue(budget.inventory_complete)
        self.assertEqual(apps[0]["_desktopFile"], str(winning))
        self.assertEqual(apps[0]["_flatpak"], "org.example.One")
        scanner.map_paths(apps, self.roots, budget, {})
        self.assertFalse(any(key.startswith("_") for key in apps[0]))

    def test_missing_default_directories_and_hidden_launchers_keep_inventory_complete(self):
        self.desktop(self.user, "hidden.desktop", extra="Hidden=true\n")
        self.desktop(self.user, "nodisplay.desktop", extra="NoDisplay=true\n")
        budget = scanner.Budget()
        apps = scanner.discover([str(self.home / "absent"), str(self.user)], budget)
        self.assertEqual(apps, [])
        self.assertTrue(budget.inventory_complete)
        self.assertFalse(budget.warnings)

    def test_invalid_metadata_masks_lower_launcher_and_marks_inventory_incomplete(self):
        self.desktop(self.system, "one.desktop")
        invalid = self.user / "one.desktop"
        for payload in (b"not a desktop file", b"[Desktop Entry]\nType=Application\n",
                        b"[Desktop Entry]\nType=Application\nName=\xff\n",
                        b"x" * (scanner.Limits().metadata_bytes + 1)):
            with self.subTest(payload=payload[:40]):
                invalid.write_bytes(payload)
                apps, records = self.run_scan({})
                self.assertEqual(apps, [])
                self.assertFalse(records[0]["inventoryComplete"])
                self.assertIn("metadata", records[-1]["warnings"])

    def test_unreadable_metadata_and_application_directories_are_incomplete(self):
        self.desktop(self.user, "a.desktop", "A")
        with patch.object(scanner, "read_desktop", side_effect=PermissionError(13, "denied")):
            apps, records = self.run_scan({})
        self.assertEqual(apps, [])
        self.assertFalse(records[0]["inventoryComplete"])
        with patch.object(scanner.os, "scandir", side_effect=PermissionError(13, "denied")):
            budget = scanner.Budget()
            self.assertEqual(scanner.discover([str(self.user)], budget), [])
        self.assertFalse(budget.inventory_complete)
        self.assertIn("metadata", budget.warnings)

    def test_nested_discovery_disappearance_and_depth_limit_are_incomplete(self):
        self.desktop(self.user, "nested/a.desktop", "A")
        real_scandir = scanner.os.scandir

        def vanished(path):
            if path == str(self.user / "nested"):
                raise FileNotFoundError(2, "disappeared")
            return real_scandir(path)

        with patch.object(scanner.os, "scandir", side_effect=vanished):
            budget = scanner.Budget()
            scanner.discover([str(self.user)], budget)
        self.assertFalse(budget.inventory_complete)
        self.assertIn("metadata", budget.warnings)
        self.desktop(self.user, "/".join(["deep"] * 9) + "/a.desktop", "A")
        budget = scanner.Budget()
        scanner.discover([str(self.user)], budget)
        self.assertFalse(budget.inventory_complete)
        self.assertIn("limit", budget.warnings)

    def test_discovery_entry_limit_is_distinct_from_measurement_limits(self):
        self.desktop(self.user, "a.desktop", "A")
        self.data("data", "owned/file", b"123")
        _, records = self.run_scan({}, scanner.Limits(discovery_entries=0))
        self.assertFalse(records[0]["inventoryComplete"])
        self.assertTrue(records[-1]["limited"])
        _, records = self.run_scan({"a": {"data": ["owned"]}}, scanner.Limits(path_entries=1))
        self.assertTrue(records[0]["inventoryComplete"])
        self.assertTrue(records[-1]["limited"])

    def test_known_possible_and_stream_snapshots(self):
        self.desktop(self.user, "com.microsoft.VSCode.desktop", "Visual Studio Code")
        self.data("config", "Code/settings", b"1234567")
        self.data("data", "Visual Studio Code/possible", b"123")
        apps, records = self.run_scan()
        app = apps[0]
        self.assertEqual(app["mappedBytes"], 7)
        self.assertEqual(app["categories"]["config"], 7)
        self.assertEqual({p["confidence"] for p in app["paths"]}, {"known", "possible"})
        self.assertTrue(all(p["bytes"] is None for p in records[1]["app"]["paths"]))
        self.assertTrue(all(p["status"] == "complete" for p in app["paths"]))
        known = next(item for item in app["paths"] if item["confidence"] == "known")
        possible = next(item for item in app["paths"] if item["confidence"] == "possible")
        self.assertIn("com.microsoft.VSCode.desktop", known["evidence"])
        self.assertEqual(known["source"], scanner.SOURCES["com.microsoft.VSCode"])
        self.assertIn("com.microsoft.VSCode.desktop", possible["evidence"])
        self.assertEqual(possible["source"], "")

    def test_overlapping_roots_and_ambiguous_names_are_shared(self):
        self.desktop(self.user, "a.desktop", "Same")
        self.desktop(self.user, "b.desktop", "Same")
        self.data("config", "owned/nested/file")
        self.data("data", "Same/file")
        apps, _ = self.run_scan({"a": {"config": ["owned"]}, "b": {"config": ["owned/nested"]}})
        self.assertEqual(sum(a["mappedBytes"] for a in apps), 0)
        self.assertTrue(all(p["confidence"] == "shared" for a in apps for p in a["paths"]))
        self.assertTrue(all(a["id"] in p["evidence"] for a in apps for p in a["paths"]))

    def test_user_mapping_overrides_builtin_category_once_and_counts_as_known(self):
        self.desktop(self.user, "a.desktop", "A")
        path = self.data("config", "owned", b"1234567")
        assigned = [{"id": "a.desktop", "path": str(path), "category": "cache"}]
        apps, _ = self.run_scan({"a": {"config": ["owned"]}}, custom_mappings=assigned)
        app, = apps
        item, = app["paths"]
        self.assertEqual((item["reason"], item["confidence"], item["category"]), ("user", "known", "cache"))
        self.assertIn("a.desktop", item["evidence"])
        self.assertFalse(item["source"])
        self.assertEqual(app["mappedBytes"], 7)
        self.assertEqual(app["categories"], {"config": 0, "cache": 7, "data": 0, "state": 0})

    def test_user_category_is_not_overwritten_by_flatpak_namespace(self):
        self.desktop(self.user, "org.example.Tool.desktop", "Tool", "X-Flatpak=org.example.Tool\n")
        self.data("home", ".var/app/org.example.Tool/cache/file", b"123")
        path = self.home / ".var/app/org.example.Tool/cache"
        apps, _ = self.run_scan({}, custom_mappings=[
            {"id": "org.example.Tool.desktop", "path": str(path), "category": "state"}])
        item, = apps[0]["paths"]
        self.assertEqual((item["category"], item["reason"]), ("state", "user"))
        self.assertEqual(apps[0]["categories"]["state"], 3)
        self.assertEqual(apps[0]["categories"]["cache"], 0)

    def test_user_overlap_keeps_assignment_evidence_but_excludes_totals(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        self.data("data", "owned/nested/file", b"1234")
        assigned = [{"id": "a.desktop", "path": str(Path(self.roots["data"]) / "owned"), "category": "data"}]
        apps, _ = self.run_scan({}, custom_mappings=assigned)
        evidence = apps[0]["paths"][0]["evidence"]
        apps, _ = self.run_scan({"b": {"data": ["owned/nested"]}}, custom_mappings=assigned)
        self.assertTrue(all(item["confidence"] == "shared" for app in apps for item in app["paths"]))
        self.assertEqual(sum(app["mappedBytes"] for app in apps), 0)
        self.assertIn(evidence, apps[0]["paths"][0]["evidence"])

    def test_same_app_nested_user_roots_and_cross_app_identical_roots_are_shared(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        self.data("data", "owned/nested/file", b"1234")
        outer = str(Path(self.roots["data"]) / "owned")
        assigned = [{"id": "a.desktop", "path": outer, "category": "data"},
                    {"id": "a.desktop", "path": outer + "/nested", "category": "cache"},
                    {"id": "b.desktop", "path": outer, "category": "state"}]
        apps, _ = self.run_scan({}, custom_mappings=assigned)
        self.assertEqual(sum(len(app["paths"]) for app in apps), 3)
        self.assertEqual(sum(app["mappedBytes"] for app in apps), 0)
        self.assertTrue(all(item["confidence"] == "shared" for app in apps for item in app["paths"]))

    def test_user_roots_precede_guesses_and_overlap_is_checked_before_clipping(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        self.data("data", "owned/nested/file", b"1234")
        self.data("data", "A/guess")
        other = self.data("cache", "other", b"12")
        outer = str(Path(self.roots["data"]) / "owned")
        assigned = [{"id": "a.desktop", "path": outer, "category": "data"},
                    {"id": "b.desktop", "path": str(other), "category": "cache"}]
        apps, records = self.run_scan({"b": {"data": ["owned/nested"]}},
                                      scanner.Limits(paths=1), custom_mappings=assigned)
        self.assertEqual([app["paths"][0]["path"] for app in apps], [outer, str(other)])
        self.assertEqual(apps[0]["paths"][0]["confidence"], "shared")
        self.assertEqual(apps[0]["mappedBytes"], 0)
        self.assertEqual(apps[1]["mappedBytes"], 2)
        self.assertTrue(records[0]["inventoryComplete"])
        self.assertTrue(records[-1]["limited"])

    def test_explicit_root_remains_visible_after_discovery_uses_the_time_budget(self):
        self.desktop(self.user, "a.desktop", "A")
        assigned_path = self.data("data", "assigned", b"123")
        tick = [0.0]
        real_discover = scanner.discover

        def expire_after_discovery(*args):
            apps = real_discover(*args)
            tick[0] = 100.0
            return apps

        with patch.object(scanner, "discover", side_effect=expire_after_discovery):
            apps, records = self.run_scan({}, scanner.Limits(seconds=1), clock=lambda: tick[0],
                custom_mappings=[{"id": "a.desktop", "path": str(assigned_path), "category": "data"}])
        item, = apps[0]["paths"]
        self.assertEqual((item["path"], item["reason"], item["status"]),
                         (str(assigned_path), "user", "partial"))
        self.assertTrue(records[0]["inventoryComplete"])
        self.assertTrue(records[-1]["limited"])

    def test_user_known_roots_share_hardlink_accounting_but_guesses_do_not(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        payload = self.data("data", "assigned", b"123456")
        second = Path(self.roots["data"]) / "builtin"
        guess = Path(self.roots["data"]) / "A"
        os.link(payload, second)
        os.link(payload, guess)
        assigned = [{"id": "a.desktop", "path": str(payload), "category": "state"}]
        apps, _ = self.run_scan({"b": {"data": ["builtin"]}}, custom_mappings=assigned)
        self.assertEqual(sum(app["mappedBytes"] for app in apps), 6)
        possible, = [item for item in apps[0]["paths"] if item["confidence"] == "possible"]
        self.assertEqual(possible["bytes"], 6)
        self.assertEqual(apps[1]["paths"][0]["bytes"], 0)
        self.assertIn("hardlink", apps[1]["paths"][0]["issues"])

    def test_saved_missing_root_stays_unknown_and_missing_app_is_not_invented(self):
        self.desktop(self.user, "a.desktop", "A")
        missing = str(self.home / "missing")
        assigned = [{"id": "a.desktop", "path": missing, "category": "data"},
                    {"id": "absent.desktop", "path": missing, "category": "data"}]
        apps, _ = self.run_scan({}, custom_mappings=assigned)
        self.assertEqual([app["id"] for app in apps], ["a.desktop"])
        item, = apps[0]["paths"]
        self.assertEqual((item["status"], item["bytes"], item["reason"]), ("missing", None, "user"))
        self.assertEqual(apps[0]["status"], "partial")
        self.assertEqual(apps[0]["mappedBytes"], 0)

    def test_saved_user_root_replaced_by_symlink_is_not_traversed(self):
        self.desktop(self.user, "a.desktop", "A")
        outside = self.data("data", "outside/file", b"secret")
        linked = self.home / "assigned"
        linked.symlink_to(outside.parent, target_is_directory=True)
        apps, _ = self.run_scan({}, custom_mappings=[
            {"id": "a.desktop", "path": str(linked / "file"), "category": "data"}])
        item, = apps[0]["paths"]
        self.assertEqual((item["status"], item["bytes"]), ("symlink", None))
        self.assertEqual(apps[0]["mappedBytes"], 0)

    def test_scan_loads_saved_mappings_and_explicit_injection_bypasses_settings(self):
        self.desktop(self.user, "a.desktop", "A")
        path = self.data("data", "assigned", b"1234")
        settings_path = Path(self.roots["config"]) / "omarchy/mosaic/settings.json"
        settings_path.parent.mkdir(parents=True, mode=0o700)
        assigned = [{"id": "a.desktop", "path": str(path), "category": "cache"}]
        settings_path.write_text(json.dumps({"historyEnabled": False, "alertsEnabled": False,
                                            "thresholdBytes": 268435456, "customMappings": assigned}))
        settings_path.chmod(0o600)
        apps, _ = self.run_scan({})
        self.assertEqual(apps[0]["mappedBytes"], 4)
        self.assertEqual(apps[0]["categories"]["cache"], 4)
        settings_path.write_text("{not json")
        apps, _ = self.run_scan({}, custom_mappings=assigned)
        self.assertEqual(apps[0]["mappedBytes"], 4)
        stream = io.StringIO()
        with self.assertRaises(scanner.SettingsError) as failure:
            scanner.scan(self.env, stream, application_dirs=[str(self.user)], rules={})
        self.assertIn("custom mappings", str(failure.exception))
        self.assertEqual(stream.getvalue(), "")

    def test_settings_failure_has_an_explicit_terminal_cli_error(self):
        stream = io.StringIO()
        with patch.object(scanner.sys, "argv", ["scanner.py", "scan"]), \
                patch.object(scanner.sys, "stdout", stream), \
                patch.object(scanner, "scan", side_effect=scanner.SettingsError("Invalid custom mappings")), \
                patch.object(scanner.signal, "signal"), patch.object(scanner.signal, "setitimer"):
            self.assertEqual(scanner.main(), 1)
        self.assertEqual(json.loads(stream.getvalue()), {"type": "error", "message": "Invalid custom mappings"})

    def test_hardlinks_symlinks_and_special_files(self):
        root = self.home / "tree"
        root.mkdir()
        (root / "a").write_bytes(b"123456")
        os.link(root / "a", root / "b")
        outside = self.home / "outside"
        outside.write_bytes(b"not included")
        (root / "link").symlink_to(outside)
        os.mkfifo(root / "pipe")
        result = scanner.measure(str(root), scanner.Budget())
        self.assertEqual(result["bytes"], 6)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["issues"], ["hardlink", "special", "symlink"])
        self.assert_partition(result)
        self.assertEqual(result["skippedCounts"], {"hardlink": 1, "symlink": 1, "special": 1})
        self.assertEqual(result["breakdown"]["directFiles"], 2)
        result = scanner.measure(str(root / "link"), scanner.Budget())
        self.assertEqual(result["status"], "symlink")
        self.assertIsNone(result["bytes"])
        (self.home / "alias").symlink_to(root, target_is_directory=True)
        result = scanner.measure(str(self.home / "alias/a"), scanner.Budget())
        self.assertEqual(result["status"], "symlink")

    def test_hardlinks_across_known_roots_not_double_counted(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        first = self.data("data", "a/file", b"123456789")
        other = self.data("data", "b/file", b"")
        other.unlink()
        os.link(first, other)
        apps, _ = self.run_scan({"a": {"data": ["a"]}, "b": {"data": ["b"]}})
        self.assertEqual(sum(a["mappedBytes"] for a in apps), 9)
        self.assertIn("hardlink", apps[1]["paths"][0]["issues"])
        self.assertEqual(apps[1]["paths"][0]["status"], "complete")
        self.assertEqual(apps[1]["paths"][0]["skippedCounts"], {"hardlink": 1})
        deep, _ = self.run_scan({"a": {"data": ["a"]}, "b": {"data": ["b"]}},
                                selected_id="b.desktop")
        self.assertEqual(deep[0]["mappedBytes"], 9)
        self.assertEqual(deep[0]["paths"][0]["skippedCounts"], {})

    def test_entry_limit_and_deadline_are_partial(self):
        root = self.home / "tree"
        root.mkdir()
        for n in range(4):
            (root / str(n)).write_bytes(b"123")
        result = scanner.measure(str(root), scanner.Budget(scanner.Limits(path_entries=2)))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["bytes"], 3)
        self.assertIn("limit", result["issues"])
        self.assert_partition(result)
        self.assertEqual(result["skippedCounts"], {"limit": 1})
        self.assertIn(result["skippedSamples"][0]["relative"], {str(n) for n in range(4)})
        tick = [0]
        budget = scanner.Budget(scanner.Limits(seconds=1), clock=lambda: tick[0])
        tick[0] = 2
        result = scanner.measure(str(root), budget)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["bytes"], 0)
        self.assert_partition(result)
        self.assertEqual(result["skippedSamples"], [{"relative": ".", "reason": "limit", "truncated": False}])

    def test_permission_denied_and_child_partial(self):
        root = self.home / "tree"
        root.mkdir()
        (root / "good").write_bytes(b"1234")
        (root / "denied").mkdir()
        real_open = scanner.os.open
        def denied_open(path, flags, *args, **kwargs):
            if path == "denied":
                raise PermissionError(13, "Permission denied")
            return real_open(path, flags, *args, **kwargs)
        with patch.object(scanner.os, "open", side_effect=denied_open):
            result = scanner.measure(str(root), scanner.Budget())
            direct = scanner.measure(str(root / "denied"), scanner.Budget())
        self.assert_measurement(result, "partial", 4, ["permission"])
        self.assert_measurement(direct, "denied", None, ["permission"])
        self.assertEqual(result["breakdown"]["children"],
                         [{"name": "denied", "bytes": None, "status": "denied", "issues": ["permission"]}])
        self.assertEqual(result["skippedSamples"], [{"relative": "denied", "reason": "permission", "truncated": False}])
        self.assertEqual(direct["skippedSamples"], [{"relative": ".", "reason": "permission", "truncated": False}])

    def test_directory_replacement_detected_without_traversal(self):
        root = self.home / "tree"
        root.mkdir()
        (root / "private").write_bytes(b"secret")
        alternative = self.home / "other"
        alternative.mkdir()
        (alternative / "payload").write_bytes(b"must not count")
        real_open = scanner.os.open
        def changed_open(path, flags, *args, **kwargs):
            if path == "tree":
                return real_open(str(alternative), flags)
            return real_open(path, flags, *args, **kwargs)
        with patch.object(scanner.os, "open", side_effect=changed_open):
            result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "partial", 0, ["changed"])
        self.assertEqual(result["skippedSamples"], [{"relative": ".", "reason": "changed", "truncated": False}])

    def test_flatpak_namespace_categories(self):
        self.desktop(self.user, "org.example.Tool.desktop", "Tool", "X-Flatpak=org.example.Tool\n")
        for category in scanner.CATEGORIES:
            self.data("home", ".var/app/org.example.Tool/" + category + "/file", b"12")
        apps, _ = self.run_scan({})
        self.assertEqual(apps[0]["categories"], dict.fromkeys(scanner.CATEGORIES, 2))
        self.assertEqual(apps[0]["mappedBytes"], 8)
        self.assertTrue(all(p["reason"] == "flatpak" for p in apps[0]["paths"]))
        self.assertTrue(all("org.example.Tool" in p["evidence"] and p["source"]
                            for p in apps[0]["paths"]))

    def test_markup_newline_paths_and_exec_are_inert(self):
        name = '<b>Odd & "App"</b>'
        marker = self.home / "executed"
        self.desktop(self.user, "odd.desktop", name, "Exec=touch " + str(marker) + "\n")
        weird = 'odd\n<markup> "quoted"'
        path = self.data("config", weird, b"123")
        apps, records = self.run_scan({"odd": {"config": [weird]}})
        self.assertEqual(apps[0]["name"], name)
        self.assertEqual(apps[0]["paths"][0]["path"], str(path))
        self.assertEqual(apps[0]["mappedBytes"], 3)
        self.assertEqual(apps[0]["paths"][0]["breakdown"],
                         {"children": [], "directBytes": 3, "directFiles": 1, "otherBytes": 0, "otherCount": 0})
        self.assertFalse(marker.exists())
        self.assertEqual(records[-1]["limited"], False)

    def test_disappeared_path_is_not_zero(self):
        result = scanner.measure(str(self.home / "missing"), scanner.Budget())
        self.assert_measurement(result, "missing", None, ["changed"])
        self.assertEqual(result["skippedSamples"], [{"relative": ".", "reason": "changed", "truncated": False}])

    def test_app_and_path_limits_are_signalled(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        apps, records = self.run_scan({}, scanner.Limits(apps=1))
        self.assertEqual(len(apps), 1)
        self.assertTrue(records[-1]["limited"])
        self.assertFalse(records[0]["inventoryComplete"])
        self.data("config", "one")
        self.data("config", "two")
        apps, records = self.run_scan({"a": {"config": ["one", "two"]}}, scanner.Limits(paths=1))
        self.assertEqual(len(apps[0]["paths"]), 1)
        self.assertTrue(records[-1]["limited"])
        self.assertTrue(records[0]["inventoryComplete"])

    def test_omitted_partial_and_denied_children_keep_other_accounting(self):
        root = self.home / "tree"
        root.mkdir()
        for size in range(2, 17):
            child = root / f"child-{size:02}"
            child.mkdir()
            (child / "payload").write_bytes(b"x" * size)
        (root / "partial/blocked").mkdir(parents=True)
        (root / "partial/file").write_bytes(b"x")
        (root / "denied").mkdir()
        real_open = scanner.os.open

        def denied_open(path, flags, *args, **kwargs):
            if path in ("blocked", "denied"):
                raise PermissionError(13, "Permission denied")
            return real_open(path, flags, *args, **kwargs)

        with patch.object(scanner.os, "open", side_effect=denied_open):
            result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "partial", 136, ["permission"])
        self.assertEqual(result["breakdown"]["otherBytes"], 10)
        self.assertEqual(result["breakdown"]["otherCount"], 5)
        self.assertTrue(all(child["status"] == "complete" for child in result["breakdown"]["children"]))
        self.assertEqual(result["skippedCounts"], {"permission": 2})
        self.assertEqual({sample["relative"] for sample in result["skippedSamples"]},
                         {"partial/blocked", "denied"})

    def test_top_twelve_partition_uses_one_traversal(self):
        root = self.home / "tree"
        root.mkdir()
        (root / "direct").write_bytes(b"123")
        for size in range(1, 17):
            child = root / f"child-{size:02}"
            child.mkdir()
            (child / "payload").write_bytes(b"x" * size)
        real_scandir = scanner.os.scandir
        enumerated = Counter()

        def counted_scandir(fd):
            info = os.fstat(fd)
            enumerated[(info.st_dev, info.st_ino)] += 1
            return real_scandir(fd)

        with patch.object(scanner.os, "scandir", side_effect=counted_scandir):
            result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "complete", 139, [])
        self.assertEqual(len(enumerated), 17)
        self.assertEqual(set(enumerated.values()), {1})
        breakdown = result["breakdown"]
        self.assertEqual([c["name"] for c in breakdown["children"]],
                         [f"child-{size:02}" for size in range(16, 4, -1)])
        self.assertEqual(breakdown["directBytes"], 3)
        self.assertEqual(breakdown["directFiles"], 1)
        self.assertEqual(breakdown["otherBytes"], 10)
        self.assertEqual(breakdown["otherCount"], 4)

    def test_interrupted_immediate_child_retains_partition_and_stop_location(self):
        root = self.home / "tree"
        child = root / "branch"
        child.mkdir(parents=True)
        for index in range(4):
            (child / str(index)).write_bytes(b"123")
        result = scanner.measure(str(root), scanner.Budget(scanner.Limits(path_entries=3)))
        self.assert_measurement(result, "partial", 3, ["limit"])
        self.assertEqual(result["breakdown"]["children"],
                         [{"name": "branch", "bytes": 3, "status": "partial", "issues": ["limit"]}])
        self.assertEqual(result["breakdown"]["otherCount"], 0)
        self.assertEqual(result["skippedCounts"], {"limit": 1})
        self.assertIn(result["skippedSamples"][0]["relative"], {f"branch/{i}" for i in range(4)})

    def test_permission_after_partial_enumeration_keeps_child_bytes(self):
        root = self.home / "tree"
        child = root / "branch"
        child.mkdir(parents=True)
        (child / "file").write_bytes(b"123456")
        child_inode = child.stat().st_ino
        real_scandir = scanner.os.scandir

        @contextmanager
        def interrupted_scandir(fd):
            with real_scandir(fd) as entries:
                if os.fstat(fd).st_ino == child_inode:
                    def interrupted_entries():
                        yield next(entries)
                        raise PermissionError(13, "Permission denied during enumeration")
                    yield interrupted_entries()
                else:
                    yield entries

        with patch.object(scanner.os, "scandir", side_effect=interrupted_scandir):
            result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "partial", 6, ["permission"])
        self.assertEqual(result["breakdown"]["children"],
                         [{"name": "branch", "bytes": 6, "status": "partial", "issues": ["permission"]}])
        self.assertEqual(result["skippedSamples"],
                         [{"relative": "branch", "reason": "permission", "truncated": False}])

    def test_breakdown_hardlinks_partition_without_marking_incomplete(self):
        root = self.home / "tree"
        (root / "one").mkdir(parents=True)
        (root / "two").mkdir()
        first = root / "one/file"
        first.write_bytes(b"1234567")
        os.link(first, root / "two/alias")
        os.link(first, root / "direct")
        result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "complete", 7, ["hardlink"])
        self.assertEqual(result["skippedCounts"], {"hardlink": 2})
        self.assertTrue(all(child["status"] == "complete" for child in result["breakdown"]["children"]))
        self.assertEqual(result["breakdown"]["directFiles"], 1)
        self.assertEqual(result["breakdown"]["otherCount"], 0)

    def test_skipped_samples_are_capped_and_long_relative_labels_are_explicit(self):
        root = self.home / "tree"
        name = "n" * 255
        nested = root / name / name / name
        nested.mkdir(parents=True)
        for index in range(12):
            (nested / str(index)).symlink_to(self.home / "nonexistent")
        result = scanner.measure(str(root), scanner.Budget())
        self.assert_measurement(result, "partial", 0, ["symlink"])
        self.assertEqual(result["skippedCounts"], {"symlink": 12})
        self.assertEqual(len(result["skippedSamples"]), 8)
        self.assertTrue(all(s["truncated"] and len(s["relative"]) == 512 for s in result["skippedSamples"]))
        self.assertEqual(result["breakdown"]["children"][0]["name"], name)

    def test_selected_app_preserves_global_ownership_but_measures_only_target(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        self.data("data", "shared/nested/file", b"1234")
        self.data("data", "a-only/file", b"123456")
        self.data("data", "b-only/file", b"12")
        rules = {"a": {"data": ["shared", "a-only"]},
                 "b": {"data": ["shared/nested", "b-only"]}}
        with patch.object(scanner, "measure", wraps=scanner.measure) as measured:
            apps, records = self.run_scan(rules, selected_id="b.desktop")
        self.assertEqual([app["id"] for app in apps], ["b.desktop"])
        self.assertEqual(apps[0]["mappedBytes"], 2)
        nested = next(item for item in apps[0]["paths"] if item["path"].endswith("/nested"))
        self.assertEqual(nested["confidence"], "shared")
        self.assertIn("not exclusive", nested["evidence"])
        self.assertEqual({call.args[0] for call in measured.call_args_list},
                         {str(Path(self.roots["data"]) / p) for p in ("shared/nested", "b-only")})
        self.assertTrue(all(record.get("id", "b.desktop") == "b.desktop" for record in records))

    def test_unknown_selected_app_never_falls_back_to_overview(self):
        self.desktop(self.user, "a.desktop", "A")
        self.data("config", "owned/file")
        stream = io.StringIO()
        with patch.object(scanner, "measure", wraps=scanner.measure) as measured:
            with self.assertRaisesRegex(scanner.UnknownApp, "Unknown selected application"):
                scanner.scan(self.env, stream, application_dirs=[str(self.user)],
                             rules={"a": {"config": ["owned"]}}, selected_id="missing.desktop")
        measured.assert_not_called()
        self.assertEqual(stream.getvalue(), "")

    def test_deep_scan_uses_larger_finite_budgets_and_reaches_deeper_payload(self):
        self.desktop(self.user, "a.desktop", "A")
        root = Path(self.roots["data"]) / "owned"
        leaf = root
        for _ in range(70):
            leaf /= "branch"
        leaf.mkdir(parents=True)
        (leaf / "file").write_bytes(b"123456789")
        rules = {"a": {"data": ["owned"]}}
        normal, normal_records = self.run_scan(rules)
        deep, deep_records = self.run_scan(rules, selected_id="a.desktop")
        self.assertEqual(normal[0]["paths"][0]["status"], "partial")
        self.assertEqual(normal[0]["mappedBytes"], 0)
        self.assertTrue(normal_records[-1]["limited"])
        self.assertEqual(deep[0]["paths"][0]["status"], "complete")
        self.assertEqual(deep[0]["mappedBytes"], 9)
        self.assertFalse(deep_records[-1]["limited"])
        self.assertEqual((scanner.DEEP_LIMITS.entries, scanner.DEEP_LIMITS.path_entries,
                          scanner.DEEP_LIMITS.seconds, scanner.DEEP_LIMITS.path_seconds,
                          scanner.DEEP_LIMITS.depth), (1000000, 500000, 90.0, 20.0, 96))

    def test_deeper_time_budget_retains_more_actual_bytes(self):
        root = self.home / "tree"
        root.mkdir()
        for index in range(5):
            (root / str(index)).write_bytes(b"12")
        tick = [0.0]
        real_stat = scanner.os.stat

        def slow_stat(*args, **kwargs):
            result = real_stat(*args, **kwargs)
            tick[0] += 1
            return result

        with patch.object(scanner.os, "stat", side_effect=slow_stat):
            normal = scanner.measure(str(root), scanner.Budget(clock=lambda: tick[0]))
            tick[0] = 0
            deep = scanner.measure(str(root), scanner.Budget(scanner.DEEP_LIMITS, clock=lambda: tick[0]))
        self.assert_measurement(normal, "partial", 4, ["limit"])
        self.assert_measurement(deep, "complete", 10, [])

    def test_known_path_results_stream_before_next_root_and_before_possible_roots(self):
        self.desktop(self.user, "a.desktop", "A")
        self.desktop(self.user, "b.desktop", "B")
        self.data("config", "owned-a/file")
        self.data("config", "owned-b/file")
        self.data("data", "A/file")
        self.data("data", "B/file")
        real_measure, real_emit = scanner.measure, scanner.emit
        records, observations = [], []

        def capture_emit(record, stream):
            records.append(copy.deepcopy(record))
            real_emit(record, stream)

        def observe_measure(path, *args, **kwargs):
            observations.append((path, sum(r["type"] == "path" for r in records)))
            self.assertEqual(sum(r["type"] == "app" for r in records), 2)
            return real_measure(path, *args, **kwargs)

        with patch.object(scanner, "emit", side_effect=capture_emit), \
                patch.object(scanner, "measure", side_effect=observe_measure):
            self.run_scan({"a": {"config": ["owned-a"]}, "b": {"config": ["owned-b"]}})
        self.assertEqual([count for _, count in observations], [0, 1, 2, 3])
        self.assertEqual([Path(path).name for path, _ in observations], ["owned-a", "owned-b", "A", "B"])

    def test_progress_is_throttled_and_reports_actual_root_measurements(self):
        self.desktop(self.user, "a.desktop", "A")
        for index in range(30):
            self.data("data", f"owned/{index}", b"12")
        tick, updates = [0.0], []
        real_stat, real_emit = scanner.os.stat, scanner.emit

        def ticking_stat(*args, **kwargs):
            result = real_stat(*args, **kwargs)
            tick[0] += 0.05
            return result

        def capture_emit(record, stream):
            if record["type"] == "progress":
                updates.append((tick[0], copy.deepcopy(record)))
            real_emit(record, stream)

        with patch.object(scanner.os, "stat", side_effect=ticking_stat), \
                patch.object(scanner, "emit", side_effect=capture_emit):
            apps, _ = self.run_scan({"a": {"data": ["owned"]}}, clock=lambda: tick[0])
        self.assertGreaterEqual(len(updates), 3)
        self.assertEqual((updates[0][1]["entries"], updates[0][1]["bytes"]), (0, 0))
        self.assertTrue(any(record["bytes"] > 0 for _, record in updates))
        for previous, current in zip(updates, updates[1:]):
            self.assertGreaterEqual(current[0] - previous[0], scanner.PROGRESS_INTERVAL - 1e-9)
            self.assertGreaterEqual(current[1]["entries"], previous[1]["entries"])
        for _, record in updates:
            self.assertEqual(record["bytes"], max(0, record["entries"] - 1) * 2)
            self.assertEqual(record["id"], "a.desktop")
            self.assertEqual(record["path"], apps[0]["paths"][0]["path"])
        self.assertEqual(apps[0]["mappedBytes"], 60)

    def test_inventory_clipping_is_bounded_and_remains_partial(self):
        self.desktop(self.user, "a.desktop", "A")
        prefix = "/".join(["n" * 200] * 5)
        paths = [prefix + "/" + str(index) for index in range(24)]
        for relative in paths:
            self.data("config", relative, b"12")
        assigned_path = self.data("data", "assigned", b"123")
        apps, records = self.run_scan({"a": {"config": paths}}, custom_mappings=[
            {"id": "a.desktop", "path": str(assigned_path), "category": "state"}])
        self.assertEqual(apps[0]["paths"][0]["path"], str(assigned_path))
        self.assertEqual(apps[0]["categories"]["state"], 3)
        self.assertLess(len(apps[0]["paths"]), 24)
        self.assertGreater(len(apps[0]["paths"]), 0)
        self.assertEqual(apps[0]["status"], "partial")
        self.assertTrue(all(item["status"] == "complete" for item in apps[0]["paths"]))
        self.assertTrue(records[-1]["limited"])
        for record in records:
            if record["type"] == "app":
                self.assertLessEqual(len(json.dumps(record, ensure_ascii=True, separators=(",", ":"))) + 1,
                                     scanner.MAX_APP_RECORD)

    def test_unicode_metadata_matches_consumer_text_bounds(self):
        self.desktop(self.user, "a.desktop", "\U0001f680" * 200, "Icon=" + "\U0001f680" * 200 + "\n")
        apps, _ = self.run_scan({})
        self.assertEqual(apps[0]["name"], "\U0001f680" * 128)
        self.assertEqual(apps[0]["icon"], "\U0001f680" * 128)

    def test_cli_modes_and_unknown_target_emit_v3_or_error_without_user_data(self):
        self.desktop(self.user, "a.desktop", "A")
        self.data("data", "owned/file", b"123")
        real_scan = scanner.scan

        def fixture_scan(**kwargs):
            return real_scan(self.env, application_dirs=[str(self.user)],
                             rules={"a": {"data": ["owned"]}}, **kwargs)

        for args, expected_mode, status in [
                (["scan"], "overview", 0),
                (["scan", "--app", "a.desktop"], "deep", 0),
                (["scan", "--app", "missing.desktop"], None, 2)]:
            with self.subTest(args=args):
                stream = io.StringIO()
                with patch.object(scanner.sys, "argv", ["scanner.py"] + args), \
                        patch.object(scanner.sys, "stdout", stream), \
                        patch.object(scanner, "scan", side_effect=fixture_scan), \
                        patch.object(scanner.signal, "signal"), \
                        patch.object(scanner.signal, "setitimer") as timer:
                    self.assertEqual(scanner.main(), status)
                records = [json.loads(line) for line in stream.getvalue().splitlines()]
                self.assertEqual(timer.call_args_list[0].args[0], scanner.signal.ITIMER_REAL)
                self.assertGreater(timer.call_args_list[0].args[1], 0)
                self.assertEqual(timer.call_args_list[-1].args, (scanner.signal.ITIMER_REAL, 0))
                if expected_mode:
                    self.assertEqual(records[0]["version"], 3)
                    self.assertEqual(records[0]["mode"], expected_mode)
                    self.assertEqual(records[-1]["type"], "done")
                    self.assertTrue(all(len(json.dumps(r, separators=(",", ":"))) + 1 <= scanner.MAX_LINE
                                        for r in records))
                else:
                    self.assertEqual(records, [{"type": "error", "message": "Unknown selected application ID"}])


if __name__ == "__main__":
    unittest.main()
