"""Stable release boundaries; all repositories, data and worker IPC are isolated."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic"
sys.path.insert(0, str(PROJECT))
import updates


def release(tag="v2.0.0", **changes):
    return {"id": 123, "draft": False, "prerelease": False, "tag_name": tag,
            "html_url": "https://github.com/naolselemon/mosaic/releases/tag/" + tag, **changes}


def manifest(version):
    return {"schemaVersion": 1, "id": updates.PLUGIN_ID, "name": "Mosaic", "version": version,
            "kinds": ["service"], "entryPoints": {"service": "Service.qml"}}


def git(path, *args):
    env = {"PATH": "/usr/bin:/bin", "HOME": str(path), "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_AUTHOR_NAME": "Fixture", "GIT_COMMITTER_NAME": "Fixture",
           "GIT_AUTHOR_EMAIL": "fixture@example.invalid", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
    return subprocess.check_output(["/usr/bin/git", "-c", "init.templateDir=", "-C", str(path), *args],
                                   stderr=subprocess.STDOUT, env=env, text=True).strip()


class MetadataTests(unittest.TestCase):
    def test_stable_identity_is_exact_and_bounded(self):
        self.assertEqual(updates.release_version(release()), "2.0.0")
        for changes in ({"draft": True}, {"prerelease": True}, {"id": True}, {"id": -1},
                        {"html_url": "https://evil.invalid/release"}, {"tag_name": "v2.0.0-rc.1"},
                        {"tag_name": "2.0.0\n"}, {"tag_name": "v02.0.0"}, {"tag_name": "v" + "1" * 100 + ".0.0"}):
            with self.subTest(changes=changes), self.assertRaises(updates.UpdateError):
                updates.release_version(release(**changes))
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{broken'):
            with self.assertRaises(updates.UpdateError):
                updates.decode(raw)

    def test_404_is_no_release_not_network_failure(self):
        opener = Mock()
        opener.open.side_effect = urllib.error.HTTPError(updates.LATEST_RELEASE, 404, "Not found", {}, None)
        with patch.object(updates.urllib.request, "build_opener", return_value=opener):
            self.assertIsNone(updates.latest_release())
        opener.open.side_effect = urllib.error.HTTPError(updates.LATEST_RELEASE, 403, "Limit", {}, None)
        with patch.object(updates.urllib.request, "build_opener", return_value=opener), self.assertRaises(updates.UpdateError) as caught:
            updates.latest_release()
        self.assertEqual(caught.exception.code, "rateLimited")

    def test_redirect_and_response_limits(self):
        with self.assertRaises(updates.UpdateError):
            updates.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid")
        for url, raw in (("https://evil.invalid", b"{}"), (updates.LATEST_RELEASE, b"x" * (updates.LIMIT + 1))):
            response = Mock(status=200)
            response.geturl.return_value = url
            response.read.return_value = raw
            response.__enter__ = Mock(return_value=response)
            response.__exit__ = Mock(return_value=False)
            opener = Mock()
            opener.open.return_value = response
            with patch.object(updates.urllib.request, "build_opener", return_value=opener), self.assertRaises(updates.UpdateError):
                updates.latest_release()

    def test_cli_accepts_no_source_provider_or_installed_overrides(self):
        for args in (["check", "--source", "/tmp/x"], ["check", "--repository", "https://evil.invalid"],
                     ["load", "--installed", "1.0.0"], ["install"], ["load", "--commit", "a" * 40], []):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = updates.main(args)
            self.assertEqual(code, 1)
            self.assertEqual(len(stdout.getvalue().splitlines()), 1)
            self.assertEqual(json.loads(stdout.getvalue())["error"], "arguments")


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.remote = self.home / "official"
        self.remote.mkdir()
        git(self.remote, "init", "--quiet")
        (self.remote / "manifest.json").write_text(json.dumps(manifest("1.0.0")))
        (self.remote / "Service.qml").write_text("// fixture: never executed\n")
        git(self.remote, "add", ".")
        git(self.remote, "commit", "-qm", "Initial")
        self.base = git(self.remote, "rev-parse", "HEAD")
        git(self.remote, "tag", "v1.0.0")
        self.source = self.home / ".config/omarchy/plugins" / updates.PLUGIN_ID
        self.source.parent.mkdir(parents=True)
        git(self.home, "clone", "--quiet", "--no-hardlinks", str(self.remote), str(self.source))
        (self.remote / "manifest.json").write_text(json.dumps(manifest("2.0.0")))
        git(self.remote, "add", ".")
        git(self.remote, "commit", "-qm", "Release")
        self.commit = git(self.remote, "rev-parse", "HEAD")
        git(self.remote, "tag", "v2.0.0")
        self.env = {"HOME": str(self.home), "XDG_STATE_HOME": str(self.home / "state"),
                    "XDG_CONFIG_HOME": str(self.home / "preferences")}
        self.commands = []
        self.launches = []
        self.now = 1000000
        self.active = "active"
        self.running = True
        self.latched = False
        self.fail_ready = False
        self.migrate = False
        self.config = {"bar": {"layout": {"left": ["other.plugin", updates.PLUGIN_ID]}},
                       "plugins": [updates.PLUGIN_ID, "other.plugin"], "disabledPlugins": []}
        self.updater = updates.Updater(env=self.env, source=self.source, installed_root=self.source,
                                       repository=str(self.remote), release_fetcher=lambda: release(),
                                       runner=self.runner, launcher=lambda *args: self.launches.append(args),
                                       clock=lambda: self.now)
        self.updater.runtime_environment = lambda: "/trusted/shell/shell.qml"
        self.updater.verify_activation = self.verify_activation

    def runner(self, argv, **kwargs):
        self.commands.append([str(arg) for arg in argv])
        name = Path(argv[0]).name
        if name == "git":
            return updates.run_command(argv, environment=self.env, **kwargs)
        if name == "omarchy-plugin-validate":
            self.assertTrue(Path(argv[1]).is_dir())
            return 0, ""
        if name == "systemctl":
            return 0, self.active
        if name == "omarchy-plugin-list":
            return 0, json.dumps([{"id": updates.PLUGIN_ID, "enabled": True}, {"id": "other.plugin", "enabled": True}])
        if name == "omarchy-shell":
            method = argv[2]
            if method == "listShellConfig":
                return 0, json.dumps(self.config)
            if method == "updateHealth":
                return 0, json.dumps({"id": updates.PLUGIN_ID, "version": self.updater.manifest(self.source)["version"],
                                      "ready": True, "busy": False, "quiesced": self.latched})
            if method == "beginUpdate":
                self.latched = True
                return 0, "true"
            if method == "endUpdate":
                self.latched = False
                return 0, ""
            if method == "status":
                return 0, '{"secure":false,"requested":false}'
        if name == "quickshell":
            if argv[1] == "list":
                return 0, json.dumps([{"id": "shell-fixture", "pid": 42, "config_path": "/trusted/shell/shell.qml"}] if self.running else [])
            if argv[1] == "kill":
                self.running = False
                return 0, ""
        if name == "omarchy-hyprland-session-locked":
            return 1, ""
        if name == "omarchy-restart-shell":
            self.running = True
            self.latched = False
            if self.migrate and self.updater.manifest(self.source)["version"] == "2.0.0":
                self.updater.profile.joinpath("history.json").write_text('{"newRecords":[1]}')
            return 0, ""
        raise AssertionError("Unexpected command: " + repr(argv))

    def verify_activation(self, activation, expected_version):
        self.assertEqual(self.updater.activation(), activation)
        if self.fail_ready and expected_version == "2.0.0":
            raise updates.UpdateError("runtime_readiness", "Fixture rejected new runtime")
        self.updater.health(expected_version, False)

    def prepare(self):
        result = self.updater.check()
        self.assertEqual(result["status"], "ready", result)
        self.assertTrue(result["supported"])
        self.assertEqual(result["commit"], self.commit)
        return self.updater.load()["prepared"]

    def approve(self):
        self.prepare()
        result = self.updater.install(self.commit)
        self.assertEqual(result["status"], "installing", result)
        return self.launches[-1][1]

    def test_load_has_no_network_or_state_writes(self):
        self.updater.release_fetcher = Mock(side_effect=AssertionError("network"))
        result = self.updater.result()
        self.assertEqual(result["status"], "idle")
        self.assertFalse(self.updater.root.exists())
        self.assertTrue(result["supported"])

    def test_prepare_is_private_pinned_and_does_not_replace_source(self):
        plan = self.prepare()
        self.assertEqual(self.updater.identity(), self.base)
        self.assertEqual(plan["installed"], self.base)
        self.assertEqual(plan["version"], "2.0.0")
        candidate = Path(plan["path"])
        self.assertEqual(candidate.parent, self.updater.root)
        self.assertEqual(candidate.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.updater.state_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.launches, [])

    def test_expanded_repeated_blobs_are_rejected_before_checkout(self):
        # Git stores one tiny compressed blob, but checkout would write it twice.
        for name in ("repeated-a", "repeated-b"):
            (self.remote / name).write_bytes(b"x" * 4096)
        git(self.remote, "add", ".")
        git(self.remote, "commit", "-qm", "Repeated expanded release content")
        git(self.remote, "tag", "-f", "v2.0.0")
        with patch.object(updates, "TREE_LIMIT", 6000):
            result = self.updater.check()
        self.assertEqual(result["error"], "size_limit", result)
        candidates = list(self.updater.root.glob("candidate-*"))
        self.assertEqual(len(candidates), 1)
        self.assertEqual({path.name for path in candidates[0].iterdir()}, {".git"})
        self.assertEqual(self.updater.identity(), self.base)
        self.assertEqual(self.launches, [])

    def test_aggregate_staging_cap_refuses_fetch_and_preserves_retained_edits(self):
        self.updater.private_root()
        retained = self.updater.root / ("candidate-" + "b" * 32)
        retained.mkdir(mode=0o700)
        record = retained / "local-records"
        record.write_bytes(b"retained user modifications")
        before = record.read_bytes()
        with patch.object(updates, "STAGING_LIMIT", updates.CANDIDATE_LIMIT - 1):
            result = self.updater.check()
        self.assertEqual(result["error"], "storage_limit", result)
        self.assertFalse(any("fetch" in command for command in self.commands))
        self.assertEqual(list(self.updater.root.glob("candidate-*")), [retained])
        self.assertEqual(record.read_bytes(), before)
        self.assertEqual(self.updater.identity(), self.base)

    def test_git_child_file_limit_bounds_materialization_writes(self):
        archive = self.home / "limited.tar"
        with patch.object(updates, "GIT_FILE_LIMIT", 4096), self.assertRaises(updates.UpdateError):
            updates.run_command(["/usr/bin/git", "-C", str(self.remote), "archive", "--output=" + str(archive), "HEAD"],
                                environment=self.env)
        self.assertTrue(archive.exists())
        self.assertLessEqual(archive.stat().st_size, 4096)

    def test_operation_write_monitor_refuses_growth_without_removing_data(self):
        self.updater.private_root()
        candidate = self.updater.root / ("candidate-" + "c" * 32)
        candidate.mkdir(mode=0o700)
        monitor = self.updater.storage_monitor(candidate)
        marker = candidate / "retained"
        marker.write_bytes(b"x" * 8192)
        with patch.object(updates, "OPERATION_WRITE_LIMIT", 4096), self.assertRaises(updates.UpdateError) as caught:
            monitor()
        self.assertEqual(caught.exception.code, "storage_limit")
        self.assertEqual(marker.read_bytes(), b"x" * 8192)

    def test_unsupported_non_git_copy_reports_metadata_without_downloading(self):
        shutil.rmtree(self.source / ".git")
        result = self.updater.check()
        self.assertFalse(result["supported"])
        self.assertEqual(result["latest"], "2.0.0")
        self.assertEqual(result["status"], "idle")
        self.assertEqual(result["commit"], "")
        self.assertFalse(any("fetch" in command for command in self.commands))
        self.assertEqual(self.updater.manifest(self.source)["version"], "1.0.0")

    def test_no_release_is_successful_even_for_local_preview(self):
        self.updater.source = self.remote
        self.updater.release_fetcher = lambda: None
        result = self.updater.check()
        self.assertEqual(result["status"], "noRelease")
        self.assertTrue(result["ok"])
        self.assertFalse(result["supported"])
        self.assertEqual(result["checkedAt"], self.now)

    def test_failed_and_interrupted_attempts_are_persisted_before_network(self):
        def failure():
            self.assertEqual(self.updater.load()["lastAttempt"], self.now)
            raise updates.UpdateError("network", "Offline")
        self.updater.release_fetcher = failure
        self.assertEqual(self.updater.check()["error"], "network")
        self.assertEqual(self.updater.result()["lastAttempt"], self.now)
        self.now += 100
        self.updater.release_fetcher = Mock(side_effect=KeyboardInterrupt)
        with self.assertRaises(KeyboardInterrupt):
            self.updater.check()
        self.assertEqual(self.updater.result()["error"], "interrupted")
        self.assertEqual(self.updater.result()["lastAttempt"], self.now)

    def test_dirty_ignored_assume_unchanged_and_configuration_attacks(self):
        target = self.source / "Service.qml"
        original = target.read_bytes()
        git(self.source, "update-index", "--assume-unchanged", "Service.qml")
        target.write_text("// malicious same tracked name\n")
        self.assertFalse(self.updater.support()[0])
        target.write_bytes(original)
        git(self.source, "update-index", "--no-assume-unchanged", "Service.qml")
        git(self.source, "config", "filter.evil.clean", "touch /never-run")
        self.assertFalse(self.updater.support()[0])
        git(self.source, "config", "--remove-section", "filter.evil")
        (self.source / ".git/objects/info/alternates").write_text("/tmp/elsewhere")
        self.assertFalse(self.updater.support()[0])
        (self.source / ".git/objects/info/alternates").unlink()
        (self.source / ".git/info").mkdir(exist_ok=True)
        (self.source / ".git/info/exclude").write_text("private-records\n")
        (self.source / "private-records").write_text("must survive")
        self.assertFalse(self.updater.support()[0])
        self.assertEqual((self.source / "private-records").read_text(), "must survive")

    def test_exact_approval_base_and_candidate_are_revalidated(self):
        plan = self.prepare()
        with self.assertRaises(updates.UpdateError):
            self.updater.install("a" * 40)
        Path(plan["path"]).joinpath("Service.qml").write_text("// modified candidate")
        with self.assertRaises(updates.UpdateError):
            self.updater.install(self.commit)
        self.assertEqual(self.launches, [])
        self.prepare()
        (self.source / "Service.qml").write_text("// modified installed source")
        with self.assertRaises(updates.UpdateError):
            self.updater.install(self.commit)
        self.assertEqual(self.updater.result()["status"], "error")
        self.assertEqual(self.launches, [])

    def test_divergent_history_and_tag_manifest_mismatch_are_refused(self):
        (self.source / "Service.qml").write_text("// local commit")
        git(self.source, "add", ".")
        git(self.source, "commit", "-qm", "Local divergence")
        result = self.updater.check()
        self.assertEqual(result["error"], "diverged", result)
        git(self.source, "checkout", "--quiet", "--detach", self.base)
        self.updater.release_fetcher = lambda: release("v1.0.0")
        self.assertEqual(self.updater.check()["status"], "current")
        git(self.remote, "tag", "v3.0.0")
        self.updater.release_fetcher = lambda: release("v3.0.0")
        self.assertEqual(self.updater.check()["error"], "release_invalid")

    def test_corrupt_or_linked_state_is_not_overwritten(self):
        self.prepare()
        self.updater.state_path.write_bytes(b"{corrupt")
        with self.assertRaises(updates.UpdateError):
            self.updater.check()
        self.assertEqual(self.updater.state_path.read_bytes(), b"{corrupt")
        self.updater.state_path.unlink()
        target = self.home / "unrelated"
        target.write_text("preserve")
        self.updater.state_path.symlink_to(target)
        with self.assertRaises(updates.UpdateError):
            self.updater.check()
        self.assertEqual(target.read_text(), "preserve")

    def test_worker_installs_and_retains_original_tree_and_only_owned_backups(self):
        token = self.approve()
        self.updater.private_directory(self.updater.config, True)
        self.updater.config.joinpath("settings.json").write_text('{"setting":true}')
        self.updater.config.joinpath("settings.json").chmod(0o600)
        self.updater.profile.joinpath("history.json").write_text('{"records":[1]}')
        self.updater.profile.joinpath("history.json").chmod(0o600)
        unrelated = self.home / "application-data"
        unrelated.mkdir()
        unrelated.joinpath("record").write_text("do not scan or copy")
        worker = self.launches[-1][0]
        self.assertEqual(worker.parent, self.updater.root)
        self.assertNotIn(self.source, worker.parents)
        self.assertEqual(worker.read_bytes(), Path(updates.__file__).read_bytes())
        result = self.updater.work(token)
        self.assertEqual(result["status"], "installed", result)
        self.assertEqual(self.updater.identity(), self.commit)
        state = self.updater.load()
        self.assertEqual(git(Path(state["rollbackSource"]), "rev-parse", "HEAD"), self.base)
        self.assertEqual({path.name for path in Path(state["backup"]).iterdir()},
                         {"settings.json", "history.json", "activation.json", "files.json"})
        self.assertEqual(unrelated.joinpath("record").read_text(), "do not scan or copy")
        self.assertEqual(self.config["bar"]["layout"]["left"], ["other.plugin", updates.PLUGIN_ID])

    def test_failed_readiness_rolls_back_code_only_when_data_unchanged(self):
        token = self.approve()
        self.fail_ready = True
        result = self.updater.work(token)
        self.assertEqual(result["status"], "recovery", result)
        self.assertEqual(self.updater.identity(), self.base)
        self.assertFalse(result["supported"])
        self.assertIn("Original code restored", result["message"])
        self.assertIn("omarchy-restart-shell", result["message"])
        self.assertTrue(Path(self.updater.load()["failedBackup"]).exists())
        with self.assertRaises(updates.UpdateError):
            self.updater.check()

    def test_new_records_prevent_code_rollback_and_are_never_restored(self):
        token = self.approve()
        self.updater.profile.joinpath("history.json").write_text('{"oldRecords":[1]}')
        self.updater.profile.joinpath("history.json").chmod(0o600)
        self.fail_ready = self.migrate = True
        result = self.updater.work(token)
        self.assertEqual(result["status"], "recovery", result)
        self.assertEqual(self.updater.identity(), self.commit)
        self.assertEqual(json.loads(self.updater.profile.joinpath("history.json").read_text()), {"newRecords": [1]})
        self.assertIn("Owned data changed", result["message"])
        self.assertTrue(self.running)

    def test_partial_recovery_quiescence_still_restarts_current_shell(self):
        token = self.approve()
        self.fail_ready = True
        previous = self.updater.raw_runner
        kills = 0
        def partial_stop(argv, **kwargs):
            nonlocal kills
            if Path(argv[0]).name == "quickshell" and argv[1] == "kill":
                kills += 1
                outcome = previous(argv, **kwargs)
                if kills == 2:
                    # Real quiesce attaches shell_stop_requested when its kill
                    # operation times out after stopping the shell.
                    raise updates.UpdateError("timeout", "Stop acknowledgement was lost")
                return outcome
            return previous(argv, **kwargs)
        self.updater.raw_runner = partial_stop
        result = self.updater.work(token)
        self.assertEqual(kills, 2)
        self.assertEqual(result["status"], "recovery", result)
        self.assertTrue(self.running)
        self.assertEqual(self.updater.identity(), self.commit)
        self.assertTrue(Path(self.updater.load()["rollbackSource"]).exists())
        self.assertEqual(sum(Path(command[0]).name == "omarchy-restart-shell" for command in self.commands), 2)

    def test_lost_worker_is_not_success_or_reusable_approval(self):
        self.approve()
        self.now += 31000
        self.active = "inactive"
        result = self.updater.result()
        self.assertEqual(result["status"], "recovery")
        self.assertNotIn("prepared", self.updater.load())
        self.assertEqual(self.updater.identity(), self.base)
        with self.assertRaises(updates.UpdateError):
            self.updater.install(self.commit)

    def test_guard_is_released_when_stop_is_refused(self):
        token = self.approve()
        self.updater.quiesce = Mock(side_effect=updates.UpdateError("session_locked", "Locked"))
        result = self.updater.work(token)
        self.assertEqual(result["status"], "error", result)
        self.assertFalse(self.latched)
        self.assertEqual(self.updater.identity(), self.base)

    def test_ambiguous_launch_requires_recovery_not_second_approval(self):
        self.prepare()
        self.updater.launcher = Mock(side_effect=updates.UpdateError("timeout", "Launch timed out"))
        self.assertEqual(self.updater.install(self.commit)["status"], "recovery")
        self.assertNotIn("prepared", self.updater.load())

    def test_private_worker_bootstrap_preserves_untrusted_installed_code(self):
        token = self.approve()
        worker = self.launches[-1][0]
        result = subprocess.run(["/usr/bin/python3", "-I", str(worker), "--worker", token],
                                env=self.updater.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 1)
        response = json.loads(result.stdout)
        # The copied worker reaches the installed checkout, but its production
        # trust rule refuses our local fixture origin before stopping any shell.
        self.assertEqual(response["error"], "identity")
        self.assertEqual(response["status"], "error")
        self.assertEqual(self.updater.identity(), self.base)
        self.assertNotIn("prepared", self.updater.load())
        self.assertFalse(list(self.updater.root.glob("backup-*")))

    def test_native_journal_lock_prevents_backup_exchange(self):
        self.updater.private_directory(self.updater.config, True)
        with self.updater.journal_lock():
            with self.assertRaises(updates.UpdateError):
                with self.updater.journal_lock():
                    self.fail("Second writer acquired the journal lock")


if __name__ == "__main__":
    unittest.main()
