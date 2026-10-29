// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// New tabs open here: Favorites, Frequently Visited and the Reading List,
// or what private browsing means in a private tab.
Rectangle {
    id: root
    required property var browser
    property bool isPrivate: false
    color: isPrivate ? (Theme.light ? "#2C2C33" : "#111116") : Theme.background

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 140
        boundsBehavior: Flickable.DragOverBounds

        Column {
            id: column
            x: 20
            y: Theme.statusBarHeight + 28
            width: parent.width - 40
            spacing: 26

            Column {
                visible: root.isPrivate
                width: parent.width
                spacing: 12
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "eye-off"; size: 48; color: "white" }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Private Browsing")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Bold
                    color: "white"
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("Planet won't remember the pages you visit, your searches or what you type in forms. Cookies and website data are deleted when you close your private tabs.")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
            }

            Section {
                visible: !root.isPrivate
                title: qsTr("Favorites")
                Grid {
                    width: parent.width
                    columns: 4
                    rowSpacing: 18
                    readonly property real cell: width / 4
                    Repeater {
                        model: root.browser.bookmarks.slice(0, 12)
                        delegate: Tile {
                            required property var modelData
                            width: parent.cell
                            entry: modelData
                            onClicked: root.browser.open(modelData.url)
                        }
                    }
                }
                Text {
                    visible: root.browser.bookmarks.length === 0
                    text: qsTr("Add bookmarks from the aA menu and they show up here.")
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize
                    color: Theme.textSecondary
                }
            }

            Section {
                visible: !root.isPrivate && root.browser.frequent.length > 0
                title: qsTr("Frequently Visited")
                Grid {
                    width: parent.width
                    columns: 4
                    rowSpacing: 18
                    readonly property real cell: width / 4
                    Repeater {
                        model: root.browser.frequent
                        delegate: Tile {
                            required property var modelData
                            width: parent.cell
                            entry: modelData
                            onClicked: root.browser.open(modelData.url)
                        }
                    }
                }
            }

            Section {
                visible: !root.isPrivate && root.browser.readingList.length > 0
                title: qsTr("Reading List")
                Repeater {
                    model: root.browser.readingList.slice(0, 4)
                    delegate: Card {
                        required property var modelData
                        width: parent.width
                        pressable: true
                        padding: 14
                        onClicked: root.browser.open(modelData.url)
                        Column {
                            width: parent.width
                            Text { width: parent.width; text: modelData.title || modelData.url; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                            Text { width: parent.width; text: root.browser.host(modelData.url); elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                        }
                    }
                }
            }
        }
    }

    component Section: Column {
        property string title
        width: parent.width
        spacing: 14
        Text {
            text: parent.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.Bold
            color: Theme.text
        }
    }

    component Tile: Item {
        id: tile
        property var entry
        signal clicked()
        height: 96
        Rectangle {
            id: face
            anchors.horizontalCenter: parent.horizontalCenter
            width: 62
            height: 62
            radius: 16
            color: Theme.surfaceRaised
            scale: tileArea.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            Image {
                id: fav
                anchors.centerIn: parent
                width: 30
                height: 30
                source: tile.entry && tile.entry.icon ? tile.entry.icon : ""
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !fav.visible
                text: root.browser.host(tile.entry ? tile.entry.url : "").charAt(0).toUpperCase()
                font.family: Theme.fontFamily
                font.pixelSize: 26
                font.weight: Font.Bold
                color: Theme.accent
            }
        }
        Text {
            anchors.top: face.bottom
            anchors.topMargin: 6
            width: parent.width - 6
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: tile.entry ? (tile.entry.title || root.browser.host(tile.entry.url)) : ""
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.text
        }
        MouseArea { id: tileArea; anchors.fill: parent; onClicked: tile.clicked() }
    }
}
