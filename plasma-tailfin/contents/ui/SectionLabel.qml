import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// §V6-15 section label: `ONLINE  19 ─────────────` — the count is data,
// not a label (T3 bold textColor, tnum — the strongest thing in the
// row), the word is T4 (smallFont bold caps, letterSpacing 0.4,
// disabledTextColor — labels only, carried), and a hairline rule fills
// to the right edge (Tailscale admin-console group-header pattern).
// Members bound individually — whole-object font binds plus member
// binds throw at load (SectionLabel law).
RowLayout {
    id: label

    // e.g. "ONLINE" / "OFFLINE" / "MATCHES"
    property string word: ""
    // e.g. "19" / "2 OF 40" — "" hides the count block
    property string countText: ""

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing
    Layout.topMargin: Kirigami.Units.smallSpacing

    PC3.Label {
        visible: label.word !== ""
        text: label.word
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.4
    }

    PC3.Label {
        visible: label.countText !== ""
        text: label.countText
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        font.bold: true
        font.features: ({ "tnum": 1 })
    }

    Item { Layout.preferredWidth: Kirigami.Units.largeSpacing - Kirigami.Units.smallSpacing }

    Kirigami.Separator {
        Layout.fillWidth: true
        opacity: 0.5
    }
}
