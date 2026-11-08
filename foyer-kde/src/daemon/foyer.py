#!/usr/bin/python3
"""
foyer.py — user-space Foyer daemon (no rpm-ostree, no compiled C++).

Architecture (R1.2 user-space contract):
    PySide6 (system rpm, links the SAME Qt 6.11 as the desktop) hosts
    FoyerRoot.qml inside FoyerWindow.qml — a LayerShellQt Layer.Top surface
    (org.kde.layershell QML module, shipped on the host). The daemon stays
    resident (systemd user unit, Type=dbus) so summon = window.show() on a
    warm engine — the krunner pattern without being krunner.

DBus surface (gdeyoung.foyer):
    toggle() / showUI() / hideUI()   — the hotkey targets
    driveState(s)                    — state-driver channel (harness + tests)

The bridge is signal-only: QML never calls into Python, Python never pokes
QML objects; FoyerWindow.qml wires bridge signals to FoyerRoot.gotoState.

Verify in the nested-kwin harness (harness/run-foyer-daemon.sh) — never on
the live session first.
"""
import glob
import json
import os
import sys

from PySide6.QtCore import (QObject, Property, QCoreApplication, QEvent, Qt,
                            Signal, Slot, QUrl, QPointF)
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtDBus import QDBusConnection

HERE = os.path.dirname(os.path.abspath(__file__))

# --- environment pinning (must precede QGuiApplication construction) --------
# Fractional scaling on a layer-shell surface produced a ~5% hit-test skew
# on the 5120x1440@105% host (clicks landed one row low): run physical 1:1
# and scale the card ourselves (bridge.cardScale). setdefault so a harness
# may still override explicitly.
os.environ.setdefault("QT_ENABLE_HIGHDPI_SCALING", "0")
os.environ.setdefault("QT_SCALE_FACTOR", "1")
os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")

BUS_NAME = "gdeyoung.foyer"
BUS_PATH = "/gdeyoung/foyer"

HARNESS = os.environ.get("FOYER_D_RW") == "1"   # nested-harness marker

# XDG main category -> foyer label (first hit wins; order = priority)
_CATMAP = [
    ("Game", "Games"), ("Network", "Internet"), ("AudioVideo", "Media"),
    ("Graphics", "Graphics"), ("Office", "Office"), ("Utility", "Utilities"),
    ("Development", "Development"), ("Science", "Science"),
    ("Education", "Education"), ("System", "System"),
]
_DESKTOP_DIRS = (
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
)


def scan_apps():
    """Real launcher data: .desktop scan -> categories with real app lists.

    This is the 'live providers' phase the frozen FoyerData.js always
    promised — boot category counts and category contents come from the
    system, not a design-time snapshot. Returns a JSON string.
    """
    import configparser

    seen = {}
    for d in _DESKTOP_DIRS:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            key = os.path.basename(f)
            if key in seen and d == _DESKTOP_DIRS[0]:
                continue  # user/system dirs override /usr/share on revisit
            try:
                cp = configparser.ConfigParser(interpolation=None,
                                               strict=False)
                with open(f, encoding="utf-8", errors="ignore") as fh:
                    cp.read_file(fh)
                if not cp.has_section("Desktop Entry"):
                    continue
                de = cp["Desktop Entry"]
                if de.get("Type", "Application") != "Application":
                    continue
                if de.getboolean("NoDisplay", False):
                    continue
                if de.getboolean("Hidden", False):
                    continue
                name = de.get("Name", "").strip()
                exec_ = de.get("Exec", "").strip()
                if not name or not exec_:
                    continue
                cats = (de.get("Categories", "") + ";").split(";")
                label = "Other"
                for cid, lab in _CATMAP:
                    if cid in cats:
                        label = lab
                        break
                # spec visibility: NotShowIn hits the current desktop → skip;
                # OnlyShowIn set and current desktop absent → skip
                cur = {s.strip() for s in os.environ.get(
                    "XDG_CURRENT_DESKTOP", "").split(":") if s.strip()}
                nsi = (de.get("NotShowIn", "") + ";").split(";")
                if cur & {s.strip() for s in nsi if s.strip()}:
                    continue
                osi = {s.strip() for s in
                       (de.get("OnlyShowIn", "") + ";").split(";") if s.strip()}
                if osi and not (cur & osi):
                    continue
                seen[key] = (label, name, de.get("GenericName", "").strip(),
                             f)
            except Exception:
                continue

    buckets = {}
    for label, name, generic, path in seen.values():
        buckets.setdefault(label, []).append(
            {"name": name, "generic": generic, "path": path})
    out = []
    for label, apps in buckets.items():
        if label == "Other" and len(out) >= 9:   # keep the rail tidy
            continue
        apps.sort(key=lambda a: a["name"].lower())
        out.append({"id": label, "label": label, "apps": apps})
    out.sort(key=lambda c: c["label"].lower())
    return json.dumps(out)


# real Qt key delivery (QEvent.KeyPress/Release on the window — delivered
# to the focus object, i.e. the EXACT path a physical keypress takes,
# field Keys-handlers and TextInput cursor logic included)
_REALKEYS = {
    "down": Qt.Key.Key_Down, "up": Qt.Key.Key_Up,
    "left": Qt.Key.Key_Left, "right": Qt.Key.Key_Right,
    "enter": Qt.Key.Key_Return, "escape": Qt.Key.Key_Escape,
}


def post_real_key(win, k):
    kk = _REALKEYS.get(k)
    if kk is None:
        return
    try:    # QA trace: who receives real keys (focus theft detector)
        fo = win.focusObject()
        cn = ""
        try:
            cn = fo.metaObject().className()
        except Exception:
            pass
        print(f"foyer[key] {k} -> {cn} '{fo.objectName()}'", file=sys.stderr,
              flush=True)
    except Exception:
        pass
    pre = post = ""
    try:
        pre = _STATE_READER() or ""      # type: ignore[misc]
    except Exception:
        pass
    for typ in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
        QCoreApplication.sendEvent(
            win, QKeyEvent(typ, int(kk), Qt.KeyboardModifier.NoModifier))
    try:
        post = _STATE_READER() or ""     # type: ignore[misc]
    except Exception:
        pass
    cur = ln = -1
    try:
        from PySide6.QtQuick import QQuickItem
        r = win.findChild(QQuickItem, "foyerRoot")
        if r is not None:
            pv = r.property("caret")
            cur = int(pv) if pv is not None else -1
            pv = r.property("queryLen")
            ln = int(pv) if pv is not None else -1
    except Exception:
        pass
    print(f"foyer[nav] {k}: {pre!r} -> {post!r} cur={cur} len={ln}",
          file=sys.stderr, flush=True)


_STATE_READER = lambda: ""   # set by main() once the window exists


class Bridge(QObject):
    """QML↔daemon channel (signals out, dbus slots in)."""

    gotoState = Signal(str)
    keyDriven = Signal(str)
    keyRealDriven = Signal(str)
    launchRequested = Signal(str)

    def __init__(self):
        super().__init__()
        self._launch_log = []   # harness: recorded (not executed) launches
        # multi-monitor: horizontal shift so the card centers on the PRIMARY
        # screen rather than the combined virtual desktop (see main()).
        self._cardOffsetX = 0
        # super-ultrawide (aspect >= 2.6): upscale the 920x640 card so it
        # doesn't read tiny on a 5120-wide panel; 1.0 elsewhere.
        self._cardScale = 1.0
        self._appsJson = scan_apps()

    def _read_cardOffsetX(self):
        return self._cardOffsetX

    cardOffsetX = Property(int, _read_cardOffsetX, constant=True)

    def _read_cardScale(self):
        return self._cardScale

    cardScale = Property(float, _read_cardScale, constant=True)

    def _read_appsJson(self):
        return self._appsJson

    appsJson = Property(str, _read_appsJson, constant=True)

    @Slot()
    def toggle(self):
        self.toggleRequested.emit()

    @Slot()
    def showUI(self):
        self.showRequested.emit()

    @Slot()
    def hideUI(self):
        self.hideRequested.emit()

    @Slot(str)
    def driveState(self, state):
        print(f"foyer[drv] {state}", file=sys.stderr, flush=True)
        self.gotoState.emit(state)

    @Slot(str)
    def driveKey(self, key):
        """Verification channel: routes a logical key (down/up/left/right/
        enter) into the QML nav layer — same code path a real keypress
        takes after the field's Keys handlers forward it."""
        self.keyDriven.emit(key)

    @Slot(str)
    def driveKeyReal(self, key):
        """Verification channel: posts a REAL Qt KeyPress/KeyRelease pair
        on the window (delivered to the focus object). This is the exact
        delivery path a physical keypress takes — field Keys-handlers,
        TextInput cursor logic and all. QA must use this one."""
        self.keyRealDriven.emit(key)

    @Slot(result=str)
    def launchLog(self):
        """Harness assertion channel: execs recorded but not spawned."""
        return json.dumps(self._launch_log)

    @Slot(result=str)
    def harnessMode(self):
        """QA gate: '1' when running under the nested harness (launches
        are recorded, not spawned). check-nav must never press ⏎ on app
        rows against a live daemon — it would launch real apps."""
        return "1" if HARNESS else "0"

    # set by main() once the window exists: () -> "state zone i n cols rail"
    stateReader = None  # type: ignore[assignment]

    @Slot(result=str)
    def navState(self):
        """QA introspection: full keyboard-nav state as one string."""
        return self.stateReader() if self.stateReader else ""  # type: ignore[misc]

    # internal wiring signals (connected to the window by main())
    toggleRequested = Signal()
    showRequested = Signal()
    hideRequested = Signal()


def main():
    app = QGuiApplication(sys.argv)
    app.setApplicationName("foyer")
    app.setDesktopFileName("gdeyoung-foyer")
    app.setApplicationVersion("0.2.0")

    bridge = Bridge()

    # Multi-monitor fix: kwin assigns the layer surface the FULL combined
    # output; an un-offset card would center on the monitor seam. Shift the
    # card to the PRIMARY screen's center. Computed before QML loads so the
    # constant property binds with the right value (single-monitor → 0).
    try:
        prim = app.primaryScreen()
        if prim is not None:
            vg = prim.virtualGeometry()
            bridge._cardOffsetX = prim.geometry().center().x() - vg.center().x()
            # With QT_ENABLE_HIGHDPI_SCALING=0 these are PHYSICAL pixels.
            w, h = vg.width(), vg.height()
            if w / h >= 2.6:
                bridge._cardScale = 1.45
    except Exception as exc:  # cosmetic; never block startup
        print(f"foyer: screen geometry fallback ({exc})", file=sys.stderr)

    engine = QQmlApplicationEngine()
    engine.addImportPath("/usr/lib64/qt6/qml")  # system KDE QML modules
    engine.rootContext().setContextProperty("bridge", bridge)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "FoyerWindow.qml")))
    if not engine.rootObjects():
        print("foyer: FoyerWindow.qml failed to load", file=sys.stderr)
        return 1
    win = engine.rootObjects()[0]

    def _read_nav():
        from PySide6.QtQuick import QQuickItem
        r = win.findChild(QQuickItem, "foyerRoot")
        if r is None:
            return "no-root"
        vals = [str(r.property(p)) for p in
                ("state", "zone", "lensIndex", "lensCount", "lensCols", "railIndex",
                 "activeCatId")]
        return " ".join(v if v not in ("None", "") else "?" for v in vals)

    bridge.stateReader = _read_nav
    global _STATE_READER
    _STATE_READER = _read_nav

    bridge.toggleRequested.connect(
        lambda: win.hide() if win.isVisible() else _show(win))
    bridge.showRequested.connect(lambda: _show(win))
    bridge.hideRequested.connect(win.hide)
    bridge.keyRealDriven.connect(lambda k: post_real_key(win, k))

    def _launch(path):
        # Launch by desktop FILE via gio — spec-compliant Exec handling
        # (field codes, quoting, Terminal, DBusActivatable), no shell, no
        # injection surface. Council item: never hand-parse Exec.
        if HARNESS:
            bridge._launch_log.append(path)   # assertable, never spawned
            return
        from PySide6.QtCore import QProcess
        if os.path.exists("/usr/bin/gio"):
            ok = QProcess.startDetached("/usr/bin/gio", ["launch", path])
        else:   # last-ditch fallback (logged loudly)
            print(f"foyer: gio missing; cannot launch {path}",
                  file=sys.stderr, flush=True)
            ok = False
        if ok:
            win.hide()
        else:
            print(f"foyer: launch failed: {path}", file=sys.stderr,
                  flush=True)

    bridge.launchRequested.connect(_launch)

    conn = QDBusConnection.sessionBus()
    if not conn.registerService(BUS_NAME):
        print("foyer: another instance owns " + BUS_NAME, file=sys.stderr)
        return 2
    # Fedora PySide6 has no QClassInfo; the interface-name overload pins it.
    ok = conn.registerObject(BUS_PATH, BUS_NAME, bridge,
                             QDBusConnection.ExportAllSlots)
    if not ok:
        print("foyer: registerObject failed", file=sys.stderr)
        return 3

    if "--show" in sys.argv:
        _show(win)

    # harness diagnostics: late window state (post-map)
    from PySide6.QtCore import QTimer
    QTimer.singleShot(3000, lambda: _dump(win, "t+3s"))

    return app.exec()


def _show(win):
    win.show()
    win.raise_()
    win.requestActivate()
    _dump(win, "show")


def _dump(win, tag):
    print("foyer[%s] vis=%s w=%s h=%s x=%s y=%s" % (
        tag, win.isVisible(), win.width(), win.height(), win.x(), win.y()),
        file=sys.stderr, flush=True)
    # card geometry in WINDOW coordinates (diagnostics; exact, no pixels)
    try:
        from PySide6.QtQuick import QQuickItem
        box = win.findChild(QQuickItem, "cardBox")
        r = win.findChild(QQuickItem, "foyerRoot")
        if box is not None and r is not None:
            bp = box.mapToScene(QPointF(0, 0))
            print("foyer[%s] cardBox %.0fx%.0f at (%.0f,%.0f) | foyerRoot "
                  "%.0fx%.0f u=%.2f t=%.2f" % (
                      tag, box.width(), box.height(), bp.x(), bp.y(),
                      r.width(), r.height(),
                      float(r.property("u") or 0), float(r.property("t") or 0)),
                  file=sys.stderr, flush=True)
    except Exception as exc:
        print(f"foyer[{tag}] cardBox probe failed: {exc}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
