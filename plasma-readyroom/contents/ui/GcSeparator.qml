import QtQuick
import org.kde.kirigami as Kirigami

// Horizontal separator. Port of PanelSeparator.
Rectangle {
    implicitHeight: 1
    color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
}
