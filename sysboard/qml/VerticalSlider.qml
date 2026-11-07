// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// Tall Control Center slider (brightness, volume). Drag anywhere on it;
// the fill grows from the bottom, from nothing to the whole slider.
Rectangle {
    id: root

    property string iconName
    property real value: 0.5
    signal moved(real value)

    // While dragging it shows the finger, and the value again afterwards, so a
    // change from elsewhere (the volume keys) still moves it.
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, area.pressed ? dragValue : value))

    radius: width / 2
    color: Theme.glassButton
    scale: area.pressed ? 1.04 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    // A pill of its own, so it stays round at every level: below its own width
    // it is a circle that shrinks to nothing.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: root.shown * parent.height
        width: Math.min(parent.width, height)
        color: Qt.rgba(1, 1, 1, 0.92)
        radius: width / 2
    }

    Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        name: root.iconName
        size: 30
        color: root.shown > 0.22 ? "#2B2B2B" : "white"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        property real startY
        property real startValue
        onPressed: (m) => {
            startY = m.y
            startValue = root.shown
            root.dragValue = root.shown
        }
        onPositionChanged: (m) => {
            root.dragValue = Math.max(0, Math.min(1, startValue + (startY - m.y) / height))
            root.moved(root.dragValue)
        }
    }
}
