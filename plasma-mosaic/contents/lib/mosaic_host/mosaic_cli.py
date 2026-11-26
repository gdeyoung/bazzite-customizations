#!/usr/bin/env python3
"""plasma-mosaic host orchestration layer.

Wraps the vendored Mosaic engine (contents/lib/mosaic, byte-identical to
naolselemon/mosaic v0.1.1 backend) for Plasma's executable dataengine:
each subcommand is one process, prints ONE strict JSON line on stdout.

Commands (all output: compact JSON + newline, exit 0 on success):
  scan              overview scan -> snapshot cached to XDG state, journalized,
                    snapshot envelope printed at completion
  deep <appid>      deeper scan of one app (never replaces the overview cache)
  snapshot          print the cached overview snapshot (or {"empty": true})
  status            {"busy": bool, "scannedAt": ms, "generation": n}
  progress          {"busy": bool, "completed": n, "total": n, "path": str}
  workspace <json>  one-shot passthrough to backend workspace.handle()
  open <path>       validated open-folder via backend actions.py (FileManager1)
  copy <path>       validated copy-to-clipboard via org.kde.klipper (busctl)

Engine modules are imported verbatim; this file adds no engine behavior.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parent / "mosaic"
if str(ENGINE) not in sys.path:
    sys.path.insert(0, str(ENGINE))

import journal  # noqa: E402  (vendored engine, sibling import path set above)
import scanner  # noqa: E402
import workspace  # noqa: E402

CATEGORIES = ("config", "cache", "data", "state")
MAX_LINE = 1 << 20
SCAN_TIMEOUT = 130          # scanner self-alarms at 35s (overview) / 100s (deep)
DEEP_TIMEOUT = 140
SNAPSHOT_NAME = "plasma-snapshot.json"
LOCK_NAME = "plasma-scan.lock"


def out(record):
    sys.stdout.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def state_dir(env):
    config_root, state_root = journal.paths(env)
    path = Path(state_root)
    path.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path, 0o700)  # journal enforces private plugin storage (0700)
    except OSError:
        pass
    return path


def lock_path(env):
    return state_dir(env) / LOCK_NAME


def snapshot_path(env):
    return state_dir(env) / SNAPSHOT_NAME


def lock_held(env):
    """True if a live scan process owns the lock (cmdline check; zombies read empty)."""
    try:
        pid = int(lock_path(env).read_text().strip())
    except (OSError, ValueError):
        return False
    if pid == os.getpid():
        return True
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            cmdline = handle.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return False
    return "python" in cmdline


def acquire_lock(env):
    path = lock_path(env)
    if lock_held(env):
        return False
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, str(os.getpid()).encode())
    os.close(fd)
    return True


def release_lock(env):
    try:
        if lock_held(env):
            os.unlink(lock_path(env))
    except OSError:
        pass


def with_paths(app, paths):
    """Mirror of upstream Protocol.withPaths: recompute known-byte totals."""
    totals = {key: 0 for key in CATEGORIES}
    total = 0
    for path in paths:
        if path.get("confidence") == "known" and path.get("bytes") is not None:
            totals[path["category"]] += path["bytes"]
            total += path["bytes"]
    app["paths"] = paths
    app["categories"] = totals
    app["mappedBytes"] = total
    return app


def replace_path(app, measured):
    """Mirror of upstream Protocol.replacePath: in-place index replacement
    with ownership-identity verification."""
    index = -1
    for position, path in enumerate(app.get("paths", [])):
        if path.get("path") == measured.get("path"):
            index = position
    if index < 0 or app["paths"][index].get("status") != "pending":
        raise RuntimeError("unknown or repeated location")
    original = app["paths"][index]
    for field in ("category", "confidence", "reason", "evidence", "source"):
        if original.get(field) != measured.get(field):
            raise RuntimeError("location ownership changed")
    paths = list(app["paths"])
    paths[index] = measured
    return with_paths(app, paths)


def summarize(apps):
    totals = {key: 0 for key in CATEGORIES}
    total = 0
    completed = 0
    partial = False
    for app in apps:
        total += app.get("mappedBytes", 0)
        for key in CATEGORIES:
            totals[key] += app.get("categories", {}).get(key, 0)
        if app.get("status") != "pending":
            completed += 1
        if app.get("status") in ("partial", "pending"):
            partial = True
    return {"bytes": total, "categories": totals, "completed": completed, "partial": partial}


def accumulate(stream, mode, target_id=""):
    """Mirror of upstream Service.qml receive(): strict event-order accounting."""
    records, order = {}, []
    began = saw_done = False
    done = None
    expected_apps = inventory_paths = completed_paths = 0
    finished = set()
    last_path = ""
    for raw in stream:
        line = raw.decode("utf-8", "replace").strip()
        if not line:
            continue
        event = json.loads(line)
        kind = event.get("type")
        if kind == "error":
            raise RuntimeError(event.get("message", "scanner error"))
        if kind == "begin":
            if began or event.get("mode") != mode or event.get("targetId", "") != target_id:
                raise RuntimeError("scan identity mismatch")
            began = True
            expected_apps = event["totalApps"]
            inventory_paths = 0
            completed_paths = 0
        elif kind == "app":
            app = event["app"]
            if app["id"] in records or app["id"] in finished:
                raise RuntimeError("inventory identity mismatch")
            order.append(app["id"])
            records[app["id"]] = app
            inventory_paths += len(app.get("paths", []))
        elif kind == "path":
            record = records.get(event["id"])
            if record is None or event["id"] in finished:
                raise RuntimeError("path event for unknown or finished app")
            records[event["id"]] = replace_path(record, event["path"])
            completed_paths += 1
            last_path = event["path"].get("path", "")
        elif kind == "appDone":
            record = records.get(event["id"])
            if record is None or event["id"] in finished:
                raise RuntimeError("appDone for unknown or finished app")
            record["status"] = event["status"]
            record["scannedAt"] = event["scannedAt"]
            finished.add(event["id"])
        elif kind == "done":
            if (len(order) != expected_apps or completed_paths != inventory_paths
                    or len(finished) != expected_apps):
                raise RuntimeError("incomplete snapshot")
            saw_done = True
            done = event
    if not saw_done:
        raise RuntimeError("scanner stream ended without done")
    done_event = done
    apps = [records[app_id] for app_id in order]
    apps.sort(key=lambda a: (-a.get("mappedBytes", 0), a.get("name", "").lower()))
    return apps, {"scannedAt": done_event["scannedAt"], "limited": done_event.get("limited", False),
                  "warnings": done_event.get("warnings", []), "inventoryComplete": True,
                  "paths": {"completed": completed_paths, "total": inventory_paths}}


def write_snapshot(env, envelope):
    path = snapshot_path(env)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".snapshot-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(envelope, handle, ensure_ascii=True, separators=(",", ":"))
            handle.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def run_scan(env, mode, target_id=""):
    if not acquire_lock(env):
        out({"busy": True})
        return 0
    try:
        args = [sys.executable, "-B", str(ENGINE / "scanner.py"), "scan"]
        if mode == "deep":
            args += ["--app", target_id]
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                env=env, cwd=str(ENGINE))
        try:
            apps, meta = accumulate(proc.stdout, mode, target_id)
        finally:
            proc.stdout.close()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        envelope = {"version": 1, "mode": mode, "targetId": target_id, "apps": apps,
                    "summary": summarize(apps), "meta": meta}
        try:
            workspace.handle({"op": "record", "snapshot": {
                "mode": mode, "targetId": target_id, "scannedAt": meta["scannedAt"],
                "inventoryComplete": True, "limited": meta["limited"],
                "partial": meta["limited"] or bool(apps) and apps[0].get("status") != "complete",
                "apps": [apps[0]] if mode == "deep" and apps else apps}}, env)
        except Exception as error:  # history is best-effort; never fail the scan
            envelope["historyError"] = str(error)[:256]
        if mode == "overview":
            write_snapshot(env, envelope)
        out(envelope)
        return 0
    except Exception as error:
        out({"error": str(error)[:512]})
        return 1
    finally:
        release_lock(env)


def cmd_snapshot(env):
    path = snapshot_path(env)
    try:
        text = path.read_text()
        json.loads(text)
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
        return 0
    except (OSError, ValueError):
        out({"empty": True, "reason": "not scanned yet"})
        return 0


def cmd_status(env):
    busy = lock_held(env)
    scanned_at = 0
    try:
        scanned_at = json.loads(snapshot_path(env).read_text()).get("meta", {}).get("scannedAt", 0)
    except (OSError, ValueError):
        pass
    out({"busy": busy, "scannedAt": scanned_at})
    return 0


def cmd_progress(env):
    out({"busy": lock_held(env)})
    return 0


def cmd_workspace(env, payload):
    try:
        request = json.loads(payload)
        if not isinstance(request, dict) or "op" not in request:
            raise ValueError("expected a JSON object with an op")
        result = workspace.handle(request, env)
        out(result if result is not None else {"ok": True})
        return 0
    except Exception as error:
        out({"error": str(error)[:512]})
        return 1


def validated_path(raw):
    if not isinstance(raw, str) or not raw.startswith("/") or len(raw) > 4096 or "\0" in raw:
        raise ValueError("Invalid location")
    if ".." in Path(raw).parts:
        raise ValueError("Invalid location")
    return raw


def cmd_open(env, raw):
    try:
        validated_path(raw)
        result = subprocess.run([sys.executable, "-B", str(ENGINE / "actions.py"), raw],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=12)
        out({"opened": result.returncode == 0,
             "error": "" if result.returncode == 0 else result.stderr.decode()[:256]})
        return 0 if result.returncode == 0 else 1
    except Exception as error:
        out({"error": str(error)[:512]})
        return 1


def cmd_copy(env, raw):
    try:
        path = validated_path(raw)
        result = subprocess.run(
            ["busctl", "--user", "call", "org.kde.klipper", "/klipper",
             "org.kde.klipper.klipper", "setClipboardContents", "s", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=8)
        out({"copied": result.returncode == 0,
             "error": "" if result.returncode == 0 else result.stderr.decode()[:256]})
        return 0 if result.returncode == 0 else 1
    except Exception as error:
        out({"error": str(error)[:512]})
        return 1


def _heartbeat(command):
    """Liveness marker for the popup harness: written on every successful
    engine command. The UI only reaches success paths by invoking this CLI,
    so a fresh file proves the widget pulled data. Disable via MOSAIC_HB=0;
    relocate via MOSAIC_HB_PATH."""
    if os.environ.get("MOSAIC_HB", "1") == "0":
        return
    path = os.environ.get("MOSAIC_HB_PATH", "/tmp/plasma-mosaic-hb.json")
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": int(time.time() * 1000), "cmd": command}))
    except OSError:
        pass


def main():
    env = dict(os.environ)
    args = sys.argv[1:]
    if not args:
        out({"error": "usage: mosaic scan|deep <id>|snapshot|status|progress|workspace <json>|open <path>|copy <path>"})
        return 2
    command = args[0]
    rc = 2
    if command == "scan":
        rc = run_scan(env, "overview")
    elif command == "deep" and len(args) == 2:
        rc = run_scan(env, "deep", args[1])
    elif command == "snapshot":
        rc = cmd_snapshot(env)
    elif command == "status":
        rc = cmd_status(env)
    elif command == "progress":
        rc = cmd_progress(env)
    elif command == "workspace" and len(args) == 2:
        rc = cmd_workspace(env, args[1])
    elif command == "open" and len(args) == 2:
        rc = cmd_open(env, args[1])
    elif command == "copy" and len(args) == 2:
        rc = cmd_copy(env, args[1])
    else:
        out({"error": "unknown command or wrong argument count"})
    if rc == 0:
        _heartbeat(command)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
