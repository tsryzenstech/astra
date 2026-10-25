// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Lock screen widget (small): analog clock.
Item {
    id: root
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    Rectangle {
        id: face
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        radius: width / 2
        color: "white"

        component Hand: Rectangle {
            property real angle
            property real length
            x: face.width / 2 - width / 2
            y: face.height / 2 - length
            height: length
            radius: width / 2
            rotation: angle
            transformOrigin: Item.Bottom
        }
        Hand { width: 2.4; length: face.width * 0.27; color: "black"; angle: (root.now.getHours() % 12 + root.now.getMinutes() / 60) * 30 }
        Hand { width: 1.8; length: face.width * 0.38; color: "black"; angle: root.now.getMinutes() * 6 }
        Hand { width: 1; length: face.width * 0.4; color: "#E5213F"; angle: root.now.getSeconds() * 6 }
        Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: "black" }
    }
}
