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

from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtDBus import QDBusConnection

HERE = os.path.dirname(os.path.abspath(__file__))

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

    def _read_cardOffsetX(self):
        return self._cardOffsetX

    cardOffsetX = Property(int, _read_cardOffsetX, constant=True)

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
    except Exception as exc:  # offset is cosmetic; never block startup
        print(f"foyer: screen-offset fallback 0 ({exc})", file=sys.stderr)

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


if __name__ == "__main__":
    sys.exit(main())
