import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

// Settings page — KConfig XT mirror of the Omarchy plugin's manifest schema
// (the parts the Plasma port uses). Paths are parameters, never baked in.
KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Opens showing:")
            model: [
                { value: "session", text: i18n("Session") },
                { value: "pads", text: i18n("Pads") },
                { value: "replay", text: i18n("Replay") },
                { value: "gear", text: i18n("Gear") }
            ]
            textRole: "text"
            currentIndex: {
                var v = String(cfg_startTab)
                var i = 0
                for (var j = 0; j < model.length; j++)
                    if (model[j].value === v) i = j
                return i
            }
            onActivated: function(index) { cfg_startTab = model[index].value }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Popup width (px):")
            from: 300
            to: 640
            stepSize: 10
            value: cfg_panelWidth
            onValueModified: cfg_panelWidth = value
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Session:")
            text: i18n("Keep the screen awake")
            checked: cfg_sessionKeepAwake
            onToggled: cfg_sessionKeepAwake = checked
        }
        QQC2.CheckBox {
            text: i18n("Silence notifications")
            checked: cfg_sessionDnd
            onToggled: cfg_sessionDnd = checked
        }
        QQC2.CheckBox {
            text: i18n("Turn off night light")
            checked: cfg_sessionNightlight
            onToggled: cfg_sessionNightlight = checked
        }
        QQC2.CheckBox {
            text: i18n("Set performance power profile")
            checked: cfg_sessionPower
            onToggled: cfg_sessionPower = checked
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Replay buffer (seconds):")
            from: 60
            to: 900
            stepSize: 60
            value: cfg_replaySeconds
            onValueModified: cfg_replaySeconds = value
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Buffer storage:")
            model: [i18n("disk"), i18n("ram")]
            currentIndex: cfg_replayStorage === "ram" ? 1 : 0
            onActivated: function(index) { cfg_replayStorage = index === 1 ? "ram" : "disk" }
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Quality:")
            model: [i18n("low"), i18n("balanced"), i18n("high"), i18n("ultra")]
            currentIndex: Math.max(0, ["low", "balanced", "high", "ultra"]
                .indexOf(String(cfg_replayQuality)))
            onActivated: function(index) {
                cfg_replayQuality = ["low", "balanced", "high", "ultra"][index]
            }
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Audio:")
            model: [i18n("desktop"), i18n("both"), i18n("none")]
            currentIndex: Math.max(0, ["desktop", "both", "none"]
                .indexOf(String(cfg_replayAudio)))
            onActivated: function(index) {
                cfg_replayAudio = ["desktop", "both", "none"][index]
            }
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Clip folder (empty = Videos/Clips):")
            text: cfg_replayDir
            onTextChanged: cfg_replayDir = text
            placeholderText: i18n("/home/you/Videos/Clips")
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("MangoHud corner:")
            model: ["top-left", "top-right", "bottom-left", "bottom-right"]
            currentIndex: Math.max(0, model.indexOf(String(cfg_mangohudPosition)))
            onActivated: function(index) { cfg_mangohudPosition = model[index] }
        }
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("MangoHud metrics:")
            text: i18n("CPU, GPU, RAM, VRAM, temps")
            checked: cfg_mhCpu && cfg_mhGpu && cfg_mhRam && cfg_mhVram && cfg_mhTemps
            onToggled: {
                cfg_mhCpu = checked; cfg_mhGpu = checked; cfg_mhRam = checked
                cfg_mhVram = checked; cfg_mhTemps = checked
            }
        }
        QQC2.CheckBox {
            text: i18n("GPU power draw (NVIDIA)")
            checked: cfg_mhPower
            onToggled: cfg_mhPower = checked
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("SDDM autologin drop-in (boot mode):")
            text: cfg_bootModeConfPath
            onTextChanged: cfg_bootModeConfPath = text
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Game Mode session file:")
            text: cfg_gameModeSession
            onTextChanged: cfg_gameModeSession = text
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Desktop session file:")
            text: cfg_desktopSession
            onTextChanged: cfg_desktopSession = text
        }
    }
}
