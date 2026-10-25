// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Lock screen widget (wide): what is playing right now.
Item {
    readonly property var s: MediaController.session

    AppIcon {
        id: art
        anchors.verticalCenter: parent.verticalCenter
        size: 38
        source: MediaController.active && s.artwork ? s.artwork : Qt.resolvedUrl("../icon.svg")
    }
    Column {
        anchors.left: art.right
        anchors.leftMargin: 7
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2
        Text {
            width: parent.width
            text: MediaController.active ? s.title : "Tune"
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            color: "white"
        }
        Text {
            width: parent.width
            text: MediaController.active ? (s.artist || "") : "Not playing"
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.7)
        }
    }
}
