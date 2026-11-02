import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "lib/CategoryModel.js" as CategoryModel

// Category view (spec §F): ranked proportional bar-list (treemap deferred
// to v0.2). 4-segment switcher inside the view, summary line, 40px rows
// with full-width single-color bars. Segment switch keeps scroll position.
ColumnLayout {
    id: page

    readonly property string category: {
        MosaicStore.viewStack                        // notifier guard
        return MosaicStore.categories.indexOf(MosaicStore.currentArg) >= 0
            ? MosaicStore.currentArg : "config"
    }
    readonly property var model: {
        MosaicStore.snapshot                         // notifier guard
        return MosaicStore.hasSnapshot
            ? CategoryModel.summary(MosaicStore.snapshot.apps, category) : null
    }
    readonly property var rows: {
        if (!model || !model.apps) return []
        // keep only apps with measured bytes in this category
        return model.apps.filter(function(r) { return r.bytes !== null && r.bytes > 0 })
    }
    readonly property real catTotal: rows.reduce(function(a, r) { return a + r.bytes }, 0)
    readonly property real mappedTotal: MosaicStore.hasSnapshot && MosaicStore.snapshot.summary
        ? MosaicStore.snapshot.summary.bytes : 0
    readonly property real catShare: mappedTotal > 0
        ? Math.round(catTotal * 100 / mappedTotal) : 0
    readonly property real maxInCat: rows.length > 0 ? rows[0].bytes : 0
    property var savedY: ({})                       // per-category scroll memory

    spacing: 8

    Keys.onLeftPressed: cycleSegment(-1)
    Keys.onRightPressed: cycleSegment(1)
    function cycleSegment(step) {
        const i = MosaicStore.categories.indexOf(page.category)
        const n = (i + step + MosaicStore.categories.length) % MosaicStore.categories.length
        selectSegment(MosaicStore.categories[n])
    }
    function selectSegment(key) {
        if (key === page.category) return
        savedY[page.category] = rankList.contentY
        MosaicStore.replaceTop("cat:" + key)
    }

    // exclusivity is derived: checked binds to currentArg, clicks go through
    // selectSegment() -> replaceTop(), so no ButtonGroup is needed (and
    // ButtonGroup.buttons cannot take a Repeater's children anyway).

    RowLayout {
        id: segmentRow
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 2

        Repeater {
            model: MosaicStore.categories
            delegate: PC3.Button {
                required property string modelData
                checkable: true
                checked: MosaicStore.currentArg === modelData
                text: MosaicStore.categoryLabel(modelData)
                implicitHeight: 32
                onClicked: page.selectSegment(modelData)
            }
        }
        Item { Layout.fillWidth: true }
    }

    // summary line: total + share of mapped
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: Kirigami.Units.smallSpacing / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.06)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Kirigami.Units.smallSpacing
            text: MosaicStore.formatBytes(page.catTotal, false) + " "
                  + page.category + " \u00b7 " + page.catShare + "% of mapped"
            color: Kirigami.Theme.textColor
            font.pixelSize: 13
        }
    }

    ListView {
        id: rankList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.rows
        PC3.ScrollBar.vertical: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }

        onVisibleChanged: if (visible) contentY = page.savedY[page.category] || 0
        onModelChanged: contentY = page.savedY[page.category] || 0

        delegate: Item {
            id: rankRow
            required property var modelData
            required property int index

            width: rankList.width
            height: 40
            implicitHeight: 40

            signal activated()
            onActivated: MosaicStore.pushView("app:" + modelData.id)

            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.name + ", "
                + MosaicStore.formatBytes(modelData.bytes, false)

            MouseArea {
                id: rankTap
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { rankRow.forceActiveFocus(); rankRow.activated() }
            }
            Rectangle {
                visible: rankTap.containsMouse || rankRow.activeFocus
                anchors.fill: parent
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.06)
                border.color: rankRow.activeFocus ? Kirigami.Theme.highlightColor : "transparent"
                border.width: 1
                radius: Kirigami.Units.smallSpacing / 2
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.12)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    source: rankRow.modelData.icon ? rankRow.modelData.icon
                                                   : "application-x-executable"
                }
                Text {
                    Layout.preferredWidth: 140
                    text: rankRow.modelData.name
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                // proportional bar: largest app in this category fills the track
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.10)
                    }
                    Rectangle {
                        height: 10
                        width: parent.width * (page.maxInCat > 0
                            ? rankRow.modelData.bytes / page.maxInCat : 0)
                        radius: 2
                        color: MosaicStore.categoryColor(page.category)
                    }
                }
                Text {
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignRight
                    text: MosaicStore.formatBytes(rankRow.modelData.bytes,
                        rankRow.modelData.partial === true)
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 13
                }
                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: (page.catTotal > 0
                        ? Math.round(rankRow.modelData.bytes * 100 / page.catTotal) : 0) + "%"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                }
            }
            Keys.onReturnPressed: rankRow.activated()
            Keys.onEnterPressed: rankRow.activated()
        }
    }
}
