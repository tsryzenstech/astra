// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Web search entry point in Notification Center (opens Planet).
Rectangle {
    id: root

    signal activated(string mode)

    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.45)

    Rectangle {
        id: badge
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 55
        height: 55
        radius: width / 2
        color: "white"
        Image {
            anchors.centerIn: parent
            width: 40
            height: 40
            source: "icons/system/search-glyph.svg"
            sourceSize: Qt.size(80, 80)
        }
    }

    Rectangle {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: mic.left
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        height: 44
        radius: 22
        color: "black"
        Text {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Search the web")
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            color: "white"
        }
        MouseArea { anchors.fill: parent; onClicked: root.activated("ask") }
    }

    Rectangle {
        id: mic
        anchors.right: parent.right
        anchors.rightMargin: 21
        anchors.verticalCenter: parent.verticalCenter
        width: 46
        height: 46
        radius: 23
        color: "black"
        Icon { anchors.centerIn: parent; name: "mic"; size: 27 }
        MouseArea { anchors.fill: parent; onClicked: root.activated("voice") }
    }
}
