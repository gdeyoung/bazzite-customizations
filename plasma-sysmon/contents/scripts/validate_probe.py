#!/usr/bin/env python3
"""Validate probe output: exactly one strict-JSON line with the expected shape.

Usage: validate_probe.py <probe-script> [--count N]
Runs the probe N times (default 3), fails on any parse error, wrong row
arity, non-numeric numerics, or control characters leaking into strings.
Gate before blaming QML when a model comes up empty (spec risk 9).
"""
import json
import subprocess
import sys

ROW = ["pid", "user", "comm", "pcpu", "pmem", "rss_kb", "state", "args"]


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: validate_probe.py <probe-script> [--count N]", file=sys.stderr)
        return 2
    script = sys.argv[1]
    count = 3
    if "--count" in sys.argv:
        count = int(sys.argv[sys.argv.index("--count") + 1])
    fails = 0
    for run in range(count):
        out = subprocess.run(["bash", script], capture_output=True, text=True, timeout=10)
        lines = [l for l in out.stdout.splitlines() if l.strip()]
        if out.returncode != 0:
            print(f"run {run}: exit {out.returncode}: {out.stderr[:200]}", file=sys.stderr)
            fails += 1
            continue
        if len(lines) != 1:
            print(f"run {run}: expected exactly 1 line, got {len(lines)}", file=sys.stderr)
            fails += 1
            continue
        try:
            data = json.loads(lines[0])
        except json.JSONDecodeError as e:
            print(f"run {run}: JSON parse error: {e}", file=sys.stderr)
            fails += 1
            continue
        procs = data.get("procs")
        if not isinstance(procs, list) or not procs:
            print(f"run {run}: no procs array", file=sys.stderr)
            fails += 1
            continue
        bad = 0
        for i, row in enumerate(procs):
            if len(row) != len(ROW):
                print(f"run {run}: row {i} arity {len(row)} != {len(ROW)}", file=sys.stderr)
                bad += 1
                break
            if not isinstance(row[0], int) or isinstance(row[0], bool):
                print(f"run {run}: row {i} pid not int: {row[0]!r}", file=sys.stderr)
                bad += 1
                break
            for j in (3, 4, 5):
                if not isinstance(row[j], (int, float)):
                    print(f"run {run}: row {i} field {ROW[j]} not numeric: {row[j]!r}", file=sys.stderr)
                    bad += 1
                    break
            if bad:
                break
            for j in (1, 2, 6, 7):
                if any(ord(ch) < 0x20 for ch in str(row[j])):
                    print(f"run {run}: row {i} field {ROW[j]} has control chars", file=sys.stderr)
                    bad += 1
                    break
            if bad:
                break
        if bad:
            fails += 1
            continue
        print(f"run {run}: OK {len(procs)} rows")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
