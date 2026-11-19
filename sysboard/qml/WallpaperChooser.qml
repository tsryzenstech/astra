// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The pictures of the phone (the Gallery's) to choose a wallpaper from, for a lock screen.
Item {
    id: root

    property bool shown: false
    property Item blurSource: null
    property bool withDefault: true
    signal chosen(string path)       // "" is the system's wallpaper
    signal cancelled()

    visible: reveal.value > 0.01
    opacity: reveal.value
    z: 70
    Spring { id: reveal; to: root.shown ? 1 : 0; response: 0.4; dampingFraction: 0.88 }

    property var pictures: []
    function load() {
        Application.mediaAsync(["*.jpg", "*.jpeg", "*.png", "*.webp"], function(list) {
            root.pictures = list.slice(0, 400)
        })
    }
    onShownChanged: if (shown) load()

    BlurLayer { anchors.fill: parent; source: root.blurSource; amount: 1; dim: 0.6 }
    MouseArea { anchors.fill: parent }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.statusBarHeight + 14
        text: qsTr("Choose a Picture")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headlineSize
        font.weight: Font.DemiBold
        color: "white"
    }
    Glass {
        x: 12
        y: Theme.statusBarHeight + 8
        width: 84
        height: 36
        source: root.blurSource
        onClicked: root.cancelled()
        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
    }

    GridView {
        id: grid
        anchors.fill: parent
        anchors.topMargin: Theme.statusBarHeight + 62
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: Theme.homeIndicatorHeight
        cellWidth: width / 3
        cellHeight: cellWidth * 1.7
        clip: true
        model: (root.withDefault ? [{ path: "" }] : []).concat(root.pictures)
        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.1)
                clip: true
                Image {
                    anchors.fill: parent
                    source: cell.modelData.path === "" ? Host.wallpaper : System.fileUrl(cell.modelData.path)
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(240, 400)
                    asynchronous: true
                }
                Text {
                    visible: cell.modelData.path === ""
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 10
                    text: qsTr("Default")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                    color: "white"
                }
                MouseArea { anchors.fill: parent; onClicked: root.chosen(cell.modelData.path) }
            }
        }
    }
    Text {
        visible: root.pictures.length === 0
        anchors.centerIn: parent
        width: parent.width - 60
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: qsTr("No pictures yet: photos and screenshots show up here.")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Qt.rgba(1, 1, 1, 0.7)
    }
}
