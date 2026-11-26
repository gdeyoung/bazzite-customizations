import QtQuick
import org.kde.kirigami as Kirigami

// SkeletonRow — shape-matched loading placeholder; alpha pulses 0.15..0.35.
Rectangle {
    property real w: 200
    width: w
    height: 10
    radius: 3
    color: Kirigami.Theme.textColor
    opacity: 0.15
    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: true
        NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.15; duration: 800; easing.type: Easing.InOutQuad }
    }
}
