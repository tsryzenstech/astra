// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Albums: two columns of rounded covers with their item count.
Flickable {
    id: root

    property var albums: []
    signal albumOpened(var album)

    contentHeight: grid.y + grid.height + 140
    boundsBehavior: Flickable.DragOverBounds

    Text {
        x: 18
        y: Theme.statusBarHeight + 10
        text: qsTr("Albums")
        font.family: Theme.fontFamily
        font.pixelSize: 34
        font.weight: Font.Bold
        color: "white"
    }

    Grid {
        id: grid
        x: 16
        y: Theme.statusBarHeight + 70
        columns: 2
        columnSpacing: 14
        rowSpacing: 18
        readonly property real cover: (root.width - 32 - 14) / 2

        Repeater {
            model: root.albums
            delegate: Column {
                id: album
                required property var modelData
                spacing: 6
                width: grid.cover

                Item {
                    width: grid.cover
                    height: grid.cover
                    scale: area.pressed ? 0.95 : 1
                    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: "#1C1C1E"
                        Icon {
                            anchors.centerIn: parent
                            visible: cover.status !== Image.Ready
                            name: album.modelData.id === "favorites" ? "heart" : album.modelData.id === "videos" ? "video"
                                : album.modelData.id === "screenshots" ? "recents" : "image"
                            size: 40
                            opacity: 0.5
                        }
                    }
                    Image {
                        id: cover
                        anchors.fill: parent
                        visible: false
                        source: {
                            const first = album.modelData.items.find(i => !i.video)
                            return first ? first.url : ""
                        }
                        sourceSize: Qt.size(320, 320)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle { id: mask; anchors.fill: parent; radius: 18; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        visible: cover.status === Image.Ready
                        source: cover
                        maskEnabled: true
                        maskSource: mask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    MouseArea { id: area; anchors.fill: parent; onClicked: root.albumOpened(album.modelData) }
                }
                Text {
                    width: parent.width
                    text: album.modelData.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    text: album.modelData.items.length
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    color: Theme.textSecondary
                }
            }
        }
    }
}
