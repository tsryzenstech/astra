// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Horizontal slider (0..1 by default).
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    readonly property real position: (value - from) / (to - from)
    signal moved(real value)

    implicitWidth: 240
    implicitHeight: 32

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.surfaceRaised
        Rectangle {
            width: root.position * parent.width
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    Rectangle {
        width: 26
        height: 26
        radius: 13
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: root.position * (root.width - width)
        scale: area.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        function update(mx) {
            let v = root.from + Math.max(0, Math.min(1, mx / width)) * (root.to - root.from)
            if (root.stepSize > 0)
                v = Math.round(v / root.stepSize) * root.stepSize
            root.value = v
            root.moved(v)
        }
        onPressed: (m) => update(m.x)
        onPositionChanged: (m) => update(m.x)
    }
}
