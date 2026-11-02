"""Unit tests for the plasma-mosaic host layer (mosaic_host/mosaic_cli.py).

Covers the event accumulator (protocol semantics mirrored from upstream
Service.qml + Protocol.js), the known-byte aggregation invariant, ownership
identity enforcement, and summary computation. Engine suite lives in the
vendored tests copied from upstream (see PORT-NOTES.md).

Run:  cd plasma-mosaic && TMPDIR=/var/home/<user>/.hermes/cache/scratch \
      /usr/bin/python3 -m unittest tests/python/test_host_cli.py
(TMPDIR must be symlink-free: /home is a symlink on ostree hosts and the
vendored engine rejects symlinked locations.)
"""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic_host"
sys.path.insert(0, str(PROJECT))
SPEC = importlib.util.spec_from_file_location("mosaic_cli", PROJECT / "mosaic_cli.py")
cli = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = cli
SPEC.loader.exec_module(cli)


def pending(path, category="config", confidence="known"):
    return {"path": path, "label": path, "category": category, "confidence": confidence,
            "reason": "rule", "status": "pending", "bytes": None, "issues": [],
            "measuredAt": 0, "entriesSeen": 0, "evidence": "ev", "source": "",
            "breakdown": {"children": [], "directBytes": 0, "directFiles": 0,
                          "otherBytes": 0, "otherCount": 0},
            "skippedCounts": {}, "skippedSamples": []}


def measured(item, status="complete", **fields):
    result = dict(item)
    result["status"] = status
    result["measuredAt"] = 123
    result["entriesSeen"] = 2
    result.update(fields)
    return result


def app(app_id, paths, name=None):
    return {"id": app_id, "name": name or app_id, "icon": "", "paths": paths,
            "mappedBytes": 0, "categories": {"config": 0, "cache": 0, "data": 0, "state": 0},
            "status": "pending", "scannedAt": 0}


def event_stream(events):
    for event in events:
        yield (json.dumps(event, separators=(",", ":")) + "\n").encode()


class AccumulateTests(unittest.TestCase):
    def test_overview_accumulation_and_totals(self):
        a = app("one.desktop", [pending("/x/a", "config"),
                                pending("/x/b", "cache", confidence="possible")])
        b = app("two.desktop", [pending("/x/c", "data")])
        stream = event_stream([
            {"type": "begin", "version": 3, "inventoryComplete": True, "totalApps": 2,
             "totalPaths": 3, "mode": "overview", "targetId": ""},
            {"type": "app", "app": a},
            {"type": "app", "app": b},
            {"type": "path", "id": "one.desktop",
             "path": measured(a["paths"][0], bytes=100)},
            {"type": "path", "id": "one.desktop",
             "path": measured(a["paths"][1], bytes=40)},
            {"type": "appDone", "id": "one.desktop", "status": "complete", "scannedAt": 5},
            {"type": "path", "id": "two.desktop",
             "path": measured(b["paths"][0], bytes=7)},
            {"type": "appDone", "id": "two.desktop", "status": "complete", "scannedAt": 5},
            {"type": "done", "scannedAt": 9, "limited": False, "warnings": []},
        ])
        apps, meta = cli.accumulate(stream, "overview")
        self.assertEqual([x["id"] for x in apps], ["one.desktop", "two.desktop"])  # size desc
        self.assertEqual(apps[0]["mappedBytes"], 100)  # possible bytes excluded
        self.assertEqual(apps[0]["categories"], {"config": 100, "cache": 0, "data": 0, "state": 0})
        self.assertEqual(meta["scannedAt"], 9)
        self.assertEqual(meta["paths"], {"completed": 3, "total": 3})

    def test_unknown_confidence_bytes_do_not_sum(self):
        item = pending("/x/a", "config", confidence="shared")
        a = app("one.desktop", [item])
        stream = event_stream([
            {"type": "begin", "version": 3, "inventoryComplete": True, "totalApps": 1,
             "totalPaths": 1, "mode": "overview", "targetId": ""},
            {"type": "app", "app": a},
            {"type": "path", "id": "one.desktop", "path": measured(item, bytes=999)},
            {"type": "appDone", "id": "one.desktop", "status": "complete", "scannedAt": 5},
            {"type": "done", "scannedAt": 9, "limited": False, "warnings": []},
        ])
        apps, _ = cli.accumulate(stream, "overview")
        self.assertEqual(apps[0]["mappedBytes"], 0)

    def test_ownership_identity_change_rejected(self):
        a = app("one.desktop", [pending("/x/a")])
        changed = measured(a["paths"][0], bytes=5)
        changed["reason"] = "other"
        with self.assertRaises(RuntimeError):
            cli.replace_path(a, changed)

    def test_repeated_location_rejected(self):
        a = app("one.desktop", [pending("/x/a")])
        once = cli.replace_path(a, measured(a["paths"][0], bytes=5))
        with self.assertRaises(RuntimeError):
            cli.replace_path(once, measured(a["paths"][0], bytes=6))

    def test_missing_done_rejected(self):
        a = app("one.desktop", [])
        stream = event_stream([
            {"type": "begin", "version": 3, "inventoryComplete": True, "totalApps": 1,
             "totalPaths": 0, "mode": "overview", "targetId": ""},
            {"type": "app", "app": a},
            {"type": "appDone", "id": "one.desktop", "status": "unmapped", "scannedAt": 5},
        ])
        with self.assertRaises(RuntimeError):
            cli.accumulate(stream, "overview")

    def test_deep_mode_targets_identity(self):
        a = app("one.desktop", [pending("/x/a")])
        stream = event_stream([
            {"type": "begin", "version": 3, "inventoryComplete": True, "totalApps": 1,
             "totalPaths": 1, "mode": "deep", "targetId": "one.desktop"},
            {"type": "app", "app": a},
            {"type": "path", "id": "one.desktop", "path": measured(a["paths"][0], bytes=3)},
            {"type": "appDone", "id": "one.desktop", "status": "complete", "scannedAt": 5},
            {"type": "done", "scannedAt": 9, "limited": True, "warnings": ["limit"]},
        ])
        apps, meta = cli.accumulate(stream, "deep", "one.desktop")
        self.assertEqual(apps[0]["mappedBytes"], 3)
        self.assertTrue(meta["limited"])
        with self.assertRaises(RuntimeError):
            cli.accumulate(stream, "deep", "other.desktop")

    def test_error_event_raises(self):
        stream = event_stream([{"type": "error", "message": "boom"}])
        with self.assertRaises(RuntimeError):
            cli.accumulate(stream, "overview")


class SummarizeTests(unittest.TestCase):
    def test_summary(self):
        apps = [
            {"mappedBytes": 10, "categories": {"config": 4, "cache": 6, "data": 0, "state": 0},
             "status": "complete"},
            {"mappedBytes": 5, "categories": {"config": 5, "cache": 0, "data": 0, "state": 0},
             "status": "partial"},
        ]
        summary = cli.summarize(apps)
        self.assertEqual(summary["bytes"], 15)
        self.assertEqual(summary["categories"]["config"], 9)
        self.assertEqual(summary["completed"], 2)  # upstream: completed = finished (non-pending); partial still finished
        self.assertTrue(summary["partial"])


class PathValidationTests(unittest.TestCase):
    def test_rejects_relative_and_traversal(self):
        for bad in ("relative/path", "/a/../b", "/a/..", "", "/x" * 3000):
            with self.assertRaises(ValueError):
                cli.validated_path(bad)

    def test_accepts_absolute(self):
        self.assertEqual(cli.validated_path("/home/x/y"), "/home/x/y")


class SnapshotIOTests(unittest.TestCase):
    def test_snapshot_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {"XDG_CONFIG_HOME": f"{tmp}/cfg", "XDG_STATE_HOME": f"{tmp}/state",
                   "HOME": tmp, "PATH": "/usr/bin:/bin"}
            envelope = {"version": 1, "apps": [], "summary": {"bytes": 0}, "meta": {}}
            cli.write_snapshot(env, envelope)
            path = cli.snapshot_path(env)
            self.assertEqual(path.read_text().strip(), '{"version":1,"apps":[],"summary":{"bytes":0},"meta":{}}')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
