"""Read-only installed-package attribution for winning desktop launchers.

Pacman sizes are exact local %SIZE% metadata, not filesystem usage. Flatpak
sizes are tool-reported (possibly rounded); runtimes and dependencies are never
added. Neither total attempts to estimate shared on-disk extents.
"""
import configparser
from decimal import Decimal, InvalidOperation
import hashlib
import os
from pathlib import Path
import re
import selectors
import shutil
import stat
import subprocess
import time

from scanner import bounded_text, locations

PACMAN_DB_PATH = "/var/lib/pacman"
MAX_APPS = 512
MAX_OUTPUT = 65536
MAX_METADATA = 4 * 1024 * 1024
MAX_DATABASE = 64 * 1024 * 1024
MAX_PACKAGES = 10000
MAX_BYTES = (1 << 53) - 1
TOTAL_SECONDS = 8
COMMAND_SECONDS = 2


class Unavailable(Exception):
    pass


def _text(value, limit=1024):
    return bounded_text(str(value), limit)


def _identity(kind, *parts):
    digest = hashlib.sha256("\0".join(parts).encode("utf-8", "surrogatepass")).hexdigest()
    return kind + ":" + digest


def _read(path, maximum=MAX_METADATA):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise Unavailable("Installed metadata is not a regular file.")
            data = stream.read(maximum + 1)
        if len(data) > maximum:
            raise Unavailable("Installed metadata exceeds the read limit.")
        return data.decode("utf-8", "strict")
    except (OSError, UnicodeError) as exc:
        raise Unavailable("Installed metadata is missing, unreadable or invalid.") from exc


def _command(args, env, deadline):
    remaining = min(COMMAND_SECONDS, deadline - time.monotonic())
    if remaining <= 0:
        raise Unavailable("Installation lookup time limit reached.")
    executable = shutil.which(args[0], path=env.get("PATH", os.defpath))
    if executable is None:
        raise Unavailable(args[0] + " is unavailable.")
    child_env = dict(env, LC_ALL="C", LANG="C")
    try:
        process = subprocess.Popen([executable] + args[1:], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                   env=child_env)
    except OSError as exc:
        raise Unavailable(args[0] + " cannot be executed.") from exc
    data = bytearray()
    until = time.monotonic() + remaining
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = until - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise Unavailable(args[0] + " lookup timed out.")
                chunk = os.read(process.stdout.fileno(), min(8192, MAX_OUTPUT + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > MAX_OUTPUT:
                    raise Unavailable(args[0] + " output exceeds the read limit.")
        try:
            status = process.wait(timeout=max(0.001, until - time.monotonic()))
        except subprocess.TimeoutExpired as exc:
            raise Unavailable(args[0] + " lookup timed out.") from exc
        if status != 0:
            raise Unavailable(args[0] + " could not read installed metadata.")
        try:
            return data.decode("utf-8", "strict").strip()
        except UnicodeError as exc:
            raise Unavailable(args[0] + " returned invalid metadata.") from exc
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def _fields(text):
    fields, key = {}, None
    for line in text.splitlines():
        if line.startswith("%") and line.endswith("%"):
            key = line
            if key in fields:
                raise Unavailable("Installed package metadata has duplicate fields.")
            fields[key] = []
        elif key is not None and line:
            fields[key].append(line)
    return fields


def _single(fields, key):
    values = fields.get(key, [])
    return values[0] if len(values) == 1 else ""


def _pacman(targets, env, deadline):
    """Index exact owned filenames once, without inspecting dependency packages."""
    database, root = PACMAN_DB_PATH, "/"
    if shutil.which("pacman-conf", path=env.get("PATH", os.defpath)):
        database = _command(["pacman-conf", "DBPath"], env, deadline)
        root = _command(["pacman-conf", "RootDir"], env, deadline)
    if not os.path.isabs(database) or not os.path.isabs(root) or "\n" in database + root:
        raise Unavailable("Pacman database configuration is unsupported.")
    local = os.path.join(database, "local")
    if os.path.lexists(os.path.join(database, "db.lck")):
        raise Unavailable("Pacman is updating its installed database; retry later.")
    ownership, read_bytes = {}, 0
    try:
        with os.scandir(local) as entries:
            packages = []
            for entry in entries:
                if entry.name == "ALPM_DB_VERSION":
                    continue
                if not entry.is_dir(follow_symlinks=False):
                    raise Unavailable("Pacman installed database contains unsupported entries.")
                packages.append(entry.path)
                if len(packages) > MAX_PACKAGES:
                    raise Unavailable("Pacman installed database exceeds the package limit.")
        for directory in sorted(packages):
            if time.monotonic() >= deadline:
                raise Unavailable("Installation lookup time limit reached.")
            file_text = _read(os.path.join(directory, "files"))
            read_bytes += len(file_text.encode("utf-8"))
            if read_bytes > MAX_DATABASE:
                raise Unavailable("Pacman installed database exceeds the read limit.")
            matched = set()
            for filename in _fields(file_text).get("%FILES%", []):
                # Pacman filenames are root-relative. Reject malformed metadata,
                # rather than normalizing traversal into a spurious owner.
                if filename.startswith("/") or ".." in filename.split("/"):
                    raise Unavailable("Pacman installed filenames are invalid.")
                path = os.path.join(root, filename)
                if path in targets:
                    matched.add(path)
            if not matched:
                continue
            fields = _fields(_read(os.path.join(directory, "desc"), MAX_OUTPUT))
            name, version = _single(fields, "%NAME%"), _single(fields, "%VERSION%")
            if not re.fullmatch(r"[A-Za-z0-9@_+.-]{1,256}", name) or not version or len(version) > 256:
                raise Unavailable("Installed package identity is invalid.")
            raw_size = _single(fields, "%SIZE%")
            size = int(raw_size) if re.fullmatch(r"[0-9]{1,16}", raw_size) else None
            if size is not None and not 0 <= size <= MAX_BYTES:
                size = None
            group = {"key": _identity("pacman", os.path.realpath(database), root, name, version),
                     "name": name, "kind": "pacman", "bytes": size,
                     "status": "known" if size is not None else "unknown", "appIds": [],
                     "reason": ("Exact installed size from pacman local %SIZE% metadata; dependencies excluded."
                                if size is not None else "Package ownership is known, but installed-size metadata is unavailable.")}
            for path in matched:
                if path in ownership:
                    raise Unavailable("Multiple installed packages claim the same desktop file.")
                ownership[path] = group
        if os.path.lexists(os.path.join(database, "db.lck")):
            raise Unavailable("Pacman is updating its installed database; retry later.")
    except OSError as exc:
        raise Unavailable("Pacman installed database is unavailable or unreadable.") from exc
    return ownership


def _flatpak_provenance(path, resolved, flatpak_id, env):
    roots, _ = locations(env)
    candidates = [(os.path.join(roots["data"], "flatpak"), "--user"),
                  ("/var/lib/flatpak", "--system")]
    for installation, scope in candidates:
        exported = os.path.join(installation, "exports", "share", "applications") + os.sep
        if not path.startswith(exported):
            continue
        base = os.path.realpath(installation)
        relative = os.path.relpath(resolved, base).split(os.sep)
        if (len(relative) < 9 or relative[0] != "app" or relative[1] != flatpak_id
                or relative[5:8] != ["export", "share", "applications"]
                or not all(re.fullmatch(r"[A-Za-z0-9_.-]+", part) for part in relative[2:5])):
            raise Unavailable("Flatpak export does not resolve to the declared installed application.")
        deployment = os.path.join(base, *relative[:5])
        metadata = configparser.ConfigParser(interpolation=None, strict=True)
        try:
            metadata.read_string(_read(os.path.join(deployment, "metadata"), MAX_OUTPUT))
            if metadata.get("Application", "name", fallback="") != flatpak_id:
                raise Unavailable("Flatpak deployment metadata does not match its desktop export.")
        except configparser.Error as exc:
            raise Unavailable("Flatpak deployment metadata is invalid.") from exc
        return scope, "/".join(relative[:4]), deployment
    raise Unavailable("Desktop file is not a verified export from a supported Flatpak installation.")


def _flatpak_size(raw):
    # Flatpak versions can report decimal SI sizes, binary sizes, or raw bytes.
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*(bytes?|[kKMGTPE]?i?B)?", raw)
    if not match:
        raise Unavailable("Flatpak returned an unsupported installed-size format.")
    number, unit = match.groups()
    unit = unit or "B"
    multiplier = 1
    if unit not in ("B", "byte", "bytes"):
        exponent = "KMGTPE".index(unit[0].upper()) + 1
        multiplier = (1024 if "i" in unit else 1000) ** exponent
    try:
        size = Decimal(number) * multiplier
        if size != size.to_integral_value() or not 0 <= size <= MAX_BYTES:
            raise Unavailable("Flatpak installed size is outside the supported range.")
        return int(size), unit not in ("B", "byte", "bytes")
    except InvalidOperation as exc:
        raise Unavailable("Flatpak installed size is invalid.") from exc


def resolve_installations(apps, env=None):
    """Attribute each winning launcher to one package/deployment, counting once."""
    env = dict(os.environ if env is None else env)
    result = {"scannedAt": int(time.time() * 1000), "groups": [], "apps": [],
              "totalBytes": 0, "knownApps": 0, "unresolvedApps": 0, "issues": []}
    deadline = time.monotonic() + TOTAL_SECONDS
    pending, targets, groups, flatpaks = [], set(), {}, {}

    def issue(message):
        message = _text(message)
        if message not in result["issues"] and len(result["issues"]) < 64:
            result["issues"].append(message)

    seen = set()
    for app in apps:
        if len(pending) >= MAX_APPS:
            issue("Installation inventory exceeds the application limit.")
            break
        app_id = app.get("id", "")
        if not isinstance(app_id, str) or not app_id or _text(app_id, 256) != app_id or app_id in seen:
            issue("Installation inventory contains an invalid or duplicate application ID.")
            continue
        seen.add(app_id)
        row = {"id": app_id, "groupKey": "", "status": "unknown", "reason": ""}
        result["apps"].append(row)
        path, resolved, failure = app.get("_desktopFile", ""), "", ""
        try:
            if not isinstance(path, str) or not os.path.isabs(path) or len(path) > 4096 or "\x00" in path:
                raise Unavailable("Winning desktop-file provenance is unavailable.")
            path = os.path.normpath(path)
            resolved = os.path.realpath(path, strict=True)
            if not stat.S_ISREG(os.stat(resolved).st_mode):
                raise Unavailable("Winning desktop file is not a regular file.")
            # Opening catches denied files even when stat/realpath can succeed.
            _read(resolved, MAX_OUTPUT)
        except (OSError, ValueError, Unavailable) as exc:
            failure = str(exc) if isinstance(exc, Unavailable) else "Winning desktop file is missing or inaccessible."
        flatpak_id = app.get("_flatpak", "")
        pending.append((row, path, resolved, flatpak_id, failure))
        if not failure and not flatpak_id:
            targets.update((path, resolved))
    ownership, pacman_error = {}, ""
    if targets:
        try:
            ownership = _pacman(targets, env, deadline)
        except Unavailable as exc:
            pacman_error = str(exc)
            issue(pacman_error)
    for row, path, resolved, flatpak_id, failure in pending:
        group = None
        try:
            if failure:
                raise Unavailable(failure)
            if flatpak_id:
                if not isinstance(flatpak_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2,}", flatpak_id):
                    raise Unavailable("Declared Flatpak application ID is invalid.")
                scope, ref, deployment = _flatpak_provenance(path, resolved, flatpak_id, env)
                key = _identity("flatpak", deployment)
                if key not in flatpaks:
                    try:
                        location = _command(["flatpak", "info", scope, "--show-location", ref], env, deadline)
                        if os.path.realpath(location, strict=True) != deployment:
                            raise Unavailable("Flatpak installed deployment changed or does not match its desktop export.")
                        size, rounded = _flatpak_size(_command(["flatpak", "info", scope, "--show-size", ref], env, deadline))
                        flatpaks[key] = {"key": key, "name": _text(flatpak_id, 256), "kind": "flatpak",
                                         "bytes": size, "status": "known", "appIds": [],
                                         "reason": ("Rounded installed size reported by flatpak info; shared runtimes excluded."
                                                    if rounded else "Installed size reported by flatpak info; shared runtimes excluded.")}
                    except (Unavailable, OSError, ValueError) as exc:
                        reason = str(exc) if isinstance(exc, Unavailable) else "Flatpak installed deployment is inaccessible."
                        flatpaks[key] = {"key": key, "name": _text(flatpak_id, 256), "kind": "flatpak",
                                         "bytes": None, "status": "unknown", "appIds": [], "reason": _text(reason)}
                        issue(reason)
                group = flatpaks[key]
            else:
                if pacman_error:
                    raise Unavailable(pacman_error)
                group = ownership.get(path) or ownership.get(resolved)
                if group is None:
                    raise Unavailable("Winning desktop file is not owned by a supported installed package.")
            key = group["key"]
            if key not in groups:
                groups[key] = dict(group, appIds=[])
            groups[key]["appIds"].append(row["id"])
            row.update(groupKey=key, status=group["status"], reason=group["reason"])
        except Unavailable as exc:
            row["reason"] = _text(exc)
    for group in groups.values():
        group["appIds"].sort()
        if group["status"] == "known":
            if result["totalBytes"] + group["bytes"] > MAX_BYTES:
                group.update(bytes=None, status="unknown", reason="Combined installed size exceeds the supported range.")
                issue(group["reason"])
            else:
                result["totalBytes"] += group["bytes"]
    for row in result["apps"]:
        group = groups.get(row["groupKey"])
        if group and group["status"] == "known":
            row["status"] = "shared" if len(group["appIds"]) > 1 else "known"
            result["knownApps"] += 1
        else:
            if group:
                row.update(status="unknown", reason=group["reason"])
            result["unresolvedApps"] += 1
    result["groups"] = sorted(groups.values(), key=lambda group: (group["name"], group["key"]))
    result["apps"].sort(key=lambda row: row["id"])
    return result
