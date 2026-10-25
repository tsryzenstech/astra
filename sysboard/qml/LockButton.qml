// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// Round lock screen shortcut. Activated by a long press: the button grows
// while it is held and fires once fully grown.
Item {
    id: root

    property string iconName
    property bool checked: false
    signal activated()

    width: 40
    height: 40

    Spring { id: grow; to: area.pressed ? 1 : 0; response: area.pressed ? 0.55 : 0.35; dampingFraction: area.pressed ? 1.0 : 0.6 }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        scale: 1 + 0.45 * grow.value
        color: root.checked ? "white" : Qt.rgba(0, 0, 0, 0.72)
        Behavior on color { ColorAnimation { duration: 160 } }

        Icon {
            anchors.centerIn: parent
            name: root.iconName
            size: 21
            color: root.checked ? "black" : "white"
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -10
        pressAndHoldInterval: 420
        onPressAndHold: root.activated()
    }
}
