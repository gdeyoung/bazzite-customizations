import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Session tab: Boot-to-Game-Mode toggle (SDDM autologin session, mirrors
// `ujust toggle-gamemode`), the game-session switch (gc-session), and the
// per-switch honest ownership notes from the upstream SessionTab.
// All interaction is callback properties; verbs bubble to main.qml.
ColumnLayout {
    id: root

    property var session: null        // main.qml's sessionStatus object
    property var bootMode: null       // main.qml's bootModeStatus object
    property bool busy: false
    property var engageTap: function() {}
    property var releaseTap: function() {}
    property var bootModeTap: function(mode) {}   // "gamemode" | "desktop"

    spacing: Kirigami.Units.largeSpacing

    readonly property bool ready: session !== null

    // ------------------------------------------------ boot-to-game-mode

    GcSectionHeader { Layout.fillWidth: true; text: "Boot into" }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.smallFont
            text: bootMode && bootMode.readable
                ? (bootMode.mode === "gamemode"
                    ? "Next login opens Steam Game Mode (gamescope-session)."
                    : "Next login opens the desktop.")
                : "Boot mode reads the SDDM autologin file; switching it asks for authorization once (pkexec)."
        }

        GcButton {
            glyph: bootMode && bootMode.mode === "gamemode" ? "\uF0379" : "\uF02B4"
            text: bootMode && bootMode.mode === "gamemode" ? "Desktop" : "Game Mode"
            enabled: !root.busy && bootMode && bootMode.readable
            opacity: enabled ? 1.0 : 0.5
            tap: function() {
                root.bootModeTap(bootMode && bootMode.mode === "gamemode"
                    ? "desktop" : "gamemode")
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: bootMode && bootMode.lastError !== ""
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
        text: bootMode ? bootMode.lastError : ""
    }

    GcSeparator { Layout.fillWidth: true }

    // ------------------------------------------------ the session switch

    GcToggle {
        Layout.fillWidth: true
        label: root.ready && session.engaged ? "Session on" : "Session"
        description: {
            if (!root.ready) return "starting…"
            if (root.busy) return "working…"
            return session.engaged
                ? "Ending it puts back only what Ready Room changed."
                : "One switch for the things you flip before playing."
        }
        checked: root.ready && session.engaged
        tap: function() {
            if (root.ready && session.engaged) root.releaseTap()
            else root.engageTap()
        }
    }

    GcSectionHeader { Layout.fillWidth: true; text: "This session will" }

    GcToggle {
        Layout.fillWidth: true
        label: "Keep the screen awake"
        description: root.ready ? session.stayAwakeNote : ""
        checked: root.ready && session.wantIdle
        tap: function() { if (root.ready) session.wantIdle = !session.wantIdle }
    }

    GcToggle {
        Layout.fillWidth: true
        label: "Silence notifications"
        description: {
            if (!root.ready) return ""
            if (session.dndState === "unknown")
                return "can't read do-not-disturb right now"
            if (session.engaged && session.ownedDnd)
                return session.dndState === "on"
                    ? "on for this session — put back when it ends"
                    : "you changed this — Ready Room won't put it back"
            return session.dndState === "on"
                ? "already on — Ready Room won't change it"
                : (session.engaged ? "left as it was"
                                   : "on for this session — put back when it ends")
        }
        checked: root.ready && session.wantDnd
        tap: function() { if (root.ready) session.wantDnd = !session.wantDnd }
    }

    GcToggle {
        Layout.fillWidth: true
        label: "Turn off night light"
        description: {
            if (!root.ready) return ""
            if (session.engaged && session.ownedNightlight)
                return "off for this session — restored to the same temperature"
            return session.nightlightOn
                ? "on now — turned off for the session, restored to the same temperature"
                : "already off"
        }
        checked: root.ready && session.wantNightlight
        tap: function() { if (root.ready) session.wantNightlight = !session.wantNightlight }
    }

    GcToggle {
        // Absent, not disabled, when the machine has no performance profile.
        visible: root.ready && session.powerProfileAvailable
        Layout.fillWidth: true
        label: "Performance power profile"
        description: root.ready ? "now: " + session.powerCurrent : ""
        checked: root.ready && session.wantPower
        tap: function() { if (root.ready) session.wantPower = !session.wantPower }
    }

    Text {
        Layout.fillWidth: true
        visible: root.ready && !session.powerProfileAvailable
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: Kirigami.Theme.smallFont
        text: root.ready
            ? "No performance power profile on this machine (offers "
              + (session.powerAvailable || []).join(", ") + ")."
            : ""
    }

    GcSeparator { Layout.fillWidth: true }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.6
        font: Kirigami.Theme.smallFont
        text: {
            if (!root.ready) return "starting…"
            if (session.lastError !== "") return session.lastError
            return session.engaged
                ? "Session on. Ending it puts back only what Ready Room changed."
                : "Nothing changed yet."
        }
    }
}
