// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// Tall Control Center slider (brightness, volume). Drag anywhere on it;
// the fill grows from the bottom.
Rectangle {
    id: root

    property string iconName
    property real value: 0.5
    signal moved(real value)

    radius: width / 2
    color: Theme.glassButton
    clip: true
    scale: area.pressed ? 1.04 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.max(0, Math.min(1, root.value)) * parent.height
        color: Qt.rgba(1, 1, 1, 0.92)
        radius: height > parent.height - parent.radius ? parent.radius : 0
    }

    Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        name: root.iconName
        size: 30
        color: root.value > 0.22 ? "#2B2B2B" : "white"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        property real startY
        property real startValue
        onPressed: (m) => {
            startY = m.y
            startValue = root.value
        }
        onPositionChanged: (m) => {
            const v = Math.max(0, Math.min(1, startValue + (startY - m.y) / height))
            root.value = v
            root.moved(v)
        }
    }
}
