// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

Rectangle {
    id: root

    property string iconName
    signal clicked()

    radius: width / 2
    color: Theme.glassButton
    scale: area.pressed ? 0.9 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: parent.width * 0.48
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
