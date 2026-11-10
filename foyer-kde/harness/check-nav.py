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

def dbus_prop(prop):
    """Read a bridge value over the user bus via its getter slot
    (Qt property export yields a duplicate introspection interface,
    so tests call getUpdateOut/getFleetJson instead)."""
    slot = "getUpdateOut" if prop == "updateOut" else "getFleetJson"
    o = subprocess.run(
        ["busctl", "--user", "call", "gdeyoung.foyer",
         "/gdeyoung/foyer", "gdeyoung.foyer", slot],
        capture_output=True, text=True).stdout.strip()
    # busctl prints `s "escaped"`; JSON payloads embed quotes, so the old
    # split('"')[1] truncation mangled them — shlex unescapes correctly.
    import shlex
    try:
        parts = shlex.split(o)
        return parts[1] if len(parts) > 1 else ""
    except ValueError:
        return ""


def dbus_str(method):
    """Decode a busctl str return ('s "payload"' -> payload)."""
    o = call(method)
    if '"' not in o:
        return o.strip()
    return json.loads(o.split(None, 1)[1].strip())

import os

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
         "typed", "nomatch", "ai", "ready", "system", "fleet",
         "ssh", "update", "settings", "help", "about",
         "favs", "recents", "snippets"]
DRILLS = {"category:Internet", "category:Games", "category:Utilities",
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

# ---- settings modules: Kickoff parity -------------------------------------
# kcm_*.desktop are 83/84 NoDisplay=true; Foyer must still surface them in
# search ("auto start" → Autostart settings page) and offer the Settings
# bucket in the apps view. Owner report 2026-11-10: typed "auto start" in
# Foyer found nothing while Kickoff jumped straight to the Autostart KCM.
drive("boot")
for ch in "auto start":
    key(ch)
st = nav()
check(st["state"] == "typed" and st["n"] >= 1,
      f"search 'auto start': settings module not offered ({st})")
if st["state"] == "typed" and st["n"] >= 1:
    key("down")                        # slot 0 = top hit (starts-with rank)
    if HARNESS_MODE == "1" and nav()["zone"] == "lens" and nav()["i"] == 0:
        log0 = json.loads(dbus_str("launchLog") or "[]")
        key("enter")
        log1 = json.loads(dbus_str("launchLog") or "[]")
        check(len(log1) == len(log0) + 1
              and log1[-1].endswith("kcm_autostart.desktop"),
              f"search 'auto start': ⏎ did not launch the Autostart KCM "
              f"({log1[-1:]})")
for _ in range(11):
    key("backspace")

# Settings bucket is browsable: category view with real kcm entries
drive("category:Settings")
st = nav()
check(st["state"] == "category" and st["cat"] == "Settings" and st["n"] >= 20,
      f"Settings bucket: not browsable as category ({st})")

# NoDisplay non-kcm entries stay HIDDEN (seeded zqhidden.desktop)
drive("boot")
for ch in "zqhidden":
    key(ch)
st = nav()
check(st["state"] == "nomatch",
      f"NoDisplay leak: seeded hidden app matched in search ({st})")
for _ in range(8):
    key("backspace")

# ranking guard (CC r63): true-prefix beats spaceless-prefix —
# "visualstudio" must put Visualstudio Ninja ABOVE Visual Studio Code
drive("boot")
for ch in "visualstudio":
    key(ch)
st = nav()
check(st["state"] == "typed" and st["n"] >= 2,
      f"search 'visualstudio': expected 2+ ranked hits ({st})")
if st["state"] == "typed" and st["n"] >= 2 and HARNESS_MODE == "1":
    key("down")
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("enter")
    log1 = json.loads(dbus_str("launchLog") or "[]")
    check(len(log1) == len(log0) + 1
          and log1[-1].endswith("visualstudio-ninja.desktop"),
          f"ranking: true-prefix did not outrank spaceless-prefix "
          f"({log1[-1:]})")
for _ in range(12):
    key("backspace")

# ---- live lanes: ssh/system/update/recents/fleet ------------------------
# ssh view is fed by the REAL ~/.ssh/config parse (16 hosts on this machine)
drive("ssh")
st = nav()
check(st["state"] == "ssh" and st["n"] >= 10,
      f"ssh: live alias list not loaded ({st})")
if HARNESS_MODE == "1" and st["n"] > 1:
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("down"); key("enter")            # slot 0 is BackRow -> boot
    drive("ssh"); key("down"); key("right"); key("enter")   # slot 1 = first host
    log1 = json.loads(dbus_str("launchLog") or "[]")
    check(len(log1) == len(log0) + 1 and log1[-1].startswith("ssh:"),
          f"ssh: ⏎ on host row did not record terminal ssh ({log1[-1:]})")

# system rows map to whitelisted session commands (harness records only)
if HARNESS_MODE == "1":
    # reversible lock fires at once; destructive poweroff arms a confirm
    drive("system")
    key("down"); key("right")                      # slot 1 = Lock
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("enter")
    log1 = json.loads(dbus_str("launchLog") or "[]")
    check(len(log1) == len(log0) + 1 and log1[-1] == "system:lock",
          f"system lock: ⏎ did not record system:lock ({log1[-1:]})")

    # destructive ⏎ arms the confirm strip: n=2, Cancel default (slot 0)
    drive("system")
    key("down")
    for _ in range(5):
        key("right")                               # slot 5 = Shut Down
    key("enter")
    st = nav()
    check(st["state"] == "system" and st["n"] == 2 and st["zone"] == "lens"
          and st["i"] == 0,
          f"system: shut-down ⏎ did not arm confirm w/ Cancel default ({st})")
    # Esc cancels and restores the full list
    key("escape")
    st = nav()
    check(st["state"] == "system" and st["n"] == 6,
          f"system: Esc did not cancel confirm / restore list ({st})")
    # re-arm, walk to Confirm, ⏎ fires; view disarms after
    for _ in range(5):
        key("right")
    key("enter")
    st = nav()
    check(st["n"] == 2 and st["i"] == 0,
          f"system: re-arm failed ({st})")
    key("right")                                   # Cancel -> Confirm
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("enter")
    log1 = json.loads(dbus_str("launchLog") or "[]")
    st = nav()
    check(len(log1) == len(log0) + 1 and log1[-1] == "system:poweroff",
          f"system: confirm ⏎ did not record poweroff ({log1[-1:]})")
    check(st["n"] == 6,
          f"system: confirm did not disarm back to the list ({st})")

# update: history row streams read-only rpm-ostree output into the view
# (harness only — a live run must not fetch repo metadata by itself)
if HARNESS_MODE == "1":
    drive("update")
    key("down"); key("down"); key("enter")   # slot 2 = Deployment history
    out = ""
    for _ in range(20):
        import time as _t; _t.sleep(0.25)
        out = dbus_prop("updateOut")
        if out and len(out) > 40:
            break
    check("ostree" in out.lower() or "harness" in out.lower(),
          f"update: no rpm-ostree output rendered ({out[:60]!r})")

# recents come from the real xbel (this machine has 200+ entries)
drive("recents")
st = nav()
check(st["n"] >= 5,
      f"recents: live recently-used list not loaded ({st})")

# fleet view: probe-on-open populates real UP/DOWN + a real timestamp
drive("fleet")
ok = ""
for _ in range(24):
    import time as _t; _t.sleep(0.25)
    fj = dbus_prop("fleetJson")
    if fj and '"stamp"' in fj:
        ok = fj; break
check(ok != "" and '"hosts"' in ok,
      "fleet: probe-on-open produced no fleetJson")

# ---- Loop-2: Ask Hermes streams a real (stubbed) answer ------------------
if HARNESS_MODE == "1":
    drive("typed")
    for ch in "zzqx":          # no app hits -> Ask row is slot 0
        key(ch)
    import time as _t
    _t.sleep(0.3)
    key("down")                # field -> lens 0 (Ask Hermes)
    key("enter")
    st = nav()
    check(st["state"] == "stream", f"ask: ⏎ on Ask row did not open stream ({st})")
    ai = ""
    for _ in range(40):
        _t.sleep(0.25)
        ai = json.loads(dbus_str("getAiState"))
        if ai["done"]:
            break
    check(ai["done"] and ai["len"] > 40,
          f"ask: stream did not land ({ai})")
    check(nav()["state"] == "ready",
          "ask: done stream did not auto-advance to ready")
    # ⏎ on Copy records the answer to the clipboard lane
    drive("ready")
    key("down"); key("right")          # slot 1 = Copy
    log0 = json.loads(dbus_str("launchLog") or "[]")
    key("enter")
    log1 = json.loads(dbus_str("launchLog") or "[]")
    check(len(log1) == len(log0) + 1 and log1[-1].startswith("clip:Hermes harness answer"),
          f"ask: ⏎ Copy did not record the answer ({log1[-1:]})")
    # Esc mid-stream cancels: partial text kept, done flips, no hang
    drive("typed")
    for ch in "qqxz":
        key(ch)
    import time as _t
    _t.sleep(0.25)
    key("down"); key("enter")            # ask again
    _t.sleep(0.2)                        # mid-stub (chunk 1 of 3)
    key("escape")
    ai2 = ""
    for _ in range(20):
        _t.sleep(0.25)
        ai2 = json.loads(dbus_str("getAiState"))
        if ai2["done"]:
            break
    check(ai2["done"] and ai2["len"] < 60,
          f"ask-cancel: Esc did not stop the stream early ({ai2})")

    # the question persists into RECENT QUESTIONS (questions only)
    drive("ai")
    st = nav()
    check(st["n"] >= 3, f"ask: recent question row missing ({st})")
    rq = os.path.expanduser("~/.local/share/foyer/recent-questions.json")
    check(os.path.exists(rq) and "zzqx" in open(rq).read(),
          "ask: question not persisted to recent-questions.json")

# ---- Loop-2: settings levers persist + apply live -------------------------
if HARNESS_MODE == "1":
    drive("settings")
    st = nav()
    check(st["n"] == 6, f"settings: rebuilt lever list wrong ({st})")
    c0 = json.loads(dbus_str("getConfig"))
    check(c0.get("card_scale") is None and c0.get("card_anchor") == "center",
          f"settings: harness config not at defaults ({c0.get('card_scale')}, {c0.get('card_anchor')})")
    key("down")
    key("right"); key("right")         # slot 2 = Opacity
    key("enter")                       # 100 -> 96
    c1 = json.loads(dbus_str("getConfig"))
    check(c1.get("card_opacity") == 96,
          f"settings: opacity ⏎ did not cycle ({c1.get('card_opacity')})")
    onDisk = json.load(open(os.path.expanduser("~/.config/foyer/config.json")))
    check(onDisk.get("card_opacity") == 96,
          "settings: lever change not persisted to config.json")
    key("down")                        # slot 3
    key("right"); key("right")         # slot 5 = Reset
    key("enter")
    c2 = json.loads(dbus_str("getConfig"))
    check(c2.get("card_opacity") == 100 and c2.get("card_scale") is None,
          f"settings: reset did not restore defaults ({c2.get('card_opacity')}, {c2.get('card_scale')})")
    check(c2["ai"].get("ask_exe"), "settings: reset wiped the AI config (must be kept)")

# ---- Loop-2: fuzzy lever actually changes search behavior -----------------
if HARNESS_MODE == "1":
    drive("settings")
    key("down")
    for _ in range(4):
        key("right")              # slot 4 = Fuzzy search
    key("enter")                  # off -> on
    c = json.loads(dbus_str("getConfig"))
    check(c.get("fuzzy") is True, f"fuzzy: lever did not toggle on ({c.get('fuzzy')})")
    drive("typed")
    for ch in "brv":              # subsequence — no substring hit
        key(ch)
    import time as _t; _t.sleep(0.3)
    st = nav()
    check(st["n"] >= 3,
          f"fuzzy: 'brv' produced no subsequence hits ({st})")
    key("escape") if st["state"] != "boot" else None
    drive("settings"); key("down")
    for _ in range(4):
        key("right")
    key("enter")                  # on -> off
    c = json.loads(dbus_str("getConfig"))
    check(c.get("fuzzy") is False, "fuzzy: lever did not toggle back off")

# real vs logical key channels must agree (sample)
for v in ("boot", "category:Internet"):
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

# ===== favorites: pin/unpin via ctrl+p, star rows, summon landing =====
import time as _ft

def favs():
    return json.loads(dbus_str("getFavsJson"))

def st():
    return nav()["state"]

# 1) typed "brav" -> first row is Brave -> ctrl+p pins it
drive("boot")
for ch in "brav":
    key(ch)
key("down")                       # lens 0 = Brave (typed rows: no back row)
key("ctrl+p")
f = favs()
check(len(f) == 1 and "Brave" in f[0]["name"],
      f"fav pin: ctrl+p did not pin Brave ({f})")

# 2) favorites view shows it; unpin via ctrl+p on the row
drive("favs")
check(st() == "favs", f"fav view: not in favs ({st()})")
key("down")                       # back row (slot 0)
key("down")                       # the Brave row
key("ctrl+p")
f = favs()
check(len(f) == 0, f"fav unpin: row still pinned ({f})")

# 3) summon lands on Favorites ALWAYS — empty state teaches pinning
drive("settings")
call("hideUI"); _ft.sleep(0.2); call("showUI"); _ft.sleep(0.2)
check(st() == "favs", f"summon with 0 favs should land on favs ({st()})")
# pin one again, then summon must land on favs
drive("boot")
for ch in "brav":
    key(ch)
key("down")
key("ctrl+p")
drive("settings")
call("hideUI"); _ft.sleep(0.2); call("showUI"); _ft.sleep(0.2)
check(st() == "favs", f"summon with favs should land on favs ({st()})")

# 3b) reorder: pin two more (Brave is still pinned from step 3), then
# ctrl+arrows move rows with focus following the moved row
for q_ in ("firef", "kons"):                # firefox, konsole
    drive("boot")
    for ch in q_:
        key(ch)
    key("down")
    key("ctrl+p")
f = favs()
check(len(f) == 3, f"reorder setup: expected 3 pins ({len(f)})")
if len(f) == 3:
    names0 = [r["name"] for r in f]
    drive("favs")
    key("down")                    # back row
    key("down")                    # first fav row
    st_ = nav()
    check(st_["state"] == "favs" and st_["i"] == 1 and st_["n"] == 4,
          f"reorder: focus not on first fav ({st_})")
    key("ctrl+down")               # move row 0 down
    f = favs()
    check([r["name"] for r in f] == [names0[1], names0[0], names0[2]],
          f"reorder: ctrl+down order wrong ({[r['name'] for r in f]})")
    st_ = nav()
    check(st_["i"] == 2, f"reorder: focus did not follow the row ({st_['i']})")
    key("ctrl+down")               # now last, must clamp
    f = favs()
    check([r["name"] for r in f] == [names0[1], names0[2], names0[0]],
          f"reorder: second ctrl+down wrong ({[r['name'] for r in f]})")
    check(nav()["i"] == 3, f"reorder: focus after second move ({nav()['i']})")
    key("ctrl+down")               # at bottom: swallowed, no change
    f2 = favs()
    check(len(f2) == 3 and nav()["i"] == 3,
          "reorder: bottom clamp moved something")
    key("ctrl+up"); key("ctrl+up") # walk back to top
    f = favs()
    check([r["name"] for r in f] == names0,
          f"reorder: ctrl+up x2 did not restore ({[r['name'] for r in f]})")
    check(nav()["i"] == 1, f"reorder: focus at top ({nav()['i']})")
    key("ctrl+up")                 # top: swallowed
    check(nav()["i"] == 1, "reorder: top clamp moved focus")

# 3c) single-item clamp: one pin cannot move at all
f = favs()
for _ in range(6):
    drive("favs")
    if nav()["n"] <= 1:
        break
    key("down"); key("down")
    key("ctrl+p")
if len(favs()) == 0:                      # ensure exactly one pin remains
    drive("boot")
    for ch in "brav":
        key(ch)
    key("down")
    key("ctrl+p")
drive("favs")
key("down"); key("down")                  # focus the only fav row
key("ctrl+down"); key("ctrl+up")
f = favs()
check(len(f) == 1, f"single-item clamp changed the list ({f})")
check(nav()["i"] == 1, f"single-item clamp moved focus ({nav()['i']})")

# 4) rail order: Favorites sits ABOVE Apps
drive("boot")                     # owner of boot is AP
key("left")                       # escape to rail
key("up")                         # next selectable above AP = FA
key("enter")                      # rail enter -> gotoState
check(st() == "favs", f"rail order: FA is not above AP ({st()})")

# 5) clean slate: unpin everything for the later drills
for _ in range(6):
    drive("favs")
    if nav()["n"] <= 1:             # back row only — empty
        break
    key("down"); key("down")
    key("ctrl+p")
f = favs()
check(len(f) == 0, f"fav cleanup failed ({f})")

# ===== warm-show latency: 20 summons, p99 < 150 ms (harness kwin) =====
import time as _wt
_samples = []
for _ in range(20):
    call("hideUI")
    _wt.sleep(0.15)
    call("showUI")
    ms = None
    for _ in range(40):          # up to 2 s
        _wt.sleep(0.05)
        st = json.loads(dbus_str("getShowMs"))
        if st["ms"] is not None:
            ms = st["ms"]
            break
    if ms is None:
        check(False, "warm-show: no frameShown sample")
        break
    _samples.append(ms)
call("hideUI")
if len(_samples) == 20:
    _samples.sort()
    p50 = _samples[9]
    p99 = _samples[18]           # 19th of 20; max held out as outlier
    mx = _samples[-1]
    print(f"    warm-show: p50={p50}ms p99={p99}ms max={mx}ms (harness kwin)")
    check(p99 < 150, f"warm-show p99 {p99}ms >= 150ms budget")

print(f"nav coverage: {checked} checks, {len(fails)} failures")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
