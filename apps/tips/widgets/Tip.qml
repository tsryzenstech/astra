// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Lock screen widget (wide): tip of the day.
Item {
    readonly property var tips: [
        "Long press the lock screen to customize it",
        "Swipe down from the top right for Control Center",
        "Long press an app to rearrange your home screen",
        "Hold the torch button to turn it on"
    ]
    AppIcon {
        id: bulb
        anchors.verticalCenter: parent.verticalCenter
        size: 34
        round: true
        source: Qt.resolvedUrl("../icon.svg")
    }
    Text {
        anchors.left: bulb.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: tips[new Date().getDate() % tips.length]
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.9
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: "white"
    }
}
