import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
sys.path.insert(0, str(PROJECT))
import installations
import scanner


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.database = self.home / "pacman"
        (self.database / "local").mkdir(parents=True)
        self.user = self.home / "data/applications"
        self.system = self.home / "system/applications"
        self.user.mkdir(parents=True)
        self.system.mkdir(parents=True)
        self.env = {"HOME": str(self.home), "XDG_DATA_HOME": str(self.home / "data"), "PATH": ""}
        self.db_patch = patch.object(installations, "PACMAN_DB_PATH", str(self.database))
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)

    def desktop(self, directory, filename, extra=""):
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / filename
        path.write_text("[Desktop Entry]\nType=Application\nName=Fixture application\n" + extra)
        return path

    def package(self, name, paths, size, extra=""):
        directory = self.database / "local" / (name + "-1.0-1")
        directory.mkdir()
        size_field = "" if size is None else "%SIZE%\n" + str(size) + "\n\n"
        (directory / "desc").write_text("%NAME%\n" + name + "\n\n%VERSION%\n1.0-1\n\n" + size_field + extra)
        (directory / "files").write_text("%FILES%\n" + "\n".join(str(p).lstrip("/") for p in paths) + "\n\n%BACKUP%\n")
        return directory

    def discover(self):
        return scanner.discover([str(self.user), str(self.system)], scanner.Budget())

    def resolve(self, apps=None):
        return installations.resolve_installations(self.discover() if apps is None else apps, env=self.env)

    def assert_unknown(self, result, count=1):
        self.assertEqual(result["totalBytes"], 0)
        self.assertEqual(result["knownApps"], 0)
        self.assertEqual(result["unresolvedApps"], count)
        self.assertTrue(all(row["status"] == "unknown" and row["reason"] for row in result["apps"]))
        self.assertTrue(all(group["bytes"] is None for group in result["groups"]))

    def test_winning_user_override_does_not_borrow_system_package(self):
        system = self.desktop(self.system, "editor.desktop")
        self.package("editor", [system], 4000)
        self.desktop(self.user, "editor.desktop")
        result = self.resolve()
        self.assert_unknown(result)
        self.assertEqual(result["groups"], [])

    def test_user_symlink_to_owned_launcher_has_verified_provenance(self):
        system = self.desktop(self.system, "editor.desktop")
        self.package("editor", [system], 4000)
        (self.user / "editor.desktop").symlink_to(system)
        result = self.resolve()
        self.assertEqual(result["totalBytes"], 4000)
        self.assertEqual(result["apps"][0]["status"], "known")
        self.assertEqual(result["groups"][0]["appIds"], ["editor.desktop"])

    def test_package_grouping_counts_multiple_launchers_once_without_dependencies(self):
        first = self.desktop(self.system, "suite.desktop")
        second = self.desktop(self.system, "suite-writer.desktop")
        other = self.desktop(self.system, "viewer.desktop")
        self.package("suite", [first, second], 123456, "%DEPENDS%\nshared-lib\n\n")
        self.package("viewer", [other], 400, "%DEPENDS%\nshared-lib\n\n")
        self.package("shared-lib", [self.home / "lib/libshared.so"], 90000000)
        apps = self.discover()
        original = copy.deepcopy(apps)
        result = self.resolve(apps)
        self.assertEqual(apps, original)
        self.assertEqual(result["totalBytes"], 123856)
        self.assertEqual(result["knownApps"], 3)
        self.assertEqual(result["unresolvedApps"], 0)
        groups = {group["name"]: group for group in result["groups"]}
        self.assertEqual(set(groups), {"suite", "viewer"})
        self.assertEqual(groups["suite"]["appIds"], ["suite-writer.desktop", "suite.desktop"])
        rows = {row["id"]: row for row in result["apps"]}
        self.assertEqual(rows["suite.desktop"]["groupKey"], rows["suite-writer.desktop"]["groupKey"])
        self.assertEqual(rows["suite.desktop"]["status"], "shared")
        self.assertEqual(rows["suite-writer.desktop"]["status"], "shared")
        self.assertEqual(rows["viewer.desktop"]["status"], "known")
        self.assertNotEqual(rows["viewer.desktop"]["groupKey"], rows["suite.desktop"]["groupKey"])

    def test_missing_installed_size_is_unknown_not_zero(self):
        path = self.desktop(self.system, "editor.desktop")
        self.package("editor", [path], None)
        result = self.resolve()
        self.assert_unknown(result)
        self.assertEqual(result["groups"][0]["name"], "editor")
        self.assertIsNone(result["groups"][0]["bytes"])
        self.assertEqual(result["apps"][0]["groupKey"], result["groups"][0]["key"])

    def test_recorded_zero_is_distinct_from_missing_metadata(self):
        path = self.desktop(self.system, "empty.desktop")
        self.package("empty", [path], 0)
        result = self.resolve()
        self.assertEqual(result["groups"][0]["bytes"], 0)
        self.assertEqual(result["knownApps"], 1)
        self.assertEqual(result["unresolvedApps"], 0)

    def test_denied_package_metadata_does_not_become_zero(self):
        path = self.desktop(self.system, "editor.desktop")
        package = self.package("editor", [path], 3000)
        real_open = os.open

        def deny_files(path, flags, *args, **kwargs):
            if str(path) == str(package / "files"):
                raise PermissionError("fixture permission denied")
            return real_open(path, flags, *args, **kwargs)

        with patch.object(installations.os, "open", side_effect=deny_files):
            result = self.resolve()
        self.assert_unknown(result)
        self.assertTrue(result["issues"])

    def test_configured_pacman_database_and_root_are_used(self):
        root = self.home / "alternate-root"
        launcher = self.desktop(root / "usr/share/applications", "editor.desktop")
        package = self.package("editor", [], 7001)
        (package / "files").write_text("%FILES%\nusr/share/applications/editor.desktop\n")
        tools = self.home / "bin"
        tools.mkdir()
        command = tools / "pacman-conf"
        command.write_text(
            "#!" + sys.executable + "\nimport sys\n"
            "values = " + repr({"DBPath": str(self.database), "RootDir": str(root)}) + "\n"
            "print(values[sys.argv[1]])\n")
        command.chmod(0o700)
        self.env["PATH"] = str(tools)
        apps = scanner.discover([str(launcher.parent)], scanner.Budget())
        with patch.object(installations, "PACMAN_DB_PATH", str(self.home / "wrong-database")):
            result = self.resolve(apps)
        self.assertEqual(result["totalBytes"], 7001)
        self.assertEqual(result["knownApps"], 1)

    def test_missing_database_and_tool_preserve_unknown(self):
        self.desktop(self.system, "editor.desktop")
        with patch.object(installations, "PACMAN_DB_PATH", str(self.home / "absent")):
            result = self.resolve()
        self.assert_unknown(result)
        self.assertTrue(result["issues"])

    def test_missing_provenance_cannot_infer_ownership_from_id(self):
        path = self.desktop(self.system, "editor.desktop")
        self.package("editor", [path], 3000)
        apps = self.discover()
        del apps[0]["_desktopFile"]
        self.assert_unknown(self.resolve(apps))

    def test_changed_or_broken_winning_symlink_is_unknown(self):
        path = self.desktop(self.system, "editor.desktop")
        self.package("editor", [path], 3000)
        link = self.user / "editor.desktop"
        link.symlink_to(path)
        apps = self.discover()
        link.unlink()
        link.symlink_to(self.home / "missing.desktop")
        self.assert_unknown(self.resolve(apps))

    def test_busy_database_does_not_report_stale_package_sizes(self):
        path = self.desktop(self.system, "editor.desktop")
        self.package("editor", [path], 3000)
        (self.database / "db.lck").touch()
        result = self.resolve()
        self.assert_unknown(result)

    def test_conflicting_database_ownership_is_not_arbitrarily_chosen(self):
        path = self.desktop(self.system, "editor.desktop")
        self.package("first", [path], 3000)
        self.package("second", [path], 6000)
        result = self.resolve()
        self.assert_unknown(result)

    def test_oversized_metadata_is_bounded_and_unknown(self):
        path = self.desktop(self.system, "editor.desktop")
        package = self.package("editor", [path], 3000)
        (package / "files").write_text("%FILES%\n" + "x" * 2048)
        with patch.object(installations, "MAX_DATABASE", 1024):
            result = self.resolve()
        self.assert_unknown(result)

    def flatpak(self, app_id="org.example.Editor", branch="stable", launcher=None, size="1.5 MB"):
        base = self.home / "data/flatpak"
        deployment = base / "app" / app_id / "x86_64" / branch / ("a" * 64)
        deployment.mkdir(parents=True, exist_ok=True)
        (deployment / "metadata").write_text("[Application]\nname=" + app_id + "\nruntime=org.example.Platform/x86_64/24.08\n")
        filename = launcher or app_id + ".desktop"
        target = self.desktop(deployment / "export/share/applications", filename, "X-Flatpak=" + app_id + "\n")
        exports = base / "exports/share/applications"
        exports.mkdir(parents=True, exist_ok=True)
        link = exports / filename
        link.symlink_to(target)
        record = {"location": str(deployment), "size": size}
        return exports, deployment, "app/" + app_id + "/x86_64/" + branch, record

    def flatpak_tool(self, records, body=None):
        tools = self.home / "bin"
        tools.mkdir(exist_ok=True)
        fixture = self.home / "installed-flatpaks.json"
        fixture.write_text(json.dumps(records))
        script = ("#!" + sys.executable + "\nimport json, sys, time\n"
                  + (body if body is not None else
                     "records = json.load(open(" + repr(str(fixture)) + "))\n"
                     "if len(sys.argv) != 5 or sys.argv[1:3] != ['info', '--user']:\n    sys.exit(2)\n"
                     "record = records.get(sys.argv[4])\n"
                     "if record is None:\n    sys.exit(1)\n"
                     "field = {'--show-location': 'location', '--show-size': 'size'}.get(sys.argv[3])\n"
                     "if field is None:\n    sys.exit(2)\n"
                     "print(record[field])\n"))
        executable = tools / "flatpak"
        executable.write_text(script)
        executable.chmod(0o700)
        self.env["PATH"] = str(tools)

    def flatpak_apps(self, exports):
        return scanner.discover([str(exports)], scanner.Budget())

    def test_flatpak_exports_share_deployment_and_exclude_runtime(self):
        exports, deployment, ref, record = self.flatpak()
        self.flatpak(launcher="org.example.Editor.Settings.desktop")
        records = {ref: record, "runtime/org.example.Platform/x86_64/24.08":
                   {"location": str(self.home / "runtime"), "size": "9 GB"}}
        self.flatpak_tool(records)
        result = self.resolve(self.flatpak_apps(exports))
        self.assertEqual(result["totalBytes"], 1500000)
        self.assertEqual(result["knownApps"], 2)
        self.assertEqual(len(result["groups"]), 1)
        self.assertEqual(result["groups"][0]["kind"], "flatpak")
        self.assertTrue(all(row["status"] == "shared" for row in result["apps"]))

    def test_distinct_flatpak_branches_are_distinct_deployments(self):
        exports, _, stable_ref, stable = self.flatpak(size="12345")
        _, _, beta_ref, beta = self.flatpak(branch="beta", launcher="org.example.Editor.Beta.desktop", size="2 KiB")
        self.flatpak_tool({stable_ref: stable, beta_ref: beta})
        result = self.resolve(self.flatpak_apps(exports))
        self.assertEqual(len(result["groups"]), 2)
        self.assertEqual(len({row["groupKey"] for row in result["apps"]}), 2)
        self.assertEqual(result["totalBytes"], 12345 + 2048)
        self.assertTrue(all(row["status"] == "known" for row in result["apps"]))

    def test_flatpak_missing_tool_retains_unknown_group(self):
        exports, _, _, _ = self.flatpak()
        result = self.resolve(self.flatpak_apps(exports))
        self.assert_unknown(result)
        self.assertEqual(result["groups"][0]["kind"], "flatpak")

    def test_flatpak_missing_metadata_does_not_guess_from_export_name(self):
        exports, deployment, ref, record = self.flatpak()
        (deployment / "metadata").unlink()
        self.flatpak_tool({ref: record})
        self.assert_unknown(self.resolve(self.flatpak_apps(exports)))

    def test_custom_flatpak_launcher_is_not_an_export(self):
        self.desktop(self.user, "org.example.Editor.desktop", "X-Flatpak=org.example.Editor\n")
        _, _, ref, record = self.flatpak()
        self.flatpak_tool({ref: record})
        result = self.resolve()
        self.assert_unknown(result)

    def test_flatpak_wrong_deployment_from_tool_is_unknown(self):
        exports, _, ref, record = self.flatpak()
        record["location"] = str(self.home)
        self.flatpak_tool({ref: record})
        self.assert_unknown(self.resolve(self.flatpak_apps(exports)))

    def test_flatpak_unreadable_size_is_unknown_not_zero(self):
        exports, _, ref, record = self.flatpak(size="unknown")
        self.flatpak_tool({ref: record})
        result = self.resolve(self.flatpak_apps(exports))
        self.assert_unknown(result)

    def test_flatpak_output_limit_terminates_lookup(self):
        exports, _, _, _ = self.flatpak()
        self.flatpak_tool({}, body="print('x' * 70000)\n")
        result = self.resolve(self.flatpak_apps(exports))
        self.assert_unknown(result)

    def test_flatpak_timeout_is_explicit_unknown(self):
        exports, _, _, _ = self.flatpak()
        self.flatpak_tool({}, body="time.sleep(5)\n")
        with patch.object(installations, "COMMAND_SECONDS", 0.05):
            result = self.resolve(self.flatpak_apps(exports))
        self.assert_unknown(result)

    def test_empty_inventory_is_not_an_unavailable_package(self):
        result = self.resolve([])
        self.assertEqual(result["groups"], [])
        self.assertEqual(result["apps"], [])
        self.assertEqual(result["issues"], [])
        self.assertEqual(result["knownApps"], 0)
        self.assertEqual(result["unresolvedApps"], 0)
        self.assertEqual(result["totalBytes"], 0)


if __name__ == "__main__":
    unittest.main()
