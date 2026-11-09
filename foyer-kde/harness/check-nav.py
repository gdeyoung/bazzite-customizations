#!/usr/bin/env python3
"""check-nav.py — full-coverage keyboard-nav QA (the user's minimum bar).

Driven by driveKeyReal — REAL Qt key events delivered through the window's
focus object. That is the exact path a physical keypress takes (field
Keys-handlers, TextInput cursor logic, propagation). The old driveKey
(logical) channel is kept only as a cross-check that both paths agree.

Spec under test (user directives, 2026-11-08):
  * every lens slot 0..n-1 in every view reachable by arrows (↓/→ paths)
  * → from any slot lands on the NEXT option in reading order
  * ← from ANY slot (and from the field) jumps to the far-left rail
  * ↑ from row 0 returns to the field
  * ⏎ on the BackRow returns to boot (drill views)
  * rail ↓/↑ walks branches (live view switch), → returns to the options
  * every boot category tile opens ITS OWN category view (never a stand-in)
  * ⏎ on a category app row records a launch (harness records, never spawns)

Needs the daemon's DBus session. Exit 0 = full coverage.
"""
import json
import subprocess
import sys

BC = ["busctl", "--user", "call", "gdeyoung.foyer", "/gdeyoung/foyer",
      "gdeyoung.foyer"]

def call(method, *args):
    r = subprocess.run(BC + [method] + list(args),
                       capture_output=True, text=True, timeout=5)
    if r.returncode != 0:
        raise RuntimeError(f"{method}: {r.stderr.strip()}")
    return r.stdout.strip()

def nav():
    o = call("navState")
    if '"' in o:
        o = o.split('"')[1]
    p = o.split()
    return {"state": p[0], "zone": p[1], "i": int(p[2]), "n": int(p[3]),
            "cols": int(p[4]), "rail": int(p[5]), "cat": p[6] if len(p) > 6 else ""}

def key(k): call("driveKeyReal", "s", k)     # REAL key delivery path
def lkey(k): call("driveKey", "s", k)        # logical (cross-check only)
def drive(s): call("driveState", "s", s)

def dbus_str(method):
    """Decode a busctl str return ('s "payload"' -> payload)."""
    o = call(method)
    if '"' not in o:
        return o.strip()
    return json.loads(o.split(None, 1)[1].strip())

fails, checked = [], 0

def check(cond, msg):
    global checked
    if cond:
        checked += 1
    else:
        fails.append(msg)

def reset_to_entry(v):
    """Deterministic: enter view, land in lens at its entry slot."""
    base = v.split(":")[0]
    drive(v)
    st = nav()
    if st["zone"] == "rail":
        key("right")
        st = nav()
    if st["zone"] == "lens":
        for _ in range(st["n"] + 2):       # walk rows up until the field
            key("up")
            st = nav()
            if st["zone"] != "lens":
                break
    st = nav()
    if st["zone"] != "field":
        raise RuntimeError(f"{v}: could not reach field zone ({st})")
    key("down")
    st = nav()
    if st["state"] != base or st["zone"] != "lens":
        raise RuntimeError(f"{v}: entry failed ({st})")
    return st

def goto_slot(v, s):
    """Enter v and walk (↓/→) to slot s; assert arrival."""
    base = v.split(":")[0]
    st = reset_to_entry(v)
    for _ in range(s - st["i"]):
        key("right")
    return nav(), base

VIEWS = ["boot", "category:Internet", "category:Games", "category:Utilities",
         "games", "typed", "nomatch", "ai", "ready", "system", "fleet",
         "ssh", "update", "settings", "help", "about",
         "favs", "recents", "snippets"]
DRILLS = {"category:Internet", "category:Games", "category:Utilities", "games",
          "ai", "system", "fleet", "ssh", "update", "settings", "help",
          "about", "favs", "recents", "snippets", "ready"}

for v in VIEWS:
    st = reset_to_entry(v)
    n = st["n"]
    for s in range(n):
        st, base = goto_slot(v, s)
        check(st["state"] == base and st["zone"] == "lens" and st["i"] == s,
              f"{v}: slot {s}/{n} UNREACHABLE (ended {st})")
        if st["i"] != s or st["zone"] != "lens":
            break
        # → next option in reading order
        if s < n - 1:
            key("right")
            st = nav()
            check(st["zone"] == "lens" and st["i"] == s + 1,
                  f"{v}: → from slot {s} did not reach {s+1} ({st})")
        # ← from ANY slot jumps to the far-left rail — immediately
        key("left")
        st = nav()
        check(st["zone"] == "rail",
              f"{v}: ← from slot {s} did not reach the rail ({st})")
        key("right")          # back into the options for the next iteration
        st = nav()
        check(st["zone"] == "lens",
              f"{v}: → from rail did not re-enter the options ({st})")
    # ← from the FIELD reaches the rail too (empty fields escape at once;
    # text fields walk the caret to start first — press enough times)
    st = reset_to_entry(v)
    key("up")
    st = nav()
    if st["zone"] == "field":
        for _ in range(40):
            key("left")
            if nav()["zone"] == "rail":
                break
        st = nav()
        check(st["zone"] == "rail",
              f"{v}: ← from the field did not reach the rail ({st})")
        key("right")
    # ↑ from row 0 returns to the field
    st = reset_to_entry(v)
    key("up")
    st = nav()
    check(st["zone"] == "field",
          f"{v}: ↑ from row 0 did not reach the field ({st})")
    key("down")
    # ⏎ on the BackRow returns to boot (drill views). Entry lands ON the
    # BackRow (slot 0) since ↓ from the field enters at slot 0 — so only
    # step up first in multi-column views whose entry is column 1.
    if v in DRILLS:
        st = reset_to_entry(v)
        if st["zone"] == "lens" and st["i"] != 0:
            key("up")
            st = nav()
        if st["zone"] == "lens" and st["i"] == 0:
            key("enter")
            st = nav()
            check(st["state"] == "boot" and st["zone"] == "lens",
                  f"{v}: ⏎ on BackRow did not return to boot ({st})")

# rail: ↓ walks branches (live switch), ↑ walks back
drive("boot")
st = nav()
while st["zone"] != "rail":
    key("left")
    st = nav()
key("down")
st = nav()
check(st["zone"] == "rail" and st["state"] != "boot",
      f"rail: ↓ did not walk to the next branch ({st})")
key("up")
st = nav()
check(st["state"] == "boot",
      f"rail: ↑ did not walk back to boot ({st})")
key("right")
st = nav()
check(st["zone"] == "lens",
      f"rail: → did not re-enter the options ({st})")

# every boot category tile opens ITS OWN view — Internet must not be games
HARNESS_MODE = dbus_str("harnessMode")
drive("boot")
key("down")
st = nav()
ncat = st["n"]
for s in range(ncat):
    drive("boot")
    key("down")
    for _ in range(s):
        key("right")
    key("enter")
    st = nav()
    check(st["state"] == "category" and st["cat"] != "",
          f"boot tile {s}: ⏎ did not open its own category view ({st})")
    check(st["state"] != "games",
          f"boot tile {s}: opened games stand-in ({st})")
    if st["state"] != "category":
        break
    # inside (HARNESS ONLY): ⏎ on the first app row records a launch —
    # never pressed against a live daemon (it would launch real apps)
    if st["n"] > 1 and HARNESS_MODE == "1":
        log0 = json.loads(dbus_str("launchLog") or "[]")
        key("right")            # slot 1 = first app
        key("enter")
        log1 = json.loads(dbus_str("launchLog") or "[]")
        check(len(log1) == len(log0) + 1 and log1[-1].endswith(".desktop"),
              f"category {st['cat']}: ⏎ on app row did not record a "
              f"desktop-file launch ({log1[-1] if log1 else 'none'})")

# live search: type "brave" through REAL letter keys — the exact user path
# that found nothing when the field still queried the frozen demo index
drive("boot")
for ch in "br":
    key(ch)
st = nav()
check(st["state"] == "typed" and st["n"] >= 3,
      f"search 'br': no live results offered ({st})")
for ch in "ave":
    key(ch)
st = nav()
check(st["state"] == "typed" and st["n"] >= 3,
      f"search 'brave': results vanished on full word ({st})")
# results are arrow-walkable like any list: ↓ enters slot 0, ← hits the rail
key("down")
st = nav()
check(st["zone"] == "lens" and st["i"] == 0,
      f"search 'brave': ↓ did not enter results ({st})")
key("left")
st = nav()
check(st["zone"] == "rail",
      f"search 'brave': ← from result did not reach rail ({st})")
key("right")
# ⏎ on the first result launches a Brave desktop file (harness records only)
if HARNESS_MODE == "1" and nav()["zone"] == "lens" and nav()["i"] == 0:
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("enter")
    log1 = json.loads(dbus_str("launchLog") or "[]")
    check(len(log1) == len(log0) + 1 and "brave" in log1[-1].lower(),
          f"search 'brave': ⏎ did not launch brave ({log1[-1:]})")
# clearing the query returns to the menu
for _ in range(5):
    key("backspace")
st = nav()
check(st["state"] == "boot",
      f"search: clearing the query did not return to boot ({st})")

# real vs logical key channels must agree (sample)
for v in ("boot", "games", "category:Internet"):
    drive(v)
    key("down")
    key("right")
    real = nav()
    drive(v)
    lkey("down")
    lkey("right")
    logic = nav()
    check(real == logic,
          f"{v}: real-key and logical-key channels disagree ({real} vs {logic})")

print(f"nav coverage: {checked} checks, {len(fails)} failures")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
