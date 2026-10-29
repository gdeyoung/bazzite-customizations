/*
 * WatchlistTab — full list + symbol search (spec E).
 * Rows: 48px flat + hairlines · spark 48×20 · symbol 14 semibold · name 12 ·
 * price tabular · Δ$ text · Δ% pill · hover ✕ (undo 3s) · accent rail on the
 * chip's current symbol · click = detail. Search: debounced 300ms, ≥2 chars,
 * results replace list in place, "+" adds to watchlist. Esc clears.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: tab

    property var api
    property string query: ""
    property bool searchOpen: false

    function beginSearch() {
        var q = searchField.text.trim()
        if (q.length < 2) { tab.query = ""; resultsModel.clear(); return }
        api.searchYahoo(q, function(list) {
            // stale-guard: only apply if the field still holds this query
            if (searchField.text.trim() !== q) return
            resultsModel.clear()
            for (var i = 0; i < list.length && i < 8; i++)
                resultsModel.append(list[i])
            tab.query = q
        })
    }

    ListModel { id: resultsModel }
    ListModel { id: undoModel }   // 0 or 1 row: {sym, label}

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 8

        // header: the list is the hero; search hides behind [Add symbol]
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: qsTr("Watchlist")
                color: Kirigami.Theme.textColor
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Rectangle {
                radius: 7
                width: countText.implicitWidth + 12
                height: countText.implicitHeight + 6
                color: Qt.rgba(1, 1, 1, 0.08)
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: api.watchModel ? api.watchModel.count : 0
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            Item { Layout.fillWidth: true }
            QQC2.Button {
                flat: true
                icon.name: tab.searchOpen ? "dialog-close" : "list-add"
                text: tab.searchOpen ? qsTr("Done") : qsTr("Add symbol")
                onClicked: {
                    if (tab.searchOpen) {
                        searchField.clear()
                        tab.query = ""
                        resultsModel.clear()
                        tab.searchOpen = false
                    } else {
                        tab.searchOpen = true
                        searchField.forceActiveFocus()
                    }
                }
            }
        }

        QQC2.TextField {
            id: searchField
            visible: tab.searchOpen
            Layout.fillWidth: true
            placeholderText: qsTr("Search stocks & crypto…")
            font.pixelSize: 13
            onTextChanged: debounce.restart()
            Keys.onEscapePressed: {
                clear()
                tab.query = ""
                resultsModel.clear()
                tab.searchOpen = false
            }
            Timer {
                id: debounce
                interval: 300
                onTriggered: tab.beginSearch()
            }
        }

        // undo banner (remove w/ 3s undo — never a confirm dialog)
        Rectangle {
            visible: undoModel.count > 0
            Layout.fillWidth: true
            height: 32
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.06)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                Text {
                    Layout.fillWidth: true
                    text: undoModel.count > 0
                          ? "Removed " + undoModel.get(0).sym : ""
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 12
                }
                QQC2.Button {
                    flat: true
                    text: "Undo"
                    onClicked: {
                        if (undoModel.count > 0) {
                            api.addSymbol(undoModel.get(0).sym)
                            undoModel.clear()
                        }
                    }
                }
            }
            Timer {
                interval: 3000
                running: undoModel.count > 0
                onTriggered: undoModel.clear()
            }
        }

        // search results replace the list in place
        ListView {
            id: resultList
            visible: tab.query !== ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: resultsModel
            spacing: 0
            delegate: Rectangle {
                width: resultList.width
                height: 48
                color: srMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                MouseArea {
                    id: srMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: api.detailSymbol = symbol
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: symbol
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: shortname || ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        radius: 4
                        width: typeTag.implicitWidth + 10
                        height: typeTag.implicitHeight + 4
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            id: typeTag
                            anchors.centerIn: parent
                            text: (quoteType || "").toUpperCase()
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: 9
                            font.letterSpacing: 0.5
                        }
                    }
                    QQC2.Button {
                        flat: true
                        text: "+ Add"
                        onClicked: {
                            api.addSymbol(symbol)
                            searchField.clear()
                            tab.query = ""
                            resultsModel.clear()
                        }
                    }
                }
            }
            Text {
                visible: resultList.count === 0 && tab.query !== ""
                anchors.centerIn: parent
                text: "No matches for '" + tab.query + "'"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 12
            }
        }

        // watchlist (normal mode)
        ListView {
            id: watchList
            visible: tab.query === ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: api.watchModel
            spacing: 0

            delegate: Item {
                width: watchList.width
                height: 48

                // accent rail: chip's current symbol
                Rectangle {
                    visible: ticker === api.selected
                    width: 3
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: Kirigami.Theme.textColor
                    opacity: 0.7
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: api.detailSymbol = ticker
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Sparkline {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 20
                        points: typeof series !== "undefined" ? series : []
                        lineColor: isPos ? api.cPos : api.cNeg
                    }
                    Text {
                        text: ticker
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: name
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        text: price
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        text: change
                        color: isPos ? api.cPos : api.cNeg
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                    Rectangle {
                        radius: 4
                        color: Qt.rgba(isPos ? api.cPos.r : api.cNeg.r,
                                       isPos ? api.cPos.g : api.cNeg.g,
                                       isPos ? api.cPos.b : api.cNeg.b, 0.16)
                        width: pctText.implicitWidth + 10
                        height: pctText.implicitHeight + 4
                        Text {
                            id: pctText
                            anchors.centerIn: parent
                            text: (isPos ? "▲" : "▼") + pctv
                            color: isPos ? api.cPos : api.cNeg
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                    QQC2.Button {
                        visible: rowMa.containsMouse
                        flat: true
                        implicitWidth: 28
                        text: "✕"
                        onClicked: {
                            undoModel.append({ sym: ticker })
                            api.removeSymbol(ticker)
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.10)
                }
            }
        }
    }
}
