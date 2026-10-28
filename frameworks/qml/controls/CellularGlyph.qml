// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Four rounded signal bars (0-4 lit) and the access technology ("5G").
Row {
    id: root

    property int bars: 4
    property string technology: ""
    property color color: "white"
    property real barHeight: 12

    spacing: 4
    height: barHeight

    Text {
        visible: root.technology !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.technology
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(root.barHeight * 1.05)
        color: root.color
    }

    Row {
        spacing: root.barHeight * 0.17
        height: root.barHeight
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                width: root.barHeight * 0.26
                height: root.barHeight * (0.4 + 0.2 * index)
                anchors.bottom: parent.bottom
                radius: width / 2
                color: root.color
                opacity: index < root.bars ? 1 : 0.3
            }
        }
    }
}
