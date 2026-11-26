"""Approval-bound stable releases and a standalone, systemd-owned installer.

No plugin imports: the private worker survives replacement of the source tree.
Preparation executes only system Git and the installed Omarchy schema validator.
Settings/history are snapshotted, never restored over newer user records.
"""
import argparse
from contextlib import contextmanager
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

PLUGIN_ID = "naolselemon.mosaic"
REPOSITORY = "https://github.com/naolselemon/mosaic.git"
LATEST_RELEASE = "https://api.github.com/repos/naolselemon/mosaic/releases/latest"
SOURCE_ROOT = Path(__file__).absolute().parent.parent
COMMAND_ROOT = Path("/usr/share/omarchy/bin")
LIMIT = 1024 * 1024
TREE_LIMIT = 128 * 1024 * 1024
GIT_FILE_LIMIT = 64 * 1024 * 1024
OPERATION_WRITE_LIMIT = 128 * 1024 * 1024
CANDIDATE_LIMIT = 256 * 1024 * 1024
STAGING_LIMIT = 1024 * 1024 * 1024
FREE_SPACE_RESERVE = 64 * 1024 * 1024
SHA = re.compile(r"[0-9a-f]{40}\Z")
TOKEN = re.compile(r"[0-9a-f]{32}\Z")
VERSION = re.compile(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
STATUSES = {"idle", "noRelease", "current", "ahead", "ready", "installing", "installed", "error", "recovery"}
ENV_KEYS = ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
            "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS", "OMARCHY_PATH")


class UpdateError(ValueError):
    def __init__(self, code, message=None):
        super().__init__(message or code)
        self.code = code


def fail(code, message):
    raise UpdateError(code, message)


def bounded(value, maximum=1024):
    # Bound escaped JSON too so two diagnostics fit one response line.
    result, used = [], 0
    for character in str(value)[:maximum]:
        character = character if ord(character) >= 32 and ord(character) != 127 else " "
        cost = len(json.dumps(character, ensure_ascii=True)) - 2
        if used + cost > maximum:
            break
        result.append(character)
        used += cost
    return "".join(result)


def safe_path(value):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts or len(str(path)) > 4096:
        fail("unsafe_path", "Updater paths must be absolute without parent traversal.")
    for part in (path, *path.parents):
        if part.is_symlink():
            fail("unsafe_path", "Updater paths must not contain symbolic links.")
        if part.exists():
            info = part.stat()
            if info.st_uid not in (0, os.getuid()) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
                fail("unsafe_path", "Updater path ancestors must not be writable by other users.")
    return path


def private_file(path):
    safe_path(path)
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_mode & 0o077:
        fail("state", "Updater state must be a private, unlinked regular file.")


def decode(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                fail("invalid_json", "Duplicate JSON field.")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: fail("invalid_json", "Nonfinite JSON number."))
    except (ValueError, UnicodeError, RecursionError) as error:
        if isinstance(error, UpdateError):
            raise
        fail("invalid_json", "Invalid JSON data.")


def read_json(path, maximum=LIMIT, private=False):
    safe_path(path)
    if private:
        private_file(path)
    with open(path, "rb") as stream:
        raw = stream.read(maximum + 1)
    if len(raw) > maximum:
        fail("size_limit", "JSON data exceeds its size limit.")
    return decode(raw)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_json(path, value):
    safe_path(path)
    if path.exists():
        private_file(path)
    raw = json.dumps(value, ensure_ascii=True, allow_nan=False).encode() + b"\n"
    if len(raw) > LIMIT:
        fail("size_limit", "Updater state exceeds its size limit.")
    fd, temporary = tempfile.mkstemp(prefix=".state-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run_command(argv, timeout=90, allowed=(0,), environment=None, monitor=None):
    # A minimal environment also excludes BASH_ENV, LD_PRELOAD, Git config,
    # credential helpers, proxies, Python imports and shell function injections.
    source = os.environ if environment is None else environment
    env = {key: source[key] for key in ENV_KEYS if key in source}
    env.update(PATH=str(COMMAND_ROOT) + ":/usr/bin:/bin", LC_ALL="C", PYTHONDONTWRITEBYTECODE="1",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_SYSTEM="/dev/null", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_TERMINAL_PROMPT="0", GIT_CONFIG_COUNT="0", GIT_ASKPASS="/bin/false", SSH_ASKPASS="/bin/false")
    env.setdefault("OMARCHY_PATH", str(COMMAND_ROOT.parent))
    def child_limits():
        # Inherited by upload-pack/index-pack and other Git children. A single
        # compressed pack cannot consume the filesystem between monitor ticks.
        resource.setrlimit(resource.RLIMIT_FSIZE, (GIT_FILE_LIMIT, GIT_FILE_LIMIT))
    with tempfile.TemporaryDirectory(prefix="mosaic-git-") as home, tempfile.TemporaryFile() as output:
        if Path(str(argv[0])).name == "git":
            env.update(HOME=home, XDG_CONFIG_HOME=home, GIT_OPTIONAL_LOCKS="0", GIT_ATTR_NOSYSTEM="1")
        if monitor is not None:
            monitor()
        process = subprocess.Popen([str(arg) for arg in argv], stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT, env=env, start_new_session=True,
                                   preexec_fn=child_limits if Path(str(argv[0])).name == "git" else None)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    fail("timeout", "An updater command timed out.")
                if os.fstat(output.fileno()).st_size > LIMIT:
                    fail("output_limit", "An updater command exceeded its output limit.")
                if monitor is not None:
                    monitor()
                time.sleep(0.025)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        if monitor is not None:
            monitor()
        output.seek(0)
        raw = output.read(LIMIT + 1)
    if len(raw) > LIMIT:
        fail("output_limit", "An updater command exceeded its output limit.")
    text = raw.decode("utf-8", errors="replace").rstrip("\n")
    if process.returncode not in allowed:
        fail("command_failed", "Updater command failed: " + Path(str(argv[0])).name + ": " + bounded(text[-600:]))
    return process.returncode, text


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        fail("release_identity", "The fixed release endpoint unexpectedly redirected.")


def latest_release():
    request = urllib.request.Request(LATEST_RELEASE, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "Mosaic-release-updater",
        "Accept-Encoding": "identity", "X-GitHub-Api-Version": "2022-11-28"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=20) as response:
            if response.geturl() != LATEST_RELEASE or response.status != 200:
                fail("release_identity", "Unexpected stable release response origin.")
            raw = response.read(LIMIT + 1)
        if len(raw) > LIMIT:
            fail("release_invalid", "The release response exceeds its size limit.")
        return decode(raw)
    except urllib.error.HTTPError as error:
        error.close()
        if error.code == 404:
            return None
        fail("rateLimited" if error.code in (403, 429) else "network", "Could not retrieve the stable GitHub release.")
    except UpdateError:
        raise
    except (OSError, ValueError) as error:
        fail("timeout" if isinstance(error, TimeoutError) else "network", "Could not retrieve the stable GitHub release.")


def version(value):
    if not isinstance(value, str) or len(value) > 64 or not VERSION.fullmatch(value):
        fail("version", "A stable semantic version is required.")
    return tuple(int(part) for part in value.removeprefix("v").split("."))


def release_version(release):
    if (not isinstance(release, dict) or release.get("draft") is not False or release.get("prerelease") is not False
            or type(release.get("id")) is not int or not 0 < release["id"] < 2 ** 53):
        fail("release_invalid", "GitHub did not declare a stable latest release.")
    tag = release.get("tag_name")
    version(tag)
    if release.get("html_url") != "https://github.com/naolselemon/mosaic/releases/tag/" + tag:
        fail("release_identity", "The release does not belong to the fixed Mosaic repository.")
    return tag.removeprefix("v")


def exchange(left, right):
    libc = ctypes.CDLL(None, use_errno=True)
    operation = getattr(libc, "renameat2", None)
    if operation is None:
        fail("unsupported", "Atomic directory exchange is unavailable.")
    if operation(-100, os.fsencode(left), -100, os.fsencode(right), 2) != 0:
        fail("exchange_failed", "Atomic code exchange failed: " + os.strerror(ctypes.get_errno()))
    try:
        sync_directory(left.parent)
        if right.parent != left.parent:
            sync_directory(right.parent)
    except OSError as cause:
        error = UpdateError("exchange_durability", "Code exchanged but directory durability could not be confirmed.")
        error.exchanged = True
        raise error from cause


class Updater:
    def __init__(self, *, env=None, source=None, installed_root=None, repository=REPOSITORY,
                 release_fetcher=None, runner=None, launcher=None, exchanger=None,
                 clock=None, monotonic=None, sleeper=None):
        # Dependency injection is Python-only. Production CLI has no path/provider switches.
        self.env = dict(os.environ if env is None else env)
        self.home = safe_path(self.env.get("HOME", ""))
        def xdg(key, fallback):
            value = self.env.get(key, "")
            return safe_path(value if value.startswith("/") else self.home / fallback)
        self.config = xdg("XDG_CONFIG_HOME", ".config") / "omarchy/mosaic"
        self.profile = xdg("XDG_STATE_HOME", ".local/state") / "omarchy/mosaic"
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.config.parent.parent),
                        XDG_STATE_HOME=str(self.profile.parent.parent))
        self.root = self.profile / "updater"
        self.state_path = self.root / "state.json"
        self.source = safe_path(source if source is not None else SOURCE_ROOT)
        # Omarchy's actual PluginRegistry uses HOME, not XDG_CONFIG_HOME.
        self.installed_root = safe_path(installed_root if installed_root is not None
                                        else self.home / ".config/omarchy/plugins" / PLUGIN_ID)
        self.adjacent = self.installed_root.parent.parent / ".mosaic-updater-staging"
        self.repository = repository
        self.release_fetcher = release_fetcher or latest_release
        self.raw_runner = runner or (lambda argv, **kwargs: run_command(argv, environment=self.env, **kwargs))
        self.runner = self.run_bounded
        self.deadline = None
        self.launcher = launcher or self.launch_worker
        self.exchanger = exchanger or exchange
        self.clock = clock or (lambda: max(1, int(time.time() * 1000)))
        self.monotonic = monotonic or time.monotonic
        self.sleep = sleeper or time.sleep

    def run_bounded(self, argv, timeout=90, **kwargs):
        if self.deadline is not None:
            remaining = self.deadline - self.monotonic()
            if remaining <= 0:
                fail("timeout", "The release preparation deadline was exceeded.")
            timeout = min(timeout, remaining)
        return self.raw_runner(argv, timeout=timeout, **kwargs)

    @contextmanager
    def time_limit(self, seconds):
        previous = self.deadline
        self.deadline = self.monotonic() + seconds
        try:
            yield
        finally:
            self.deadline = previous

    def private_directory(self, path, create=False):
        safe_path(path)
        if create:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        if path.exists():
            info = path.stat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                fail("state", "Updater directories must be private (0700) and owned by this user.")

    def private_root(self):
        if self.source == self.root or self.source in self.root.parents or self.root in self.source.parents:
            fail("unsafe_path", "Updater state must live outside the plugin source.")
        self.private_directory(self.profile, True)
        self.private_directory(self.root, True)

    @contextmanager
    def locked(self, wait=False):
        self.private_root()
        path = self.root / "lock"
        if path.exists():
            private_file(path)
        fd = os.open(safe_path(path), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            deadline = self.monotonic() + (20 if wait else 0)
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if self.monotonic() >= deadline:
                        fail("busy", "Another updater operation is in progress.")
                    self.sleep(0.05)
            yield
        finally:
            os.close(fd)

    def load(self):
        self.private_directory(self.profile)
        self.private_directory(self.root)
        safe_path(self.state_path)
        if not self.state_path.exists():
            return {}
        state = read_json(self.state_path, private=True)
        if not isinstance(state, dict) or state.get("format") != 1 or state.get("status") not in STATUSES:
            fail("state", "Unsupported updater state; existing data was not overwritten.")
        for key in ("checkedAt", "lastAttempt", "workerStartedAt"):
            if type(state.get(key, 0)) is not int or not 0 <= state.get(key, 0) < 2 ** 53:
                fail("state", "Invalid updater timestamp.")
        for key in ("latest", "commit", "error", "message"):
            if not isinstance(state.get(key, ""), str) or len(state.get(key, "")) > 4096:
                fail("state", "Invalid updater field.")
        if state.get("latest"):
            version(state["latest"])
            if state["latest"].startswith("v"):
                fail("state", "Recorded release versions must be normalized.")
        if state.get("commit") and not SHA.fullmatch(state["commit"]):
            fail("state", "Invalid recorded release identity.")
        return state

    def save(self, state):
        state["format"] = 1
        state["message"] = bounded(state.get("message", ""), 4096)
        atomic_json(self.state_path, state)

    def git(self, path, *args, allowed=(0,), local=False):
        monitor = self.storage_monitor(path) if path.parent in (self.root, self.adjacent) and path.name.startswith("candidate-") else None
        return self.runner(["/usr/bin/git", "--no-replace-objects", "-c", "core.hooksPath=/dev/null",
                            "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                            "-c", "credential.helper=", "-c", "http.followRedirects=false",
                            "-c", "http.extraHeader=", "-c", "http.proxy=", "-c", "core.attributesFile=/dev/null",
                            "-c", "init.templateDir=", "-c", "fetch.fsckObjects=true", "-c", "transfer.fsckObjects=true",
                            "-c", "fetch.unpackLimit=1", "-c", "transfer.unpackLimit=1",
                            "-c", "gc.auto=0", "-c", "maintenance.auto=false",
                            "-c", "protocol.allow=never", "-c", "protocol.https.allow=always",
                            "-c", "protocol.file.allow=" + ("always" if local else "never"),
                            "-C", str(path), *args], allowed=allowed, monitor=monitor)

    def command(self, name, *args, timeout=90):
        return self.runner([str(COMMAND_ROOT / name), *args], timeout=timeout)[1]

    def manifest(self, path):
        manifest = read_json(path / "manifest.json", 64 * 1024)
        if not isinstance(manifest, dict) or manifest.get("id") != PLUGIN_ID:
            fail("identity", "The manifest does not identify Mosaic.")
        version(manifest.get("version"))
        if manifest["version"].startswith("v"):
            fail("identity", "Manifest versions must be stable x.y.z values, without a tag prefix.")
        return manifest

    def audit_git(self, path):
        gitdir = safe_path(path / ".git")
        if not gitdir.is_dir():
            fail("unsupported", "The installed plugin must be a standalone Git checkout; this copy has no .git directory.")
        # Refuse linked objects, alternates, replacement history and config which
        # could invoke a filter, URL rewrite, include, helper or custom transport.
        count = 0
        for directory, dirs, files in os.walk(gitdir, followlinks=False):
            for name in dirs + files:
                item = Path(directory) / name
                info = item.lstat()
                count += 1
                if count > 100000 or info.st_uid != os.getuid() or info.st_mode & 0o022:
                    fail("untrusted_git", "Git storage is untrusted or exceeds its safety limit.")
                if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)) or (stat.S_ISREG(info.st_mode) and info.st_nlink != 1):
                    fail("untrusted_git", "Linked or special Git storage is unsupported.")
        for relative in ("objects/info/alternates", "objects/info/http-alternates", "info/grafts", "refs/replace", "shallow", "config.worktree"):
            if (gitdir / relative).exists():
                fail("untrusted_git", "Alternate, shallow or replaced Git history is unsupported.")
        _, config = self.git(path, "config", "--file", str(gitdir / "config"), "--no-includes", "--null", "--list")
        allowed = {"core.repositoryformatversion", "core.filemode", "core.bare", "core.logallrefupdates",
                   "core.ignorecase", "core.precomposeunicode", "remote.origin.url", "remote.origin.fetch"}
        for item in config.split("\0"):
            if not item:
                continue
            key, _, value = item.partition("\n")
            if key not in allowed and not re.fullmatch(r"branch\.[^\n]+\.(remote|merge)", key):
                fail("untrusted_git", "The checkout contains unsupported Git configuration: " + bounded(key, 100))
            if key == "core.repositoryformatversion" and value != "0":
                fail("untrusted_git", "Unsupported Git repository format.")
            if key == "core.bare" and value != "false":
                fail("untrusted_git", "A working-tree checkout is required.")
        origins = self.git(path, "config", "--get-all", "remote.origin.url", allowed=(0, 1))[1].splitlines()
        if origins != [self.repository]:
            fail("identity", "The checkout origin is not the fixed official Mosaic repository.")
        if self.git(path, "rev-parse", "--show-toplevel")[1] != str(path):
            fail("identity", "The plugin is not the root of its checkout.")

    def committed_tree(self, path, commit):
        # -l reports expanded blob sizes before checkout. Count every reference,
        # not distinct object IDs: a tiny compressed blob can appear 10,000 times.
        _, tree = self.git(path, "ls-tree", "-rlz", "--full-tree", commit)
        expected = {}
        expanded = 0
        for entry in tree.split("\0"):
            if not entry:
                continue
            header, separator, name = entry.partition("\t")
            fields = header.split()
            if not separator or len(fields) != 4 or fields[0] not in ("100644", "100755") or fields[1] != "blob" or not fields[3].isdigit():
                fail("untrusted_tree", "Plugins must contain regular files, not links or submodules.")
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts or ".git" in relative.parts:
                fail("untrusted_tree", "Unsafe plugin tree path.")
            size = int(fields[3])
            expanded += size
            if size > GIT_FILE_LIMIT or expanded > TREE_LIMIT:
                fail("size_limit", "The expanded plugin tree exceeds its safe materialization limit.")
            expected[name] = (fields[0], fields[2])
        if not expected or len(expected) > 10000:
            fail("size_limit", "Plugin tree exceeds its file limit.")
        return expected

    def tree_identity(self, path, commit):
        # Never trust assume-unchanged/skip-worktree flags or index mtime caches.
        expected = self.committed_tree(path, commit)
        seen, total, entries = set(), 0, 0
        for directory, dirs, files in os.walk(path, followlinks=False):
            if Path(directory) == path:
                dirs[:] = [name for name in dirs if name != ".git"]
            entries += len(dirs) + len(files)
            if entries > 20000:
                fail("size_limit", "Plugin tree exceeds its directory-entry limit.")
            for name in dirs:
                info = (Path(directory) / name).lstat()
                if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
                    fail("dirty_source", "Plugin directories are linked or untrusted.")
            for name in files:
                item = Path(directory) / name
                relative = item.relative_to(path).as_posix()
                info = item.lstat()
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_mode & 0o022:
                    fail("dirty_source", "Plugin files are linked, special or writable by other users.")
                if relative not in expected:
                    fail("dirty_source", "The plugin contains local files; none will be discarded.")
                total += info.st_size
                if total > TREE_LIMIT:
                    fail("size_limit", "Plugin tree exceeds its byte limit.")
                digest = hashlib.sha1(("blob " + str(info.st_size) + "\0").encode())
                size = 0
                with open(item, "rb") as stream:
                    while block := stream.read(65536):
                        size += len(block)
                        if size > info.st_size:
                            fail("dirty_source", "A plugin file grew during validation.")
                        digest.update(block)
                mode, object_id = expected[relative]
                if digest.hexdigest() != object_id or bool(info.st_mode & 0o111) != (mode == "100755"):
                    fail("dirty_source", "The plugin contains modified files; none will be overwritten.")
                seen.add(relative)
        if seen != set(expected) or self.git(path, "diff", "--cached", "--name-only", commit)[1]:
            fail("dirty_source", "The plugin has deleted files or staged changes.")

    def identity(self):
        safe_path(self.source)
        if self.source != self.installed_root:
            fail("unsupported", "Automatic installation is available only in the installed Mosaic Git checkout, not this local checkout.")
        self.audit_git(self.source)
        commit = self.git(self.source, "rev-parse", "HEAD")[1]
        if not SHA.fullmatch(commit):
            fail("identity", "The installed commit is not a full Git SHA-1 identity.")
        self.tree_identity(self.source, commit)
        self.manifest(self.source)
        return commit

    def support(self):
        try:
            self.identity()
            return True, ""
        except (UpdateError, OSError) as error:
            return False, bounded(error)

    def reconcile(self, state):
        if state.get("status") != "installing" or self.clock() - state.get("workerStartedAt", 0) < 30000:
            return state
        token = state.get("token", "")
        if not isinstance(token, str) or not TOKEN.fullmatch(token):
            fail("state", "Invalid recorded worker identity.")
        try:
            _, active = self.runner(["/usr/bin/systemctl", "--user", "show", "mosaic-update-" + token + ".service",
                                     "--property=ActiveState", "--value"], timeout=5, allowed=(0, 1, 4))
        except (UpdateError, OSError):
            return state  # An unavailable manager is not evidence of worker death.
        if active in ("active", "activating", "reloading"):
            return state
        try:
            with self.locked():
                current = self.load()
                if current.get("token") != token or current.get("status") != "installing":
                    return current
                self.recovery(current, "The approved worker was interrupted; installation, data and activation are unverified.")
                self.save(current)
                return current
        except UpdateError as error:
            if error.code == "busy":
                return state
            raise

    def result(self, state=None):
        state = self.reconcile(self.load()) if state is None else state
        supported, reason = self.support()
        status = state.get("status", "idle")
        if status == "ready" and not supported:
            status = "error"
        if status == "recovery":
            supported, reason = False, state.get("message", "Manual recovery is required.")
        # A wall-clock correction must not suppress the next consented daily check.
        future = state.get("lastAttempt", 0) > self.clock()
        return {"ok": status not in ("error", "recovery"), "status": status,
                "latest": state.get("latest", ""), "commit": state.get("commit", ""),
                "checkedAt": 0 if future else state.get("checkedAt", 0),
                "lastAttempt": 0 if future else state.get("lastAttempt", 0),
                "error": "unsupported" if state.get("status") == "ready" and not supported else bounded(state.get("error", ""), 64),
                "message": bounded(state.get("message", ""), 4096),
                "supported": supported, "reason": bounded(reason, 4096)}

    def staging_root(self):
        root = self.root if self.root.stat().st_dev == self.source.stat().st_dev else self.adjacent
        # Outside PluginRegistry's top-level plugins directory, even before validation.
        self.private_directory(root, True)
        return root

    @staticmethod
    def storage_usage(roots, maximum):
        total = entries = 0
        for root in roots:
            safe_path(root)
            if not root.exists():
                continue
            for directory, dirs, files in os.walk(root, followlinks=False):
                for name in dirs + files:
                    try:
                        info = (Path(directory) / name).lstat()
                    except FileNotFoundError:
                        continue  # Git atomically renames temporary pack/index files.
                    entries += 1
                    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                        fail("storage_limit", "Private staging contains linked or special entries; no retained data was removed.")
                    total += max(info.st_size, info.st_blocks * 512)
                    if entries > 100000 or total > maximum:
                        fail("storage_limit", "Private updater storage reached its safety limit. Retained trees and backups were not removed.")
        return total

    def storage_monitor(self, candidate):
        baseline = self.storage_usage((candidate,), CANDIDATE_LIMIT)
        def monitor():
            used = self.storage_usage((candidate,), CANDIDATE_LIMIT)
            if used - baseline > OPERATION_WRITE_LIMIT:
                fail("storage_limit", "A Git operation exceeded its private staging write budget.")
            self.storage_usage((self.root, self.adjacent), STAGING_LIMIT)
            if shutil.disk_usage(candidate.parent).free < FREE_SPACE_RESERVE:
                fail("storage_limit", "Private staging reached the filesystem free-space reserve.")
        return monitor

    def reserve_staging(self, root):
        used = self.storage_usage((self.root, self.adjacent), STAGING_LIMIT)
        if used + CANDIDATE_LIMIT > STAGING_LIMIT:
            fail("storage_limit", "Insufficient updater staging budget for another candidate. Existing trees and backups were retained unchanged.")
        if shutil.disk_usage(root).free < CANDIDATE_LIMIT + FREE_SPACE_RESERVE:
            fail("storage_limit", "Insufficient free space to prepare a release safely.")

    def candidate_path(self, value):
        if not isinstance(value, str):
            fail("state", "Invalid candidate path.")
        candidate = safe_path(value)
        if candidate.parent not in (self.root, self.adjacent) or not re.fullmatch(r"candidate-[0-9a-f]{32}", candidate.name):
            fail("state", "The candidate is outside private updater staging.")
        self.private_directory(candidate.parent)
        self.private_directory(candidate)
        return candidate

    def validate_candidate(self, candidate, commit, expected_version):
        self.audit_git(candidate)
        if self.git(candidate, "rev-parse", "HEAD")[1] != commit:
            fail("candidate_changed", "The prepared tree no longer matches the approved commit.")
        self.tree_identity(candidate, commit)
        if self.manifest(candidate)["version"].removeprefix("v") != expected_version:
            fail("release_invalid", "The release tag and candidate manifest version disagree.")
        # This fixed, installed validator only reads the candidate; no candidate code runs.
        self.command("omarchy-plugin-validate", str(candidate))

    def check(self):
        with self.locked(), self.time_limit(300):
            state = self.load()
            if state.get("status") in ("installing", "recovery"):
                fail("recovery_required" if state["status"] == "recovery" else "busy", "The current installation must be resolved before checking again.")
            # Never delete old candidates: they may contain edits or retained failed code.
            state.pop("prepared", None)
            state.update(lastAttempt=self.clock(), status="error", error="interrupted",
                         message="The release check did not finish.", commit="")
            self.save(state)  # Attempts survive interruption, including network failures.
            try:
                release = self.release_fetcher()
                if release is None:
                    state.update(status="noRelease", latest="", commit="", checkedAt=self.clock(), error="",
                                 message="The official repository has no published stable release.")
                    self.save(state)
                    return self.result(state)
                latest = release_version(release)
                state.update(latest=latest, checkedAt=self.clock(), error="")
                supported, reason = self.support()
                installed_version = self.manifest(self.source)["version"]
                order = (version(installed_version) > version(latest)) - (version(installed_version) < version(latest))
                if not supported:
                    state.update(status="ahead" if order > 0 else "current" if order == 0 else "idle",
                                 message="Stable release metadata checked; code was not downloaded. " + reason)
                    self.save(state)
                    return self.result(state)
                installed = self.identity()
                if order >= 0:
                    state.update(status="ahead" if order > 0 else "current",
                                 message="Installed version is newer than the latest stable release." if order > 0 else "Installed version matches the latest stable release.")
                    self.save(state)
                    return self.result(state)
                staging = self.staging_root()
                self.reserve_staging(staging)
                candidate = staging / ("candidate-" + uuid.uuid4().hex)
                candidate.mkdir(mode=0o700)
                self.git(candidate, "init", "--quiet")
                self.git(candidate, "remote", "add", "origin", self.repository)
                self.git(candidate, "fetch", "--quiet", "--no-tags", "origin",
                         "refs/tags/" + release["tag_name"] + ":refs/tags/" + release["tag_name"],
                         local=self.repository != REPOSITORY)
                commit = self.git(candidate, "rev-parse", "refs/tags/" + release["tag_name"] + "^{commit}")[1]
                if not SHA.fullmatch(commit):
                    fail("release_invalid", "The release tag did not resolve to a full commit.")
                # Import only the inspected installed base; the source is never mutated.
                if self.identity() != installed:
                    fail("approval_stale", "Installed code changed during preparation.")
                self.git(candidate, "fetch", "--quiet", "--no-tags", "--upload-pack=/usr/bin/git-upload-pack",
                         str(self.source), "HEAD", local=True)
                self.committed_tree(candidate, commit)
                self.git(candidate, "checkout", "--quiet", "--detach", commit)
                self.validate_candidate(candidate, commit, latest)
                if self.git(candidate, "merge-base", "--is-ancestor", installed, commit, allowed=(0, 1))[0] != 0:
                    fail("diverged", "Installed code is not an ancestor of the stable release; replacement was refused.")
                if self.identity() != installed:
                    fail("approval_stale", "Installed code changed during preparation.")
                state.update(status="ready", commit=commit, message="Stable release prepared and validated. Installing requires approval of this exact commit and a whole-shell restart.",
                             prepared={"path": str(candidate), "commit": commit, "version": latest,
                                       "installed": installed, "installedVersion": installed_version})
                self.save(state)
                return self.result(state)
            except Exception as error:
                state.update(status="error", error=getattr(error, "code", "updater"), message=bounded(error), commit="")
                state.pop("prepared", None)
                self.save(state)
                return self.result(state)

    def prepared(self, state, commit):
        plan = state.get("prepared")
        if (not isinstance(plan, dict) or not isinstance(commit, str) or not SHA.fullmatch(commit)
                or plan.get("commit") != commit or state.get("commit") != commit
                or not isinstance(plan.get("installed"), str) or not SHA.fullmatch(plan["installed"])):
            fail("approval_stale", "Approval no longer matches a prepared release; check and approve again.")
        candidate = self.candidate_path(plan.get("path"))
        if self.identity() != plan["installed"]:
            fail("approval_stale", "The installed base changed after preparation.")
        if version(plan["version"]) <= version(self.manifest(self.source)["version"]):
            fail("downgrade", "The approved release is not newer than installed code.")
        self.validate_candidate(candidate, commit, plan["version"])
        if self.git(candidate, "merge-base", "--is-ancestor", plan["installed"], commit, allowed=(0, 1))[0] != 0:
            fail("diverged", "The approved release does not descend from the installed base.")
        return candidate

    def runtime_environment(self):
        _, text = self.runner(["/usr/bin/systemctl", "--user", "show-environment"], timeout=5)
        manager = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        # Restart-shell uses the manager's OMARCHY_PATH; use that same identity for IPC.
        for key in ENV_KEYS:
            if key in manager:
                value = manager[key]
                if len(value) > 4096 or any(ord(c) < 32 for c in value):
                    fail("environment", "The session environment is malformed.")
                if key in ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME") and self.env.get(key, value) != value:
                    fail("environment", "The shell session and updater disagree about owned data locations.")
                self.env[key] = value
        for key in ENV_KEYS:
            value = self.env.get(key, "")
            if not isinstance(value, str) or len(value) > 4096 or any(ord(c) < 32 or ord(c) == 127 for c in value):
                fail("environment", "An updater runtime environment value is malformed.")
        root = safe_path(self.env.get("OMARCHY_PATH", str(COMMAND_ROOT.parent)))
        configuration = root / "shell/shell.qml"
        if not configuration.is_file():
            fail("quiescence", "The actual session shell configuration was not found.")
        self.env["OMARCHY_PATH"] = str(root)
        return str(configuration.resolve())

    def install(self, commit):
        if not isinstance(commit, str) or not SHA.fullmatch(commit):
            fail("approval_required", "Installation requires approval of the full prepared commit.")
        with self.locked():
            state = self.load()
            if state.get("status") != "ready":
                fail("approval_stale", "There is no prepared release awaiting approval.")
            self.prepared(state, commit)
            configuration = self.runtime_environment()
            token = uuid.uuid4().hex
            worker = self.root / ("worker-" + token + ".py")
            with open(__file__, "rb") as source, open(worker, "xb") as target:
                os.chmod(worker, 0o600)
                shutil.copyfileobj(source, target)
                target.flush()
                os.fsync(target.fileno())
            state.update(status="installing", token=token, source=str(self.source), configuration=configuration,
                         environment={key: self.env[key] for key in ENV_KEYS if key in self.env},
                         installedBase=state["prepared"]["installed"], installedVersion=state["prepared"]["installedVersion"],
                         workerStartedAt=self.clock(), boundary="approved", error="",
                         message="Approved update is installing in an independent systemd worker.")
            self.save(state)
            try:
                self.launcher(worker, token)
            except Exception as error:
                # A timed-out systemd-run may already have launched the service;
                # never restore a reusable approval after an ambiguous launch.
                self.recovery(state, "Worker launch could not be confirmed: " + bounded(error))
                self.save(state)
                return self.result(state)
            return self.result(state)

    def launch_worker(self, worker, token):
        environment = ["--setenv=" + key + "=" + value for key, value in self.env.items() if key in ENV_KEYS]
        self.runner(["/usr/bin/systemd-run", "--user", "--quiet", "--collect", "--unit=mosaic-update-" + token,
                     "--property=Type=exec", "--property=RuntimeMaxSec=600", "--property=TimeoutStopSec=5",
                     "--property=UMask=0077", *environment, "--", "/usr/bin/python3", "-I", str(worker),
                     "--worker", token], timeout=15)

    def activation(self):
        config = decode(self.command("omarchy-shell", "shell", "listShellConfig", timeout=5))
        plugins = decode(self.command("omarchy-plugin-list", "--json", timeout=5))
        if not isinstance(config, dict) or not isinstance(plugins, list) or len(plugins) > 4096:
            fail("activation", "The shell did not report its activation state.")
        enabled = {}
        for entry in plugins:
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or type(entry.get("enabled")) is not bool or entry["id"] in enabled:
                fail("activation", "The shell reported ambiguous plugin activation.")
            enabled[entry["id"]] = entry["enabled"]
        if PLUGIN_ID not in enabled:
            fail("activation", "The shell did not discover Mosaic.")
        # Preserve the whole effective layout/services/disabled set, not just Mosaic;
        # unrelated plugins must not silently be disabled or displaced either.
        return {"layout": config.get("bar", {}).get("layout", {}), "plugins": config.get("plugins", []),
                "disabledPlugins": config.get("disabledPlugins", []), "enabled": enabled,
                "config": config}

    def health(self, expected_version=None, quiesced=None):
        value = decode(self.command("omarchy-shell", PLUGIN_ID, "updateHealth", timeout=5))
        if (not isinstance(value, dict) or value.get("id") != PLUGIN_ID or value.get("ready") is not True
                or type(value.get("busy")) is not bool or type(value.get("quiesced")) is not bool
                or (expected_version is not None and value.get("version") != expected_version)
                or (quiesced is not None and value.get("quiesced") is not quiesced)):
            fail("runtime_readiness", "Mosaic did not report the expected ready runtime generation.")
        return value

    def begin_update(self, expected_version):
        health = self.health(expected_version, False)
        if health["busy"]:
            fail("busy", "Wait for Mosaic scanning and workspace operations to finish before installing.")
        if decode(self.command("omarchy-shell", PLUGIN_ID, "beginUpdate", timeout=5)) is not True:
            fail("busy", "Mosaic could not quiesce its workers; no code was replaced.")
        if self.health(expected_version, True)["busy"]:
            fail("busy", "Mosaic still has active workers; no code was replaced.")

    def shell_instances(self, configuration):
        _, text = self.runner(["/usr/bin/quickshell", "list", "-a", "-j"], timeout=5)
        instances = [] if text.strip() == "No running instances." else decode(text)
        if not isinstance(instances, list):
            fail("quiescence", "Quickshell did not report its instances.")
        for item in instances:
            if (not isinstance(item, dict) or not isinstance(item.get("id"), str) or not item["id"]
                    or type(item.get("pid")) is not int or item["pid"] <= 0 or item.get("config_path") != configuration):
                fail("quiescence", "Close other or unidentified Quickshell instances before updating; they will not be stopped automatically.")
        if len(instances) > 1:
            fail("quiescence", "Multiple desktop shell instances are running.")
        return instances

    def require_quiescent(self, configuration):
        if self.shell_instances(configuration):
            fail("quiescence", "The shell is still running; code cannot be exchanged.")

    def quiesce(self, configuration):
        instances = self.shell_instances(configuration)
        if not instances:
            return
        locked, _ = self.runner([str(COMMAND_ROOT / "omarchy-hyprland-session-locked")], timeout=5, allowed=(0, 1, 2))
        lock = decode(self.command("omarchy-shell", "lock", "status", timeout=5))
        if locked != 1 or not isinstance(lock, dict) or lock.get("secure") is not False or lock.get("requested") is not False:
            fail("session_locked", "The session is locked or a lock is pending; its shell was not stopped.")
        if self.shell_instances(configuration) != instances:
            fail("quiescence", "The desktop shell changed during restart preparation.")
        try:
            self.runner(["/usr/bin/quickshell", "kill", "--id", instances[0]["id"]], timeout=30)
            deadline = self.monotonic() + 30
            while self.shell_instances(configuration):
                if self.monotonic() >= deadline:
                    fail("quiescence", "The shell did not stop before the deadline.")
                self.sleep(0.1)
        except Exception as error:
            error.shell_stop_requested = True
            raise

    def verify_activation(self, activation, expected_version):
        if self.activation() != activation:
            fail("activation", "Plugin activation, configuration or exact placement changed after restart.")
        deadline = self.monotonic() + 45
        while True:
            try:
                self.health(expected_version, False)
                break
            except (UpdateError, OSError):
                if self.monotonic() >= deadline:
                    fail("runtime_readiness", "Mosaic did not become ready at the expected version after restart.")
                self.sleep(0.25)
        if self.activation() != activation:
            fail("activation", "Plugin activation changed while waiting for Mosaic readiness.")

    @contextmanager
    def journal_lock(self):
        # journal.transaction uses this same configuration-directory lock.
        # Holding it excludes external workspace CLI writes at exchange.
        self.private_directory(self.config, True)
        path = self.config / ".lock"
        if path.exists():
            private_file(path)
        fd = os.open(safe_path(path), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail("busy", "A Mosaic journal operation is still active.")
            yield
        finally:
            os.close(fd)

    def snapshot(self, destination, activation):
        destination.mkdir(mode=0o700)
        fingerprints = {}
        for name, source, maximum in (("settings.json", self.config / "settings.json", LIMIT),
                                      ("history.json", self.profile / "history.json", 2 * LIMIT)):
            safe_path(source)
            if not source.exists():
                fingerprints[name] = None
                continue
            private_file(source)
            with open(source, "rb") as stream:
                raw = stream.read(maximum + 1)
            if len(raw) > maximum:
                fail("backup", "An owned Mosaic file exceeds its size limit.")
            decode(raw)
            with open(destination / name, "xb") as stream:
                os.chmod(destination / name, 0o600)
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            fingerprints[name] = hashlib.sha256(raw).hexdigest()
        atomic_json(destination / "activation.json", activation)
        atomic_json(destination / "files.json", fingerprints)
        sync_directory(destination)
        return fingerprints

    def recovery(self, state, message):
        state.update(status="recovery", error="recovery_required", recoveryRequired=True,
                     message=bounded(message, 2400) + " Both code trees and available private snapshots are retained; data was not restored or deleted. Inspect "
                     + str(self.root) + ". To restart the current code only: /usr/share/omarchy/bin/omarchy-restart-shell. Resolve recovery before another installation.")
        state.pop("prepared", None)
        state.pop("token", None)

    def work(self, token):
        with self.locked(wait=True):
            state = self.load()
            if state.get("status") != "installing" or state.get("token") != token:
                fail("approval_stale", "This worker no longer owns the approved installation.")
            swapped = stopped = latched = False
            candidate = activation = None
            configuration = state.get("configuration")
            plan = dict(state.get("prepared", {}))
            backup = self.root / ("backup-" + token)
            try:
                candidate = self.prepared(state, state["commit"])
                if candidate.stat().st_dev != self.source.stat().st_dev:
                    fail("unsupported", "Staging and installed code are not on the same filesystem.")
                if self.runtime_environment() != configuration:
                    fail("quiescence", "The session shell identity changed after approval.")
                activation = self.activation()
                latched = True  # A timed-out beginUpdate may still have latched.
                self.begin_update(plan["installedVersion"])
                if self.activation() != activation:
                    fail("activation", "Shell configuration changed during preparation.")
                state.update(boundary="before_stop", activation=activation, backup=str(backup), rollbackSource=str(candidate))
                self.save(state)
                try:
                    self.quiesce(configuration)
                except Exception as error:
                    stopped = bool(getattr(error, "shell_stop_requested", False))
                    raise
                stopped = True
                with self.journal_lock():
                    self.require_quiescent(configuration)
                    fingerprints = self.snapshot(backup, activation)
                    state.update(boundary="quiescent", fingerprints=fingerprints)
                    self.save(state)
                    self.prepared(state, state["commit"])
                    self.require_quiescent(configuration)
                    # Write-ahead boundary: death during rename is always recovery,
                    # never guessed as successful or retried on old approval.
                    state["boundary"] = "exchange_pending"
                    self.save(state)
                    try:
                        self.exchanger(self.source, candidate)
                    except Exception as error:
                        swapped = bool(getattr(error, "exchanged", False))
                        raise
                    swapped = True
                    state["boundary"] = "after_exchange"
                    self.save(state)
                self.command("omarchy-restart-shell", timeout=180)
                stopped = False
                self.verify_activation(activation, plan["version"])
                if self.identity() != state["commit"]:
                    fail("install_failed", "The installed tree differs from the approved release.")
                state.update(status="installed", boundary="complete", error="",
                             message="Stable release installed. Exact commit, Mosaic readiness and unchanged shell activation verified.")
                state.pop("prepared", None)
                state.pop("token", None)
                self.save(state)
            except Exception as error:
                message = "Update failed: " + bounded(error)
                if swapped:
                    try:
                        # No old-code restart against changed new-generation data.
                        self.quiesce(configuration)
                        stopped = True
                        with self.journal_lock():
                            self.require_quiescent(configuration)
                            failed = self.root / ("failed-backup-" + token)
                            observed = self.snapshot(failed, activation)
                            state["failedBackup"] = str(failed)
                            self.save(state)
                            if observed == state.get("fingerprints"):
                                self.audit_git(candidate)
                                self.tree_identity(candidate, plan["installed"])
                                if self.git(candidate, "rev-parse", "HEAD")[1] != plan["installed"]:
                                    fail("rollback", "The retained original tree has changed; no rollback was attempted.")
                                # Also preserve post-swap edits to the new tree in place.
                                if self.identity() != state["commit"]:
                                    fail("rollback", "Installed code changed after exchange; no rollback was attempted.")
                                self.require_quiescent(configuration)
                                self.exchanger(self.source, candidate)
                                state["boundary"] = "rolled_back"
                                self.save(state)
                                restored = True
                            else:
                                restored = False
                                message += " Owned data changed, so old code was not restored."
                        self.command("omarchy-restart-shell", timeout=180)
                        stopped = False
                        if restored:
                            if self.identity() != plan["installed"]:
                                fail("rollback", "Restored original commit could not be verified.")
                            self.verify_activation(activation, plan["installedVersion"])
                            message += " Original code restored only after confirming unchanged data; original readiness and activation verified."
                    except Exception as recovery_error:
                        stopped = stopped or bool(getattr(recovery_error, "shell_stop_requested", False))
                        message += " Recovery incomplete: " + bounded(recovery_error)
                        if stopped:
                            try:
                                self.command("omarchy-restart-shell", timeout=180)
                                stopped = False
                            except Exception as restart_error:
                                message += " Current shell restart failed: " + bounded(restart_error)
                    self.recovery(state, message)
                else:
                    if stopped:
                        try:
                            self.command("omarchy-restart-shell", timeout=180)
                            stopped = False
                            self.verify_activation(activation, plan["installedVersion"])
                        except Exception as restart_error:
                            self.recovery(state, message + " Original shell restart failed: " + bounded(restart_error))
                    elif latched:
                        try:
                            self.command("omarchy-shell", PLUGIN_ID, "endUpdate", timeout=5)
                            self.health(plan["installedVersion"], False)
                        except Exception as end_error:
                            self.recovery(state, message + " Update guard release could not be verified: " + bounded(end_error))
                    if state.get("status") != "recovery":
                        state.update(status="error", error=getattr(error, "code", "install_failed"),
                                     message=message + " No code or data was replaced.")
                        state.pop("prepared", None)
                        state.pop("token", None)
                self.save(state)
            return self.result(state)


def error_result(error):
    return {"ok": False, "status": "error", "latest": "", "commit": "", "checkedAt": 0, "lastAttempt": 0,
            "error": bounded(getattr(error, "code", "updater"), 64), "message": bounded(error, 4096),
            "supported": False, "reason": bounded(error, 4096)}


def run(command, commit=None, env=None, **injections):
    updater = None
    try:
        updater = Updater(env=env, **injections)
        if command == "load":
            return updater.result()
        if command == "check":
            return updater.check()
        if command == "install":
            return updater.install(commit)
        fail("operation", "Unknown updater operation.")
    except Exception as error:
        value = error_result(error)
        if updater is not None:
            try:
                current = updater.result()
                if current["status"] in ("installing", "recovery"):
                    return current
                value.update({key: current[key] for key in ("latest", "commit", "checkedAt", "lastAttempt", "supported", "reason")})
            except Exception:
                pass
        return value


class JsonArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        fail("arguments", "Use load, check, or install --commit FULL_SHA.")


def main(argv=None):
    parser = JsonArgumentParser(description=__doc__, add_help=False)
    parser.add_argument("command", nargs="?", choices=("load", "check", "install"))
    parser.add_argument("--commit")
    parser.add_argument("--worker", help=argparse.SUPPRESS)
    try:
        args = parser.parse_args(argv)
        if args.worker:
            if args.command or args.commit or not TOKEN.fullmatch(args.worker):
                fail("arguments", "Invalid private worker invocation.")
            updater = Updater()
            state = updater.load()
            worker = updater.root / ("worker-" + args.worker + ".py")
            private_file(worker)
            if Path(__file__).absolute() != worker or state.get("token") != args.worker or state.get("source") != str(updater.installed_root):
                fail("approval_stale", "Worker path or source does not match the private approval.")
            updater.source = updater.installed_root
            if state.get("environment") != {key: updater.env[key] for key in ENV_KEYS if key in updater.env}:
                fail("environment", "Worker environment differs from its approved session.")
            value = updater.work(args.worker)
        else:
            if not args.command or (args.command == "install") != (args.commit is not None):
                fail("arguments", "Use load, check, or install --commit FULL_SHA.")
            value = run(args.command, args.commit)
    except Exception as error:
        value = error_result(error)
    print(json.dumps(value, ensure_ascii=True, separators=(",", ":"), allow_nan=False))
    return 0 if value["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
