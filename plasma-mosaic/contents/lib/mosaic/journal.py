"""Private, bounded local settings and scan summaries. Never writes application data."""
from contextlib import contextmanager
import copy
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import time

CATEGORIES = ("config", "cache", "data", "state")
MAX_INTEGER = 9007199254740991
MAX_SETTINGS_BYTES = 1024 * 1024
MAX_HISTORY_BYTES = 2 * 1024 * 1024
MAX_HISTORY = 60
MAX_ALERTS = 50
MIN_THRESHOLD = 1024 * 1024
MAX_THRESHOLD = 1024 ** 4
DEFAULT_SETTINGS = {"historyEnabled": False, "alertsEnabled": False,
                    "thresholdBytes": 256 * 1024 * 1024, "customMappings": []}
ISSUES = {"permission", "changed", "symlink", "special", "limit", "error", "hardlink", "cancelled"}
PATH_STATES = {"complete", "partial", "denied", "missing", "symlink", "error"}


class JournalError(ValueError):
    """An explicit input, permissions, or persisted-state failure."""


def require(condition, message):
    if not condition:
        raise JournalError(message)


def text(value, maximum, nonempty=False):
    from scanner import bounded_text
    return (isinstance(value, str) and (bool(value) or not nonempty)
            and bounded_text(value, maximum) == value)


def integer(value, minimum=0, maximum=MAX_INTEGER):
    return type(value) is int and minimum <= value <= maximum


def timestamp(value):
    return integer(value, 1, min(MAX_INTEGER, int(time.time() * 1000) + 60000))


def desktop_id(value):
    return (text(value, 256, True) and value.endswith(".desktop") and len(value) > 8
            and "/" not in value and not any(ord(c) < 32 or ord(c) == 127 for c in value))


def absolute_path(value):
    return (text(value, 4096, True) and value.startswith("/") and value != "/"
            and all(part not in ("", ".", "..") for part in value[1:].split("/")))


def encode(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), allow_nan=False).encode("ascii")


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON field")
        result[key] = value
    return result


def decode(raw):
    try:
        return json.loads(raw, object_pairs_hook=_pairs,
                          parse_constant=lambda value: (_ for _ in ()).throw(JournalError("Nonfinite JSON number")))
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise JournalError("Invalid JSON data: " + str(exc)[:160]) from exc


def paths(env=None):
    from scanner import locations
    roots, _ = locations(env)
    return (os.path.join(roots["config"], "omarchy", "mosaic"),
            os.path.join(roots["state"], "omarchy", "mosaic"))


def validate_mapping(mapping, env=None, existing=False):
    require(isinstance(mapping, dict) and set(mapping) == {"id", "path", "category"}, "Invalid mapping fields")
    require(desktop_id(mapping["id"]), "Invalid desktop application ID")
    require(absolute_path(mapping["path"]), "Mapping needs a canonical absolute path")
    require(mapping["category"] in CATEGORIES, "Invalid mapping category")
    from scanner import locations, open_parent
    roots, _ = locations(env)
    path = mapping["path"]
    broad = {"/", "/bin", "/boot", "/dev", "/etc", "/home", "/lib", "/lib64", "/media", "/mnt",
             "/opt", "/proc", "/root", "/run", "/sbin", "/srv", "/sys", "/tmp", "/usr", "/usr/bin",
             "/usr/lib", "/usr/lib64", "/usr/local", "/usr/local/bin", "/usr/local/lib", "/usr/local/share",
             "/usr/share", "/var", "/var/cache", "/var/lib", "/var/log", "/var/tmp"}
    broad.update(roots.values())
    broad.update({os.path.dirname(roots["data"]), os.path.join(roots["home"], ".var"),
                  os.path.join(roots["home"], ".var", "app")})
    require(path not in broad and not any(root.startswith(path + "/") for root in roots.values()),
            "Broad system, home, and XDG roots cannot be assigned")
    require(not any(path == root or path.startswith(root + "/") for root in ("/proc", "/sys", "/dev", "/run")),
            "Virtual and runtime filesystems cannot be assigned")
    if not existing:
        try:
            fd, name = open_parent(path)
            try:
                item = os.stat(name, dir_fd=fd, follow_symlinks=False)
                require(stat.S_ISREG(item.st_mode) or stat.S_ISDIR(item.st_mode),
                        "Mapping target must be a regular file or directory, not a symlink or special file")
            finally:
                os.close(fd)
        except OSError as exc:
            raise JournalError("Cannot safely inspect mapping target: " + str(exc)) from exc
    return dict(mapping)


def validate_settings(value, env=None):
    require(isinstance(value, dict) and set(value) == set(DEFAULT_SETTINGS), "Invalid saved settings fields")
    require(type(value["historyEnabled"]) is bool and type(value["alertsEnabled"]) is bool, "Invalid settings toggles")
    require(not value["alertsEnabled"] or value["historyEnabled"], "Growth alerts require history")
    require(integer(value["thresholdBytes"], MIN_THRESHOLD, MAX_THRESHOLD), "Growth threshold must be between 1 MiB and 1 TiB")
    mappings = value["customMappings"]
    require(isinstance(mappings, list) and len(mappings) <= 128, "Too many custom mappings")
    seen, counts = set(), {}
    for item in mappings:
        validate_mapping(item, env, existing=True)
        key = (item["id"], item["path"])
        require(key not in seen, "Duplicate custom mapping")
        seen.add(key)
        counts[item["id"]] = counts.get(item["id"], 0) + 1
        require(counts[item["id"]] <= 24, "Too many mappings for one application")
    return copy.deepcopy(value)


def _private_directory(fd):
    info = os.fstat(fd)
    require(info.st_uid == os.geteuid() and not info.st_mode & 0o077,
            "Plugin storage directory must be privately owned (mode 0700)")


def _directory(path, create=False):
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in os.path.abspath(path).split("/")[1:]:
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
            os.close(fd)
            fd = child
        _private_directory(fd)
        return fd
    except BaseException:
        os.close(fd)
        raise


def _read(directory, name, maximum, default):
    try:
        parent = _directory(directory)
    except FileNotFoundError:
        return copy.deepcopy(default)
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=parent)
        except FileNotFoundError:
            return copy.deepcopy(default)
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and not info.st_mode & 0o077
                    and info.st_nlink == 1, "Plugin state must be a private, non-linked regular file (mode 0600)")
            require(info.st_size <= maximum, "Saved plugin state exceeds its size limit")
            chunks, remaining = [], maximum + 1
            while remaining:
                chunk = os.read(fd, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            raw = b"".join(chunks)
            require(len(raw) <= maximum, "Saved plugin state exceeds its size limit")
            return decode(raw)
        finally:
            os.close(fd)
    finally:
        os.close(parent)


def _atomic_write(directory, name, value, maximum):
    raw = encode(value)
    require(len(raw) <= maximum, "Plugin state exceeds its encoded size limit")
    parent = _directory(directory, create=True)
    temporary = "." + name + "." + secrets.token_hex(12)
    created = False
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=parent)
        created = True
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, name, src_dir_fd=parent, dst_dir_fd=parent)
            created = False
            os.fsync(parent)
        finally:
            if created:
                os.unlink(temporary, dir_fd=parent)
    finally:
        os.close(parent)


def read_settings(env=None):
    try:
        return validate_settings(_read(paths(env)[0], "settings.json", MAX_SETTINGS_BYTES, DEFAULT_SETTINGS), env)
    except OSError as exc:
        raise JournalError("Cannot read settings: " + str(exc)) from exc


def _validate_summary(snapshot):
    require(isinstance(snapshot, dict) and set(snapshot) == {"key", "at", "mode", "targetId", "mappedBytes", "partial", "apps"},
            "Invalid saved snapshot fields")
    require(text(snapshot["key"], 64) and re.fullmatch(r"[0-9a-f]{64}", snapshot["key"]), "Invalid saved scan identity")
    require(timestamp(snapshot["at"]) and integer(snapshot["mappedBytes"]) and type(snapshot["partial"]) is bool,
            "Invalid saved snapshot values")
    require(snapshot["mode"] in ("overview", "deep"), "Invalid saved scan scope")
    apps = snapshot["apps"]
    require(isinstance(apps, list) and len(apps) <= 512, "Invalid saved application summaries")
    require((snapshot["mode"] == "overview" and snapshot["targetId"] == "") or
            (snapshot["mode"] == "deep" and desktop_id(snapshot["targetId"]) and len(apps) == 1), "Invalid saved scan target")
    seen, total = set(), 0
    for app in apps:
        require(isinstance(app, dict) and set(app) == {"id", "name", "bytes", "partial", "categories", "signature"},
                "Invalid saved application fields")
        require(desktop_id(app["id"]) and app["id"] not in seen and text(app["name"], 256), "Invalid saved application identity")
        seen.add(app["id"])
        require((app["bytes"] is None or integer(app["bytes"])) and type(app["partial"]) is bool,
                "Invalid saved application measurement")
        require(isinstance(app["categories"], dict) and set(app["categories"]) == set(CATEGORIES)
                and all(integer(v) for v in app["categories"].values()), "Invalid saved categories")
        require(sum(app["categories"].values()) == (app["bytes"] or 0), "Inconsistent saved application total")
        require(text(app["signature"], 131) and re.fullmatch(r"[0-9a-f]{64}:[0-9a-f]{64}:[01]", app["signature"]),
                "Invalid saved ownership signature")
        total += app["bytes"] or 0
    require(total == snapshot["mappedBytes"], "Inconsistent saved snapshot total")
    require(snapshot["mode"] != "deep" or apps[0]["id"] == snapshot["targetId"], "Inconsistent saved scan target")
    require(snapshot["key"] == scan_key(snapshot["mode"], snapshot["targetId"], snapshot["at"]), "Inconsistent saved scan identity")


def _validate_alert(alert):
    require(isinstance(alert, dict) and set(alert) == {"key", "id", "name", "delta", "at", "thresholdBytes"}, "Invalid saved alert fields")
    require(text(alert["key"], 64) and re.fullmatch(r"[0-9a-f]{64}", alert["key"])
            and desktop_id(alert["id"]) and text(alert["name"], 256) and timestamp(alert["at"])
            and integer(alert["delta"], 1) and integer(alert["thresholdBytes"], MIN_THRESHOLD, MAX_THRESHOLD)
            and alert["delta"] >= alert["thresholdBytes"], "Invalid saved alert")


def read_history(env=None):
    try:
        state = _read(paths(env)[1], "history.json", MAX_HISTORY_BYTES, {"version": 1, "snapshots": [], "alerts": []})
        require(isinstance(state, dict) and set(state) == {"version", "snapshots", "alerts"}
                and type(state["version"]) is int and state["version"] == 1, "Invalid history format")
        require(isinstance(state["snapshots"], list) and len(state["snapshots"]) <= MAX_HISTORY
                and isinstance(state["alerts"], list) and len(state["alerts"]) <= MAX_ALERTS, "History exceeds retention limits")
        keys, last = set(), 0
        for snapshot in state["snapshots"]:
            _validate_summary(snapshot)
            require(snapshot["key"] not in keys and snapshot["at"] >= last, "Duplicate or unsorted saved snapshots")
            keys.add(snapshot["key"])
            last = snapshot["at"]
        keys = set()
        for alert in state["alerts"]:
            _validate_alert(alert)
            require(alert["key"] not in keys, "Duplicate saved alert")
            keys.add(alert["key"])
        return state
    except OSError as exc:
        raise JournalError("Cannot read history: " + str(exc)) from exc


def digest(value):
    return hashlib.sha256(encode(value)).hexdigest()


def scan_key(mode, target, at):
    return digest([mode, target, at])


def _validate_path(item):
    require(isinstance(item, dict) and {"path", "label", "category", "confidence", "reason", "status", "bytes", "issues",
                                      "measuredAt", "entriesSeen", "evidence", "source", "breakdown",
                                      "skippedCounts", "skippedSamples"} <= set(item)
            and absolute_path(item.get("path")) and text(item.get("label"), 4096)
            and item.get("category") in CATEGORIES and item.get("confidence") in ("known", "possible", "shared")
            and item.get("reason") in ("rule", "app-id", "name-match", "shared", "flatpak", "user")
            and item.get("status") in PATH_STATES, "Invalid snapshot path")
    size = item.get("bytes")
    require((size is None or integer(size)) and (item["status"] != "complete" or size is not None)
            and timestamp(item.get("measuredAt")) and integer(item.get("entriesSeen"))
            and text(item.get("evidence"), 1024) and text(item.get("source"), 2048), "Invalid snapshot measurement")
    def issues(value):
        return isinstance(value, list) and len(value) <= len(ISSUES) and all(isinstance(v, str) and v in ISSUES for v in value)
    require(issues(item.get("issues")) and "cancelled" not in item["issues"], "Unfinished or invalid snapshot issues")
    require(item["status"] != "complete" or not set(item["issues"]) - {"hardlink"}, "Incomplete measurement marked complete")
    data = item.get("breakdown")
    require(isinstance(data, dict) and all(integer(data.get(k)) for k in ("directBytes", "directFiles", "otherBytes", "otherCount"))
            and isinstance(data.get("children"), list) and len(data["children"]) <= 12, "Invalid measurement breakdown")
    total, seen = data["directBytes"] + data["otherBytes"], set()
    for child in data["children"]:
        require(isinstance(child, dict) and {"name", "bytes", "status", "issues"} <= set(child)
                and text(child.get("name"), 255, True) and child["name"] not in (".", "..")
                and "/" not in child["name"] and child["name"] not in seen and child.get("status") in PATH_STATES
                and issues(child.get("issues")) and (child.get("bytes") is None or integer(child["bytes"]))
                and (child["status"] != "complete" or child.get("bytes") is not None)
                and (item["status"] != "complete" or child["status"] == "complete"), "Invalid measurement child")
        seen.add(child["name"])
        total += child.get("bytes") or 0
    require(integer(total) and total == (size or 0), "Inconsistent measurement breakdown")
    counts, samples = item.get("skippedCounts"), item.get("skippedSamples")
    require(isinstance(counts, dict) and set(counts) <= ISSUES and all(integer(v) for v in counts.values())
            and isinstance(samples, list) and len(samples) <= 8, "Invalid skipped measurement metadata")
    for sample in samples:
        require(isinstance(sample, dict) and text(sample.get("relative"), 512, True)
                and isinstance(sample.get("reason"), str) and counts.get(sample["reason"], 0) > 0
                and type(sample.get("truncated")) is bool, "Invalid skipped measurement sample")


def summarize(snapshot):
    require(isinstance(snapshot, dict) and set(snapshot) == {"mode", "targetId", "scannedAt", "inventoryComplete", "limited", "partial", "apps"},
            "Invalid snapshot fields")
    mode, target, at, apps = (snapshot[k] for k in ("mode", "targetId", "scannedAt", "apps"))
    require(mode in ("overview", "deep") and timestamp(at) and isinstance(apps, list) and len(apps) <= 512,
            "Invalid scan scope or time")
    require(all(type(snapshot[k]) is bool for k in ("inventoryComplete", "limited", "partial")), "Invalid scan completion flags")
    require((mode == "overview" and target == "") or (mode == "deep" and desktop_id(target) and len(apps) == 1), "Invalid scan target")
    seen, identities, summaries, known_by_app = set(), [], [], []
    any_hardlinks = False
    for app in apps:
        require(isinstance(app, dict) and desktop_id(app.get("id")) and app["id"] not in seen
                and text(app.get("name"), 256) and text(app.get("icon"), 4096)
                and isinstance(app.get("paths"), list) and len(app["paths"]) <= 24
                and app.get("status") in ("complete", "partial", "unmapped") and timestamp(app.get("scannedAt")), "Invalid snapshot application")
        seen.add(app["id"])
        path_seen, known, categories = set(), [], dict.fromkeys(CATEGORIES, 0)
        for item in app["paths"]:
            _validate_path(item)
            require(item["path"] not in path_seen, "Duplicate snapshot path")
            path_seen.add(item["path"])
            if item["confidence"] == "known":
                known.append(item)
                identities.append([app["id"], item["path"], item["category"], item["reason"]])
                any_hardlinks |= "hardlink" in item["issues"]
                if item["bytes"] is not None:
                    categories[item["category"]] += item["bytes"]
        require(isinstance(app.get("categories"), dict) and set(app["categories"]) == set(CATEGORIES)
                and all(integer(app["categories"][k]) and app["categories"][k] == categories[k] for k in CATEGORIES)
                and integer(app.get("mappedBytes")) and app["mappedBytes"] == sum(categories.values()), "Inconsistent mapped application total")
        require(app["status"] != "unmapped" or not app["paths"], "Unmapped application has paths")
        require(app["status"] != "complete" or (app["paths"] and all(p["status"] == "complete" for p in app["paths"])), "Incomplete application marked complete")
        size = sum(categories.values()) if any(p["bytes"] is not None for p in known) else None
        summaries.append({"id": app["id"], "name": app["name"], "bytes": size,
                          "partial": app["status"] == "partial" or any(p["status"] != "complete" for p in known),
                          "categories": categories, "signature": ""})
        known_by_app.append(known)
    require(mode != "deep" or apps[0]["id"] == target, "Snapshot target does not match application")
    accounting = digest(identities)
    preceding_complete = snapshot["inventoryComplete"] and not any_hardlinks
    for summary, known in zip(summaries, known_by_app):
        identity = digest([[p["path"], p["category"], p["reason"]] for p in known])
        safe = preceding_complete and not summary["partial"] and all(p["status"] == "complete" for p in known)
        summary["signature"] = identity + ":" + accounting + ":" + ("1" if safe else "0")
        preceding_complete = safe
    total = sum(app["bytes"] or 0 for app in summaries)
    require(integer(total), "Snapshot total exceeds supported range")
    return {"key": scan_key(mode, target, at), "at": at, "mode": mode, "targetId": target,
            "mappedBytes": total, "partial": snapshot["partial"] or snapshot["limited"] or not snapshot["inventoryComplete"]
            or any(a["partial"] or a["bytes"] is None for a in summaries), "apps": summaries}


def comparisons(current, previous=None):
    if previous is not None and (current["mode"], current["targetId"]) != (previous["mode"], previous["targetId"]):
        previous = None
    before = {app["id"]: app for app in previous["apps"]} if previous else {}
    rows = []
    for app in current["apps"]:
        old = before.get(app["id"])
        reason, delta = "no-baseline", None
        if old is not None:
            own, context, safe = app["signature"].split(":")
            old_own, old_context, old_safe = old["signature"].split(":")
            if current["at"] <= previous["at"]:
                reason = "non-increasing-time"
            elif app["bytes"] is None or old["bytes"] is None:
                reason = "unmapped"
            elif app["partial"] or old["partial"]:
                reason = "incomplete"
            elif own != old_own:
                reason = "ownership-changed"
            elif context != old_context:
                reason = "accounting-changed"
            elif safe != "1" or old_safe != "1":
                reason = "accounting-uncertain"
            else:
                reason, delta = "comparable", app["bytes"] - old["bytes"]
        elif app["bytes"] is None:
            reason = "unmapped"
        rows.append({"id": app["id"], "name": app["name"], "bytes": app["bytes"], "delta": delta,
                     "previousAt": previous["at"] if previous is not None else 0, "at": current["at"],
                     "comparable": delta is not None, "reason": reason, "mode": current["mode"]})
    return rows


def growth(history, current=None):
    snapshots = list(history)
    if current is not None and not any(s["key"] == current["key"] for s in snapshots):
        snapshots.append(current)
    snapshots.sort(key=lambda s: s["at"])
    scopes = {}
    for snapshot in snapshots:
        scopes.setdefault((snapshot["mode"], snapshot["targetId"]), []).append(snapshot)
    rows = []
    for scans in scopes.values():
        rows.extend(comparisons(scans[-1], scans[-2] if len(scans) > 1 else None))
    return sorted(rows, key=lambda row: (-row["at"], row["mode"], row["id"]))[:1024]


class Journal:
    def __init__(self, env=None):
        self.env = env
        self.settings = read_settings(env)
        self.state = read_history(env)

    def save_settings(self, value):
        value = validate_settings(value, self.env)
        _atomic_write(paths(self.env)[0], "settings.json", value, MAX_SETTINGS_BYTES)
        self.settings = value

    def save_history(self):
        self.state["snapshots"] = self.state["snapshots"][-MAX_HISTORY:]
        self.state["alerts"] = self.state["alerts"][-MAX_ALERTS:]
        while len(encode(self.state)) > MAX_HISTORY_BYTES and len(self.state["snapshots"]) > 1:
            self.state["snapshots"].pop(0)
        while len(encode(self.state)) > MAX_HISTORY_BYTES and self.state["alerts"]:
            self.state["alerts"].pop(0)
        _atomic_write(paths(self.env)[1], "history.json", self.state, MAX_HISTORY_BYTES)

    def record(self, summary):
        if not self.settings["historyEnabled"]:
            return []
        snapshots = self.state["snapshots"]
        for old in snapshots:
            if old["key"] == summary["key"]:
                require(old == summary, "Conflicting contents for the same scan identity")
                return []
        scope = [s for s in snapshots if (s["mode"], s["targetId"]) == (summary["mode"], summary["targetId"])]
        previous = scope[-1] if scope else None
        if previous is not None and summary["at"] <= previous["at"]:
            return []  # Stale replay cannot create history or notifications.
        notifications = []
        if self.settings["alertsEnabled"]:
            existing = {event["key"] for event in self.state["alerts"]}
            for row in comparisons(summary, previous):
                if not row["comparable"] or row["delta"] < self.settings["thresholdBytes"]:
                    continue
                key = digest([summary["key"], row["id"]])
                if key not in existing:
                    notifications.append({"key": key, "id": row["id"], "name": row["name"], "delta": row["delta"],
                                          "at": summary["at"], "thresholdBytes": self.settings["thresholdBytes"]})
        notifications = sorted(notifications, key=lambda event: (-event["delta"], event["id"]))[:MAX_ALERTS]
        self.state["alerts"].extend(notifications)
        snapshots.append(copy.deepcopy(summary))
        snapshots.sort(key=lambda s: s["at"])
        self.save_history()
        return notifications


@contextmanager
def transaction(env=None):
    """One private lock serializes all read/modify/replace operations, across processes."""
    parent = fd = None
    try:
        parent = _directory(paths(env)[0], create=True)
        fd = os.open(".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, 0o600, dir_fd=parent)
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and not info.st_mode & 0o077
                and info.st_nlink == 1, "Unsafe plugin state lock")
        deadline = time.monotonic() + 3.0
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                require(time.monotonic() < deadline, "Plugin settings are busy; try again")
                time.sleep(0.025)
        yield Journal(env)
    except OSError as exc:
        raise JournalError("Cannot access private plugin storage: " + str(exc)) from exc
    finally:
        if fd is not None:
            os.close(fd)
        if parent is not None:
            os.close(parent)
