import QtQuick
import org.kde.kirigami as Kirigami

// Hair — 1px separator at textColor 10%.
Rectangle {
    height: 1
    color: Qt.alpha(Kirigami.Theme.textColor, 0.10)
}
