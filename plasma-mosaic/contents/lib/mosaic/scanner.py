#!/usr/bin/env python3
"""Read-only application storage metadata scanner; stdout is protocol-v3 NDJSON."""
import configparser
import errno
import heapq
import json
import os
import re
import signal
import stat
import sys
import time
from dataclasses import dataclass

from mappings import RULES, SOURCES

CATEGORIES = ("config", "cache", "data", "state")
MAX_LINE = 262144
MAX_APP_RECORD = 65536 - 4096
MAX_CHILDREN = 12
MAX_SKIPPED_SAMPLES = 8
PROGRESS_INTERVAL = 0.2


@dataclass(frozen=True)
class Limits:
    apps: int = 512
    paths: int = 24
    entries: int = 300000
    path_entries: int = 60000
    discovery_entries: int = 12000
    seconds: float = 25.0
    path_seconds: float = 3.0
    depth: int = 64
    metadata_bytes: int = 65536


DEEP_LIMITS = Limits(entries=1000000, path_entries=500000, seconds=90.0,
                     path_seconds=20.0, depth=96)


class UnknownApp(ValueError):
    pass


class SettingsError(ValueError):
    pass


class ScanTimeout(Exception):
    pass


class LimitReached(Exception):
    pass


class Budget:
    def __init__(self, limits=None, clock=time.monotonic):
        self.limits = limits or Limits()
        self.clock = clock
        self.deadline = clock() + self.limits.seconds
        self.entries = 0
        self.warnings = set()
        self.inventory_complete = True

    def check(self):
        if self.clock() >= self.deadline or self.entries >= self.limits.entries:
            self.warnings.add("limit")
            raise LimitReached()


def bounded_text(value, maximum):
    """Bound text in UTF-16 units, matching the QML protocol validator."""
    value = value.replace("\x00", "\ufffd")
    units = value.encode("utf-16-le", "surrogatepass")
    if len(units) <= maximum * 2:
        return value
    clipped = units[:maximum * 2]
    if 0xD800 <= int.from_bytes(clipped[-2:], "little") <= 0xDBFF:
        clipped = clipped[:-2]
    return clipped.decode("utf-16-le", "surrogatepass")


def empty_breakdown():
    return {"children": [], "directBytes": 0, "directFiles": 0,
            "otherBytes": 0, "otherCount": 0}


def locations(env=None):
    env = os.environ if env is None else env
    home = os.path.abspath(env.get("HOME") or os.path.expanduser("~"))
    def xdg(key, fallback):
        value = env.get(key, "")
        return os.path.normpath(value) if os.path.isabs(value) else os.path.join(home, fallback)
    roots = {"home": home, "config": xdg("XDG_CONFIG_HOME", ".config"),
             "cache": xdg("XDG_CACHE_HOME", ".cache"),
             "data": xdg("XDG_DATA_HOME", ".local/share"),
             "state": xdg("XDG_STATE_HOME", ".local/state")}
    dirs = [roots["data"]] + [p for p in env.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if os.path.isabs(p)]
    dirs += [os.path.join(roots["data"], "flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    return roots, list(dict.fromkeys(os.path.join(p, "applications") for p in dirs))


def open_parent(path):
    """Pin every ancestor with O_NOFOLLOW, including ancestors of a root."""
    parts = os.path.abspath(path).split(os.sep)
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd, parts[-1]
    except BaseException:
        os.close(fd)
        raise


def issue_for(exc):
    if exc.errno in (errno.EACCES, errno.EPERM):
        return "permission"
    if exc.errno in (errno.ELOOP, errno.ENOTDIR):
        return "symlink"
    if exc.errno == errno.ENOENT:
        return "changed"
    return "error"


def read_desktop(path, limits):
    # Desktop exports may themselves be symlinks. Read only bounded regular
    # desktop metadata; never execute Exec/TryExec or open referenced content.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        data = os.read(fd, limits.metadata_bytes + 1)
    finally:
        os.close(fd)
    if len(data) > limits.metadata_bytes:
        return None
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read_string(data.decode("utf-8"))
        return dict(parser["Desktop Entry"])
    except (configparser.Error, KeyError, UnicodeError):
        return None


def discover(application_dirs, budget):
    seen, apps = set(), []
    count = 0

    def uncertain(reason):
        budget.inventory_complete = False
        budget.warnings.add(reason)

    for directory in application_dirs:
        stack = [(directory, "", 0)]
        while stack:
            current, prefix, depth = stack.pop()
            opened = False
            try:
                budget.check()
                with os.scandir(current) as entries:
                    opened = True
                    for entry in entries:
                        count += 1
                        budget.check()
                        if count > budget.limits.discovery_entries:
                            raise LimitReached()
                        if entry.is_dir(follow_symlinks=False):
                            if depth < 8:
                                stack.append((entry.path, prefix + entry.name + "-", depth + 1))
                            else:
                                uncertain("limit")
                            continue
                        if not entry.name.endswith(".desktop"):
                            if entry.is_symlink() and entry.is_dir():
                                uncertain("metadata")
                            continue
                        desktop_id = prefix + entry.name
                        if desktop_id in seen:
                            continue
                        # Even invalid/hidden high-priority files mask lower entries.
                        seen.add(desktop_id)
                        try:
                            metadata = read_desktop(entry.path, budget.limits)
                        except OSError:
                            uncertain("metadata")
                            continue
                        if not metadata:
                            uncertain("metadata")
                            continue
                        if metadata.get("Hidden", "false").lower() == "true" or metadata.get("NoDisplay", "false").lower() == "true":
                            continue
                        if metadata.get("Type") in ("Link", "Directory"):
                            continue
                        if metadata.get("Type") != "Application" or not metadata.get("Name"):
                            uncertain("metadata")
                            continue
                        if bounded_text(desktop_id, 256) != desktop_id:
                            uncertain("limit")
                            continue
                        apps.append({"id": desktop_id, "name": bounded_text(metadata["Name"], 256),
                                     "icon": bounded_text(metadata.get("Icon", ""), 256), "paths": [],
                                     "mappedBytes": 0, "categories": dict.fromkeys(CATEGORIES, 0),
                                     "status": "pending", "scannedAt": 0,
                                     "_desktopFile": entry.path,
                                     "_flatpak": metadata.get("X-Flatpak", "")})
                        if len(apps) >= min(512, budget.limits.apps):
                            raise LimitReached()
            except FileNotFoundError:
                # An absent default applications directory is normal; a
                # directory disappearing after discovery leaves absence unknown.
                if opened or prefix:
                    uncertain("metadata")
            except OSError:
                uncertain("metadata")
            except LimitReached:
                uncertain("limit")
                return sorted(apps, key=lambda a: a["id"])
    return sorted(apps, key=lambda a: a["id"])


def candidate(path, category, confidence, reason, home, evidence, source, keep_missing=False):
    path = os.path.normpath(path)
    if bounded_text(path, 4096) != path or not os.path.isabs(path):
        return None
    # lstat without traversing any symlink ancestors; keep denied roots visible.
    try:
        fd, name = open_parent(path)
        try:
            os.stat(name, dir_fd=fd, follow_symlinks=False)
        finally:
            os.close(fd)
    except FileNotFoundError:
        if not keep_missing:
            return None
    except OSError:
        pass
    label = "~" + path[len(home):] if path == home or path.startswith(home + "/") else path
    return {"path": path, "label": label, "category": category,
            "confidence": confidence, "reason": reason, "status": "pending",
            "bytes": None, "issues": [], "measuredAt": 0, "entriesSeen": 0,
            "evidence": bounded_text(evidence, 1024), "source": bounded_text(source, 2048),
            "breakdown": empty_breakdown(), "skippedCounts": {}, "skippedSamples": []}


def map_paths(apps, roots, budget, rules=None, custom_mappings=None):
    rules = RULES if rules is None else rules
    assigned = {}
    for mapping in custom_mappings or ():
        assigned.setdefault(mapping["id"], []).append(mapping)
    for app in apps:
        paths = {}
        flatpak = app.pop("_flatpak", "")
        app.pop("_desktopFile", None)
        # Explicit roots precede built-ins and guesses, including when a
        # later inventory-size limit has to discard trailing candidates.
        for mapping in assigned.get(app["id"], ()):
            evidence = (f"User assigned this {mapping['category']} location to desktop ID {app['id']}; "
                        "ownership has not been independently verified.")
            item = candidate(mapping["path"], mapping["category"], "known", "user",
                             roots["home"], evidence, "", keep_missing=True)
            if item:
                paths[item["path"]] = item

        def add(base, relative, confidence, reason, source="", category=None):
            if not relative or relative.startswith("/") or any(p in (".", "..", "") for p in relative.split("/")):
                return
            path = os.path.join(roots[base], relative)
            if path in paths:
                return
            if reason == "rule":
                evidence = f"Exact desktop ID {app['id']}; {base} root-relative mapping: {relative}."
            elif reason == "flatpak":
                evidence = (f"Desktop ID {app['id']} declares Flatpak namespace {flatpak}; "
                            f"{base} root-relative mapping: {relative}.")
            else:
                rationale = "desktop-ID" if reason == "app-id" else "display-name"
                evidence = (f"Possible {rationale} match for {app['id']}; "
                            f"{base} root-relative path: {relative}. Ownership is not confirmed.")
            item = candidate(path, category or ("data" if base == "home" else base), confidence, reason,
                             roots["home"], evidence, source)
            if item:
                paths[path] = item
        try:
            budget.check()
            stem = app["id"][:-8]
            for base, names in rules.get(stem, {}).items():
                for name in names:
                    add(base, name, "known", "rule", SOURCES.get(stem, ""))
            if re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2,}", flatpak):
                for category in CATEGORIES:
                    add("home", ".var/app/" + flatpak + "/" + category, "known", "flatpak",
                        "https://docs.flatpak.org/en/latest/sandbox-permissions.html", category)
            for name, reason in [(stem, "app-id"), (app["name"], "name-match"), (app["name"].lower().replace(" ", "-"), "name-match")]:
                if "/" not in name and name not in ("", ".", ".."):
                    for category in CATEGORIES:
                        add(category, name, "possible", reason)
        except LimitReached:
            app["status"] = "partial"
        app["paths"] = list(paths.values())
    # Resolve overlaps before clipping any app's candidates: an omitted root
    # must not make a retained root appear exclusively owned.
    ordered = sorted((p["path"], i, p) for i, a in enumerate(apps) for p in a["paths"])
    ancestors = []
    for path, owner, item in ordered:
        ancestors = [(p, i, v) for p, i, v in ancestors if path == p or path.startswith(p + "/")]
        for _, _, other in ancestors:
            other["confidence"] = item["confidence"] = "shared"
            other["reason"] = item["reason"] = "shared"
            for shared in (other, item):
                if not shared["evidence"].startswith("Shared or overlapping root;"):
                    shared["evidence"] = bounded_text(
                        "Shared or overlapping root; ownership is not exclusive. " + shared["evidence"], 1024)
        ancestors.append((path, owner, item))
    maximum = min(24, budget.limits.paths)
    for app in apps:
        if len(app["paths"]) > maximum:
            budget.warnings.add("limit")
            app["status"] = "partial"
            del app["paths"][maximum:]
        if not app["paths"] and app["status"] != "partial":
            app["status"] = "unmapped"


def measure(path, budget, global_seen=None, progress=None):
    """Measure and partition once, with pinned directory FDs and no content reads."""
    deadline = min(budget.deadline, budget.clock() + budget.limits.path_seconds)
    issues, seen = set(), set()
    skipped_counts, skipped_samples = {}, []
    breakdown, largest = empty_breakdown(), []
    total = visited = child_count = 0
    global_seen = set() if global_seen is None else global_seen

    def note(reason, relative, child):
        issues.add(reason)
        if child is not None:
            child["issues"].add(reason)
        skipped_counts[reason] = skipped_counts.get(reason, 0) + 1
        if len(skipped_samples) < MAX_SKIPPED_SAMPLES:
            label = bounded_text(relative, 512)
            skipped_samples.append({"relative": label, "reason": reason,
                                    "truncated": label != relative})

    def stop(relative, child):
        note("limit", relative, child)
        budget.warnings.add("limit")
        raise LimitReached()

    def check(relative, child):
        nonlocal visited
        try:
            budget.check()
        except LimitReached:
            stop(relative, child)
        if visited >= budget.limits.path_entries or budget.clock() >= deadline:
            stop(relative, child)
        visited += 1
        budget.entries += 1

    def finish_child(child, status):
        nonlocal child_count
        child_count += 1
        if status == "complete" and child["issues"] - {"hardlink"}:
            status = "partial"
        child["status"] = status
        child["issues"] = sorted(child["issues"])
        if status not in ("complete", "partial"):
            child["bytes"] = None
        # Only the best twelve children remain resident. Every evicted child's
        # measured contribution goes into "other", including partial children.
        rank = child["bytes"] if child["bytes"] is not None else -1
        entry = (rank, child["name"], child_count, child)
        if len(largest) < MAX_CHILDREN:
            heapq.heappush(largest, entry)
        else:
            omitted = heapq.heappushpop(largest, entry)[3]
            breakdown["otherBytes"] += omitted["bytes"] or 0
            breakdown["otherCount"] += 1

    def failed_status(reason):
        return {"permission": "denied", "changed": "missing",
                "symlink": "symlink"}.get(reason, "error")

    def visit(parent, name, depth, relative, child=None):
        nonlocal total
        status, own_child, started = "complete", False, False
        try:
            check(relative, child)
            before = os.stat(name, dir_fd=parent, follow_symlinks=False)
            key = (before.st_dev, before.st_ino)
            if stat.S_ISLNK(before.st_mode):
                note("symlink", relative, child)
                status = "symlink"
            elif stat.S_ISREG(before.st_mode):
                if depth <= 1:
                    breakdown["directFiles"] += 1
                if key in seen or (before.st_nlink > 1 and key in global_seen):
                    note("hardlink", relative, child)
                else:
                    total += before.st_size
                    if child is None:
                        breakdown["directBytes"] += before.st_size
                    else:
                        child["bytes"] += before.st_size
                    seen.add(key)
                    if before.st_nlink > 1:
                        global_seen.add(key)
            elif not stat.S_ISDIR(before.st_mode):
                note("special", relative, child)
                status = "partial"
            else:
                if depth == 1:
                    child = {"name": name, "bytes": 0, "issues": set()}
                    own_child = True
                if depth >= budget.limits.depth:
                    stop(relative, child)
                fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                             dir_fd=parent)
                try:
                    opened = os.fstat(fd)
                    if (opened.st_dev, opened.st_ino) != key:
                        note("changed", relative, child)
                        status = "partial"
                    else:
                        with os.scandir(fd) as entries:
                            started = True
                            for entry in entries:
                                location = entry.name if relative == "." else relative + "/" + entry.name
                                visit(fd, entry.name, depth + 1, location, child)
                        after = os.fstat(fd)
                        if (opened.st_mtime_ns, opened.st_ctime_ns) != (after.st_mtime_ns, after.st_ctime_ns):
                            note("changed", relative, child)
                finally:
                    os.close(fd)
        except LimitReached:
            status = "partial"
            raise
        except OSError as exc:
            reason = issue_for(exc)
            note(reason, relative, child)
            # A failed iterator/fstat after traversal must not discard bytes
            # already collected from this directory.
            status = "partial" if started else failed_status(reason)
        finally:
            if own_child:
                finish_child(child, status)
            if progress is not None:
                progress(visited, total)
        return status

    status = "complete"
    if progress is not None:
        progress(0, 0)
    try:
        fd, name = open_parent(path)
        try:
            status = visit(fd, name, 0, ".")
        finally:
            os.close(fd)
    except LimitReached:
        status = "partial"
    except OSError as exc:
        reason = issue_for(exc)
        note(reason, ".", None)
        status = failed_status(reason)
    if status == "complete" and issues - {"hardlink"}:
        status = "partial"
    breakdown["children"] = [entry[3] for entry in sorted(largest, reverse=True)]
    return {"status": status, "bytes": total if status in ("complete", "partial") else None,
            "issues": sorted(issues), "measuredAt": int(time.time() * 1000), "entriesSeen": visited,
            "breakdown": breakdown, "skippedCounts": skipped_counts, "skippedSamples": skipped_samples}


def emit(record, stream):
    line = json.dumps(record, ensure_ascii=True, separators=(",", ":"))
    if len(line.encode("utf-8")) + 1 > MAX_LINE:
        raise ValueError("Protocol record exceeds output limit")
    stream.write(line + "\n")
    stream.flush()


def scan(env=None, stream=None, limits=None, clock=time.monotonic, application_dirs=None,
         rules=None, selected_id=None, custom_mappings=None):
    stream = sys.stdout if stream is None else stream
    if custom_mappings is None:
        from journal import read_settings
        try:
            custom_mappings = read_settings(env)["customMappings"]
        except (OSError, ValueError) as exc:
            raise SettingsError(bounded_text("Could not load custom mappings: " + str(exc), 1024)) from exc
    budget = Budget(limits or (DEEP_LIMITS if selected_id is not None else Limits()), clock)
    roots, directories = locations(env)
    apps = discover(directories if application_dirs is None else application_dirs, budget)
    inventory_complete = budget.inventory_complete
    # Ownership is resolved against the whole inventory before selecting an app.
    # A separate deep snapshot never consumes other apps' hardlink accounting.
    map_paths(apps, roots, budget, rules, custom_mappings)
    if selected_id is not None:
        apps = [app for app in apps if app["id"] == selected_id]
        if not apps:
            raise UnknownApp("Unknown selected application ID")
    # Keep inventory records at the original safe size. Measured breakdowns
    # travel individually, so a large app can never produce a giant app record.
    for app in apps:
        while len(json.dumps({"type": "app", "app": app}, ensure_ascii=True,
                             separators=(",", ":"))) + 1 > MAX_APP_RECORD and app["paths"]:
            app["paths"].pop()
            app["status"] = "partial"
            budget.warnings.add("limit")
    emit({"type": "begin", "version": 3, "inventoryComplete": inventory_complete, "totalApps": len(apps),
          "totalPaths": sum(len(app["paths"]) for app in apps),
          "mode": "deep" if selected_id is not None else "overview",
          "targetId": selected_id if selected_id is not None else ""}, stream)
    for app in apps:
        emit({"type": "app", "app": app}, stream)

    remaining = {app["id"]: len(app["paths"]) for app in apps}
    last_progress = float("-inf")

    def report(app, item, entries, size):
        nonlocal last_progress
        now = clock()
        # One global throttle also bounds events when thousands of tiny roots
        # finish quickly; per-root start events would exceed the stream limit.
        if now - last_progress >= PROGRESS_INTERVAL:
            emit({"type": "progress", "id": app["id"], "path": item["path"],
                  "entries": entries, "bytes": size}, stream)
            last_progress = now

    def finish(app):
        if app["paths"]:
            app["status"] = ("partial" if app["status"] == "partial"
                             or any(p["status"] != "complete" for p in app["paths"]) else "complete")
        app["scannedAt"] = int(time.time() * 1000)
        emit({"type": "appDone", "id": app["id"], "status": app["status"],
              "scannedAt": app["scannedAt"]}, stream)

    for app in apps:
        if not remaining[app["id"]]:
            finish(app)
    # Emit each known root promptly, while retaining global known hardlink
    # accounting. Possible/shared roots cannot consume that accounting.
    known_seen = set()
    for known in (True, False):
        for app in apps:
            for item in app["paths"]:
                if (item["confidence"] == "known") != known:
                    continue
                item.update(measure(item["path"], budget, known_seen if known else None,
                                    lambda entries, size: report(app, item, entries, size)))
                if known and item["bytes"] is not None:
                    app["categories"][item["category"]] += item["bytes"]
                    app["mappedBytes"] += item["bytes"]
                emit({"type": "path", "id": app["id"], "path": item}, stream)
                remaining[app["id"]] -= 1
                if not remaining[app["id"]]:
                    finish(app)
    emit({"type": "done", "scannedAt": int(time.time() * 1000),
          "limited": "limit" in budget.warnings, "warnings": sorted(budget.warnings)}, stream)
    return apps


def main():
    args = sys.argv[1:]
    selected_id = None
    if len(args) == 3 and args[:2] == ["scan", "--app"]:
        selected_id = args[2]
    elif args != ["scan"]:
        emit({"type": "error", "message": "Expected command: scan [--app EXACT.desktop]"}, sys.stdout)
        return 2
    # This exception must not be an OSError: traversal handles those locally,
    # whereas a watchdog expiration must terminate even a blocked filesystem.
    def timeout(_signum, _frame):
        raise ScanTimeout("Scanner wall-clock limit reached")
    signal.signal(signal.SIGALRM, timeout)
    signal.setitimer(signal.ITIMER_REAL, 100 if selected_id is not None else 35)
    try:
        scan(selected_id=selected_id)
        return 0
    except UnknownApp as exc:
        emit({"type": "error", "message": str(exc)}, sys.stdout)
        return 2
    except SettingsError as exc:
        emit({"type": "error", "message": str(exc)}, sys.stdout)
        return 1
    except BrokenPipeError:
        return 1
    except Exception:
        emit({"type": "error", "message": "Scan could not finish safely"}, sys.stdout)
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


if __name__ == "__main__":
    sys.exit(main())
