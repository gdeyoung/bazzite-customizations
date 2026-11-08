#!/usr/bin/env python3
"""Orphan sweeper for the tailfin harness (2026-11-08 incident fix).

NEVER kill by name/argv/pgid — the REAL plasmashell runs
`/usr/bin/plasmashell --no-respawn`, argv-identical to the harness
virtual shells. Kill ONLY processes whose OWN environ says they belong
to the harness (HOME=/tmp/stk-harness/home), excluding dbus-daemon
(the session bus must survive its clients).
"""
import os, signal, sys, time

ROOT = "/tmp/stk-harness"

def harness_owned(pid: int) -> bool:
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return False
    if exe.endswith("/dbus-daemon"):
        return False
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            env = f.read().decode(errors="replace").split("\0")
    except OSError:
        return False
    return f"HOME={ROOT}/home" in env

def sweep() -> int:
    killed = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == os.getpid() or pid == os.getppid():
            continue
        if harness_owned(pid):
            try:
                os.kill(pid, signal.SIGTERM)
                killed.append(pid)
            except OSError:
                pass
    return len(killed)

if __name__ == "__main__":
    n1 = sweep()
    time.sleep(2)
    n2 = sweep()  # escalate leftovers once
    # health report (read-only)
    import subprocess
    real = subprocess.run(["pgrep", "-x", "plasmashell"],
                          capture_output=True, text=True).stdout.split()
    unit = subprocess.run(["systemctl", "--user", "is-active",
                           "plasma-plasmashell"],
                          capture_output=True, text=True).stdout.strip()
    print(f"swept={n1}+{n2} real={real} unit={unit}")
    sys.exit(0 if unit == "active" and real else 1)
