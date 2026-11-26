#!/usr/bin/env python3
"""One-shot local dashboard requests. Reads metadata; writes only private plugin state."""
import copy
import os
import signal
import sys
import time

import journal
import scanner
from installations import resolve_installations
from mappings import RULES, SOURCES

MAX_MESSAGE = 8 * 1024 * 1024
MAX_WARNINGS = 64
LEFTOVER_LIMITS = scanner.Limits(entries=20000, path_entries=5000, seconds=3.0,
                                 path_seconds=0.25, depth=32)
DISCOVERY_LIMITS = scanner.Limits(seconds=5.0)
MAPPING_LIMITS = scanner.Limits(seconds=5.0)


def empty_installations():
    return {"scannedAt": 0, "groups": [], "apps": [], "totalBytes": 0,
            "knownApps": 0, "unresolvedApps": 0, "issues": []}


def overlap(first, second):
    return first == second or first.startswith(second + "/") or second.startswith(first + "/")


def inventory(env=None):
    roots, directories = scanner.locations(env)
    budget = scanner.Budget(DISCOVERY_LIMITS)
    apps = scanner.discover(directories, budget)
    return roots, apps, budget.inventory_complete


def possible_leftovers(apps, roots, mappings, complete, mapping_complete=True, rules=None):
    """No launcher is evidence only, never a claim of uninstallation or safe deletion."""
    warnings = []
    if not complete:
        return [], ["Possible leftovers are unavailable because application discovery was incomplete."]
    if not mapping_complete:
        return [], ["Possible leftovers are unavailable because current application paths could not all be mapped."]
    rules = RULES if rules is None else rules
    installed = {app["id"] for app in apps}
    occupied = [item["path"] for app in apps for item in app["paths"]]
    candidates, seen = [], set()
    # Explicit assignments take precedence over a duplicate curated association.
    specifications = [(item["id"], item["path"], item["category"],
                       "Saved user assignment; ownership was not independently verified.")
                      for item in mappings if item["id"] not in installed]
    for stem, categories in rules.items():
        desktop = stem + ".desktop"
        if desktop in installed:
            continue
        for base, names in categories.items():
            for name in names:
                if base not in roots or not name or name.startswith("/") or any(p in ("", ".", "..") for p in name.split("/")):
                    continue
                specifications.append((desktop, os.path.join(roots[base], name), "data" if base == "home" else base,
                                       "Curated exact-desktop-ID mapping. " + SOURCES.get(stem, "")))
    for desktop, path, category, evidence in specifications:
        if path in seen or any(overlap(path, current) for current in occupied):
            continue
        seen.add(path)
        candidate = scanner.candidate(path, category, "known", "rule", roots["home"], evidence, "")
        if candidate is None:
            continue
        if any(overlap(path, current[1]) for current in candidates):
            continue
        if len(candidates) == 128:
            warnings.append("Possible leftovers were limited to 128 non-overlapping locations.")
            break
        candidates.append((desktop, path, category, evidence))
    budget = scanner.Budget(LEFTOVER_LIMITS)
    rows = []
    for desktop, path, category, evidence in candidates:
        measured = scanner.measure(path, budget)
        rows.append({"id": scanner.bounded_text(desktop, 256),
                     "name": scanner.bounded_text(desktop[:-8], 256), "path": path, "category": category,
                     "bytes": measured["bytes"], "status": measured["status"],
                     "reason": "No launcher found; this may still be used by a hidden, renamed, or command-line application.",
                     "evidence": scanner.bounded_text(evidence + " No matching desktop ID was present in a complete fresh inventory. "
                                                       "Absence does not prove uninstallation or that deleting data is safe.", 1024)})
    if "limit" in budget.warnings:
        warnings.append("Possible-leftover measurements reached their separate safety budget; partial sizes are lower bounds.")
    return rows, warnings


def _settings_patch(store, patch):
    journal.require(isinstance(patch, dict) and set(patch) <= {"historyEnabled", "alertsEnabled", "thresholdBytes"},
                    "Invalid settings patch")
    value = copy.deepcopy(store.settings)
    for name in ("historyEnabled", "alertsEnabled"):
        if name in patch:
            journal.require(type(patch[name]) is bool, "Settings toggles must be booleans")
    value.update(patch)
    if patch.get("historyEnabled") is False:
        value["alertsEnabled"] = False
    store.save_settings(value)


def _save_mapping(store, mapping, apps):
    validated = journal.validate_mapping(mapping, store.env, existing=True)
    existing = any((item["id"], item["path"]) == (validated["id"], validated["path"])
                   for item in store.settings["customMappings"])
    if not existing:
        journal.validate_mapping(validated, store.env)
    journal.require(any(app["id"] == validated["id"] for app in apps),
                    "Choose an application from the current installed launcher inventory")
    value = copy.deepcopy(store.settings)
    for index, current in enumerate(value["customMappings"]):
        if (current["id"], current["path"]) == (validated["id"], validated["path"]):
            value["customMappings"][index] = validated
            break
    else:
        value["customMappings"].append(validated)
    store.save_settings(value)


def _remove_mapping(store, desktop, path):
    journal.require(journal.desktop_id(desktop) and journal.absolute_path(path), "Invalid mapping identity")
    value = copy.deepcopy(store.settings)
    value["customMappings"] = [item for item in value["customMappings"] if (item["id"], item["path"]) != (desktop, path)]
    store.save_settings(value)


def _insights(history, current, rows, raw_snapshot=None):
    latest = current if current is not None and current["mode"] == "overview" else None
    if latest is None:
        overview = [snapshot for snapshot in history if snapshot["mode"] == "overview"]
        latest = overview[-1] if overview else None
    caches = []
    if raw_snapshot is not None and raw_snapshot["mode"] == "overview":
        for app in raw_snapshot["apps"]:
            paths = [path for path in app["paths"] if path["confidence"] == "known" and path["category"] == "cache"]
            if any(path["bytes"] is not None for path in paths):
                caches.append({"id": app["id"], "name": app["name"], "bytes": sum(path["bytes"] or 0 for path in paths),
                               "partial": app["status"] == "partial" or any(path["status"] != "complete" for path in paths)})
    elif latest:
        caches = [{"id": app["id"], "name": app["name"], "bytes": app["categories"]["cache"], "partial": app["partial"]}
                  for app in latest["apps"] if app["categories"]["cache"] > 0]
    growing = sorted((row for row in rows if row["comparable"] and row["delta"] > 0),
                     key=lambda row: (-row["delta"], -row["at"], row["id"], row["mode"]))[:512]
    return {"cache": sorted(caches, key=lambda app: (-app["bytes"], app["id"]))[:512], "growing": growing}


def _view(store, current=None, raw_snapshot=None, refreshed=False, notifications=None,
          installations=None, leftovers=None, warnings=None, overview=None):
    history = store.state["snapshots"]
    rows = journal.growth(history, current)
    value = {"version": 1, "refreshedAt": int(time.time() * 1000) if refreshed else 0,
             "settings": {key: store.settings[key] for key in ("historyEnabled", "alertsEnabled", "thresholdBytes")},
             "mappings": copy.deepcopy(store.settings["customMappings"]), "history": copy.deepcopy(history),
             "growth": rows, "insights": _insights(history, current, rows, overview if overview is not None else raw_snapshot),
             "leftovers": leftovers or [], "installations": installations if installations is not None else empty_installations(),
             "alerts": copy.deepcopy(store.state["alerts"]), "notifications": notifications or [],
             "warnings": [scanner.bounded_text(message, 1024) for message in (warnings or [])[:MAX_WARNINGS]]}
    journal.require(len(journal.encode({"ok": True, "data": value})) + 1 <= MAX_MESSAGE,
                    "Dashboard response exceeds its safe size limit; reduce custom mappings or clear retained history")
    return value


def _request(request):
    journal.require(isinstance(request, dict), "Request must be an object")
    op = request.get("op")
    fields = {"load": {"op"}, "view": {"op", "snapshot"}, "record": {"op", "snapshot", "overview"},
              "settings": {"op", "patch", "snapshot"}, "mapping-save": {"op", "mapping", "snapshot"},
              "mapping-remove": {"op", "id", "path", "snapshot"}, "clear-history": {"op"}}
    journal.require(isinstance(op, str) and op in fields and set(request) <= fields[op], "Unknown operation or request fields")
    journal.require(op != "record" or "snapshot" in request, "Recording requires a completed snapshot")
    current = journal.summarize(request["snapshot"]) if "snapshot" in request else None
    if "overview" in request:
        overview = journal.summarize(request["overview"])
        journal.require(overview["mode"] == "overview", "Insight overview must have overview scope")
    return op, current


def handle(request, env=None):
    """Return a real VIEW or raise JournalError. Intended for the one-shot CLI and isolated tests."""
    journal.require(len(journal.encode(request)) + 1 <= MAX_MESSAGE, "Request exceeds the safe size limit")
    op, current = _request(request)
    if op == "load":
        return _view(journal.Journal(env))
    if op == "view":
        store = journal.Journal(env)
        roots, apps, complete = inventory(env)
        installations = resolve_installations(apps, env=env)
        budget = scanner.Budget(MAPPING_LIMITS)
        scanner.map_paths(apps, roots, budget, custom_mappings=store.settings["customMappings"])
        leftovers, warnings = possible_leftovers(apps, roots, store.settings["customMappings"], complete,
                                                 "limit" not in budget.warnings and not any(a["status"] == "partial" for a in apps))
        return _view(store, current, request.get("snapshot"), True, installations=installations,
                     leftovers=leftovers, warnings=warnings)
    # Lock the entire mutation (including mapping-ID validation) so concurrent
    # processes cannot overwrite settings, replay alerts, or resurrect cleared history.
    with journal.transaction(env) as store:
        notifications, installations, leftovers, warnings = [], None, [], []
        if op == "settings":
            _settings_patch(store, request.get("patch"))
        elif op == "mapping-save":
            _, apps, _ = inventory(env)
            _save_mapping(store, request.get("mapping"), apps)
        elif op == "mapping-remove":
            _remove_mapping(store, request.get("id"), request.get("path"))
        elif op == "clear-history":
            store.state = {"version": 1, "snapshots": [], "alerts": []}
            store.save_history()
        elif op == "record":
            roots, apps, complete = inventory(env)
            installations = resolve_installations(apps, env=env)
            budget = scanner.Budget(MAPPING_LIMITS)
            scanner.map_paths(apps, roots, budget, custom_mappings=store.settings["customMappings"])
            leftovers, warnings = possible_leftovers(apps, roots, store.settings["customMappings"], complete,
                                                     "limit" not in budget.warnings and not any(a["status"] == "partial" for a in apps))
            notifications = store.record(current)
        return _view(store, current, request.get("snapshot"), op == "record", notifications, installations, leftovers, warnings,
                     overview=request.get("overview"))


def _timeout(signum, frame):
    raise journal.JournalError("Dashboard operation exceeded its safety time limit")


def main(stdin=None, stdout=None, env=None):
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    try:
        raw = stdin.readline(MAX_MESSAGE + 1)
        journal.require(bool(raw) and len(raw) <= MAX_MESSAGE, "Missing or oversized request line")
        # The process accepts one line; no framing, executable commands, or streaming operations.
        request = journal.decode(raw)
        result = {"ok": True, "data": handle(request, env)}
        status = 0
    except (ValueError, OSError, TypeError, KeyError, OverflowError, RecursionError) as exc:
        message = scanner.bounded_text(str(exc) or "Invalid dashboard request", 1024)
        result, status = {"ok": False, "error": message}, 1
    stdout.write(journal.encode(result).decode("ascii") + "\n")
    stdout.flush()
    return status


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, _timeout)
    signal.setitimer(signal.ITIMER_REAL, 45.0)
    try:
        sys.exit(main())
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
