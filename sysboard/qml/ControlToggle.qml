// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// Round Control Center toggle: pink when on.
Rectangle {
    id: root

    property string iconName
    property bool checked: false
    signal clicked()

    radius: width / 2
    color: checked ? Theme.highlight : Theme.glassButton
    Behavior on color { ColorAnimation { duration: 180 } }
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
