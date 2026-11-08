#!/usr/bin/env python3
"""check-nav.py — full-coverage keyboard-nav QA (the user's minimum bar).

For EVERY view: every lens slot 0..n-1 must be reachable by a pure arrow
path (asserted against live navState after driving the path), ← from a
column-0 slot must land in the far-left rail, ↑ from row 0 must return to
the field, and ⏎ on the BackRow must return to boot (drill views).

Uses the same driveKey channel real keypresses take. Needs the daemon's
DBus session (inherits DBUS_SESSION_BUS_ADDRESS). Exit 0 = full coverage.
"""
import subprocess, sys

BC = ["busctl", "--user", "call", "gdeyoung.foyer", "/gdeyoung/foyer", "gdeyoung.foyer"]

def call(method, *args):
    r = subprocess.run(BC + [method] + list(args), capture_output=True, text=True, timeout=5)
    if r.returncode != 0:
        raise RuntimeError(f"{method}: {r.stderr.strip()}")
    return r.stdout.strip()

def nav():
    o = call("navState")
    if '"' in o: o = o.split('"')[1]
    p = o.split()
    return {"state": p[0], "zone": p[1], "i": int(p[2]), "n": int(p[3]),
            "cols": int(p[4]), "rail": int(p[5])}

def key(k): call("driveKey", "s", k)
def drive(s): call("driveState", "s", s)

def reset_to_entry(v):
    """Deterministic entry point: field → down → lens at the entry slot."""
    drive(v)
    st = nav()
    if st["zone"] == "rail":
        key("right"); st = nav()
    if st["zone"] == "lens":
        for _ in range(st["i"] // st["cols"] + 1):
            key("up")
    st = nav()
    if st["zone"] != "field":
        raise RuntimeError(f"{v}: could not reach field zone ({st})")
    key("down")
    st = nav()
    if st["state"] != v or st["zone"] != "lens":
        raise RuntimeError(f"{v}: entry failed ({st})")
    return st

def path_to(cur, target, cols):
    cc, ct = cur % cols, target % cols
    moves = []
    if ct > cc: moves += ["right"] * (ct - cc)
    elif ct < cc: moves += ["left"] * (cc - ct)
    rows = (target // cols) - (cur // cols)
    if rows > 0: moves += ["down"] * rows
    elif rows < 0: moves += ["up"] * (-rows)
    return moves

VIEWS = ["boot", "games", "typed", "nomatch", "ai", "ready", "system", "fleet",
         "ssh", "update", "settings", "help", "about",
         "favs", "recents", "snippets"]
# stream is transient (auto-advances to ready after 2.6 s) — smoke only.
DRILLS = {"games", "ai", "system", "fleet", "ssh", "update", "settings",
          "help", "about", "favs", "recents", "snippets", "ready"}

fails, checked = [], 0
for v in VIEWS:
    st = reset_to_entry(v)
    n, cols = st["n"], st["cols"]
    for s in range(n):
        checked += 1
        st = reset_to_entry(v)
        for m in path_to(st["i"], s, cols):
            key(m)
        st = nav()
        if st["state"] != v or st["zone"] != "lens" or st["i"] != s:
            fails.append(f"{v}: slot {s}/{n} UNREACHABLE (ended {st})")
            break
    # ← from a col-0 slot lands in the far-left rail
    st = reset_to_entry(v)
    for m in path_to(st["i"], (st["i"] // cols) * cols, cols):
        key(m)
    key("left"); st = nav()
    if st["zone"] != "rail":
        fails.append(f"{v}: ← did not reach the rail ({st})")
    else:
        checked += 1
    key("right")
    # ↑ from row 0 returns to the field
    st = reset_to_entry(v)
    for m in path_to(st["i"], st["i"] % cols, cols):
        key(m)
    key("up"); st = nav()
    if st["zone"] != "field":
        fails.append(f"{v}: ↑ from row 0 did not reach the field ({st})")
    else:
        checked += 1
    key("down")
    # ⏎ on BackRow returns to boot (drill views)
    if v in DRILLS:
        st = reset_to_entry(v)
        for m in path_to(st["i"], 0, cols):
            key(m)
        key("enter"); st = nav()
        if st["state"] != "boot":
            fails.append(f"{v}: ⏎ on BackRow did not return to boot ({st})")
        else:
            checked += 1

# stream smoke: entry + rail escape work inside its 2.6 s window
drive("stream")
st = nav()
if st["state"] in ("stream", "ready"):
    key("left"); st = nav()
    if st["zone"] == "rail":
        checked += 1
    else:
        fails.append(f"stream: ← did not reach the rail ({st})")

print(f"nav coverage: {checked} checks, {len(fails)} failures")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
