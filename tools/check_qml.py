#!/usr/bin/env python3
"""Static checker for user-level Plasma 6 ports (Bazzite/Kinoite).

Checks, per plasma-plasmoid-development skill (verified the hard way):
  metadata.json — KPackageStructure, KPlugin.Id, Min-Version >= 6.0,
                   no X-Plasma-StandAloneApp.
  QML files     — balanced braces/parens/brackets (string/comment aware),
                   no Plasma-5-only imports (PlasmaCore as dataengine source),
                   plasma5support imported unaliased + versioned,
                   Qt.resolvedUrl (not resolveUrl), duplicate signal handlers.
  probe scripts — optionally EXECUTE once read-only with --probe-run and
                   validate strict one-line JSON per tick.

Exit 0 = clean; exit 1 = errors found; warnings do not fail the run.
Usage:
  check_qml.py <plasmoid-dir> [--probe-run <script> ...]
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ERRORS, WARNINGS = [], []


def err(path, msg):
    ERRORS.append(f"{path}: {msg}")


def warn(path, msg):
    WARNINGS.append(f"{path}: {msg}")


def strip_qml_noise(text):
    """Replace comments, string literals, and regex literals with spaces so
    bracket counting cannot be fooled. (Does not attempt to understand QML
    LR grammar.) Regex literals matter: ``.replace(/^file:\\/\\//, "")``
    contains ``//`` which a naive comment scan truncates, dropping the
    closing paren and producing a phantom "unbalanced ()" (sysmon 2026-10-30).
    """
    out, i, n = [], 0, len(text)
    # A "/" opens a regex literal only in expression position: the previous
    # significant char is an operator/opening bracket (or start of input).
    # After an identifier, ")" or "]" a "/" must be division.
    last_sig = ""
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        elif c == "/" and (last_sig == "" or last_sig in "(,=:[!&|?{;+-*<>"):
            # regex literal: consume to the unescaped closing "/"
            i += 1
            while i < n and text[i] != "/":
                i += 2 if text[i] == "\\" else 1
            i += 1
            while i < n and text[i].isalpha():   # flags (g/i/s...)
                i += 1
            out.append(" ")
            last_sig = "/"
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
            out.append(" ")
        elif c == "'":
            i += 1
            while i < n and text[i] != "'":
                i += 2 if text[i] == "\\" else 1
            i += 1
            out.append(" ")
        else:
            out.append(c)
            if not c.isspace():
                last_sig = c
            i += 1
    return "".join(out)


def check_metadata(meta_path):
    try:
        meta = json.loads(meta_path.read_text())
    except Exception as e:
        err(meta_path, f"unparseable JSON: {e}")
        return None
    if meta.get("KPackageStructure") != "Plasma/Applet":
        err(meta_path, 'KPackageStructure must be "Plasma/Applet"')
    kplugin = meta.get("KPlugin", {})
    if not kplugin.get("Id"):
        err(meta_path, "KPlugin.Id missing")
    if not kplugin.get("Name"):
        err(meta_path, "KPlugin.Name missing")
    if not kplugin.get("Version"):
        warn(meta_path, "KPlugin.Version missing")
    if meta.get("X-Plasma-StandAloneApp"):
        err(meta_path, "X-Plasma-StandAloneApp makes a window app, not a widget")
    if meta.get("X-Plasma-API-Minimum-Version", "6.0") < "6.0":
        err(meta_path, "X-Plasma-API-Minimum-Version must be >= 6.0 "
                       "(without it the widget is silently hidden as Plasma-5-only)")
    return meta


def check_qml_file(qml_path, is_main, plugin_id):
    text = qml_path.read_text()
    stripped = strip_qml_noise(text)
    for open_c, close_c in (("{", "}"), ("(", ")"), ("[", "]")):
        if stripped.count(open_c) != stripped.count(close_c):
            err(qml_path, f"unbalanced {open_c}{close_c}: "
                          f"{stripped.count(open_c)} vs {stripped.count(close_c)}")
    for lineno, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if "org.kde.plasma.core" in s and "import" in s:
            warn(qml_path, f"L{lineno}: plasma.core import — Plasma 6 moved things; "
                           f"SVG frames live in org.kde.ksvg, DataSource in plasma5support")
        if "plasma5support" in s and "import" in s and " as " in s:
            err(qml_path, f"L{lineno}: plasma5support must be imported UNALIASED + versioned "
                          f"(aliased import resolves but the DataSource type is missing)")
        if "Qt.resolveUrl" in s:
            err(qml_path, f"L{lineno}: Qt.resolveUrl is a typo — Qt.resolvedUrl")
        if "X-Plasma-StandAloneApp" in s:
            err(qml_path, f"L{lineno}: X-Plasma-StandAloneApp does not belong in QML")
        if re.search(r"Kirigami\.Units\.smallRadius", s):
            err(qml_path, f"L{lineno}: Kirigami.Units.smallRadius is undefined — "
                          f"use Kirigami.Units.smallSpacing / 2")
        if re.search(r"Layout\.horizontalAlignment", s):
            err(qml_path, f"L{lineno}: Layout.horizontalAlignment does not exist in "
                          f"QtQuick.Layouts — use Text.horizontalAlignment")
        if "#" == s[:1] and re.match(r"^#[0-9a-fA-F]{3,8}\b", s[1:]):
            warn(qml_path, f"L{lineno}: hardcoded hex color — use theme colors")
    # Duplicate signal handlers on the SAME object -> "Property value set
    # multiple times" (the kill-applet lesson). Scoped per component: sibling
    # objects each declaring onClicked once is legal QML; two on ONE object
    # is the killer. File-level counting (pre-2026-10-30) flagged every file
    # with 3+ MouseAreas — sysmon v0.7 forced the fix.
    depth = 0
    stack = []           # per-object key: its id, or @depth.anon
    anon = 0
    seen = {}            # (object_key, handler) -> first lineno
    for lineno, line in enumerate(stripped.split("\n"), 1):
        events = []
        for hm in re.finditer(r"\b(on[A-Z]\w+)\s*[:{]", line):
            events.append((hm.start(), "h", hm.group(1)))
        for im in re.finditer(r"\bid\s*:\s*(\w+)", line):
            events.append((im.start(), "i", im.group(1)))
        for idx, ch in enumerate(line):
            if ch == "{" or ch == "}":
                events.append((idx, "b", ch))
        events.sort()
        for _, kind, val in events:
            if kind == "b" and val == "{":
                anon += 1
                depth += 1
                stack.append(f"@{depth}.{anon}")
            elif kind == "b" and val == "}":
                depth -= 1
                if stack:
                    stack.pop()
            elif kind == "i":
                if stack:
                    stack[-1] = val
            elif kind == "h":
                key = stack[-1] if stack else "<root>"
                hk = (key, val)
                if hk in seen:
                    err(qml_path, f"handler {val} declared again on the same "
                                  f"component as line {seen[hk]} — "
                                  f"one handler per signal per component")
                else:
                    seen[hk] = lineno
    if is_main:
        if "PlasmoidItem" not in text:
            err(qml_path, "main.qml root must be PlasmoidItem "
                          "(compact/fullRepresentation as direct children)")
        if "compactRepresentation" not in text:
            warn(qml_path, "no compactRepresentation — panel form missing")


def check_probe_run(probe_path):
    """Execute a probe ONCE (read-only probes only!) and validate strict JSON."""
    try:
        out = subprocess.run([str(probe_path)], capture_output=True,
                             text=True, timeout=10).stdout
    except Exception as e:
        err(probe_path, f"execution failed: {e}")
        return
    line = out.strip().splitlines()[-1] if out.strip() else ""
    try:
        data = json.loads(line)
        if not isinstance(data, dict):
            raise ValueError("not an object")
    except Exception as e:
        err(probe_path, f"last output line is not strict JSON object ({e}): {line[:120]!r}")
        return
    print(f"  probe OK: {sorted(data.keys())[:8]}")


if __name__ == "__main__":
    from collections import Counter
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    root = Path(sys.argv[1]).resolve()
    run_probes = sys.argv[2:]

    meta_path = root / "metadata.json"
    if not meta_path.exists():
        err(root, "metadata.json missing")
        meta = None
    else:
        meta = check_metadata(meta_path)

    qml_files = sorted(root.glob("contents/ui/**/*.qml"))
    if not qml_files:
        warn(root, "no QML files under contents/ui/")
    for qf in qml_files:
        check_qml_file(qf, qf.name == "main.qml",
                       meta.get("KPlugin", {}).get("Id", "?") if meta else "?")

    for p in run_probes:
        check_probe_run(Path(p))

    for w in WARNINGS:
        print(f"WARN {w}")
    for e in ERRORS:
        print(f"ERR  {e}")
    total = len(qml_files)
    print(f"\n{root.name}: {total} QML files checked, "
          f"{len(ERRORS)} errors, {len(WARNINGS)} warnings")
    sys.exit(1 if ERRORS else 0)
