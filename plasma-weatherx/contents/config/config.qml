import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

// WeatherX settings. The bar label mode / units / interval keys mirror the
// Omarchy plugin; latitude, longitude + locationName replace Omarchy's
// ~/.local/state/omarchy/settings/weather.json device location (KDE has no
// Omarchy settings file — this is a public repo, so they ship EMPTY and the
// popup shows a first-run hint until the user fills them in).
KCM.SimpleKCM {
    Kirigami.FormLayout {
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Latitude, longitude:")
            placeholderText: i18n("e.g. 40.7128, -74.0060")
            text: cfg_latitude + ", " + cfg_longitude
            onEditingFinished: {
                var parts = text.split(",")
                var lat = parseFloat(parts[0])
                var lon = parts.length > 1 ? parseFloat(parts[1]) : NaN
                cfg_latitude = isFinite(lat) ? lat : 0
                cfg_longitude = isFinite(lon) ? lon : 0
            }
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Place name:")
            placeholderText: i18n("Shown on the Here tab (optional)")
            text: cfg_locationName
            onEditingFinished: cfg_locationName = text
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Units:")
            model: [
                { value: "imperial", text: i18n("Imperial (°F, mph)") },
                { value: "metric", text: i18n("Metric (°C, km/h)") }
            ]
            textRole: "text"
            currentIndex: cfg_units === "metric" ? 1 : 0
            onActivated: function(index) {
                cfg_units = index === 1 ? "metric" : "imperial"
            }
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Bar label:")
            model: [
                { value: "temp", text: i18n("Temperature (72°)") },
                { value: "tempcondition", text: i18n("Temperature + condition (72° Partly cloudy)") },
                { value: "icon", text: i18n("Icon only") }
            ]
            textRole: "text"
            currentIndex: cfg_barExtra === "tempcondition" ? 1 : (cfg_barExtra === "icon" ? 2 : 0)
            onActivated: function(index) {
                cfg_barExtra = index === 1 ? "tempcondition" : (index === 2 ? "icon" : "temp")
            }
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Refresh interval (minutes):")
            from: 5
            to: 120
            stepSize: 5
            value: cfg_refreshMin
            onValueModified: cfg_refreshMin = value
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("Pinned places are managed with the ＋ button in the panel popup (search a city, click a result). To remove one, click its tab twice. They persist as a JSON list of {name, lat, lon}.")
        }
    }
}
