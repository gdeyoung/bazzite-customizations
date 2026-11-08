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
import os
import sys

from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl, QPointF
from PySide6.QtGui import QGuiApplication
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


class Bridge(QObject):
    """QML↔daemon channel (signals out, dbus slots in)."""

    gotoState = Signal(str)

    def __init__(self):
        super().__init__()
        # multi-monitor: horizontal shift so the card centers on the PRIMARY
        # screen rather than the combined virtual desktop (see main()).
        self._cardOffsetX = 0
        # super-ultrawide (aspect >= 2.6): upscale the 920x640 card so it
        # doesn't read tiny on a 5120-wide panel; 1.0 elsewhere.
        self._cardScale = 1.0

    def _read_cardOffsetX(self):
        return self._cardOffsetX

    cardOffsetX = Property(int, _read_cardOffsetX, constant=True)

    def _read_cardScale(self):
        return self._cardScale

    cardScale = Property(float, _read_cardScale, constant=True)

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
        self.gotoState.emit(state)

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

    bridge.toggleRequested.connect(
        lambda: win.hide() if win.isVisible() else _show(win))
    bridge.showRequested.connect(lambda: _show(win))
    bridge.hideRequested.connect(win.hide)

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
