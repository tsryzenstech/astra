// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Round button holding a symbolic icon.
Item {
    id: root

    property string iconName
    property real size: 44
    property color color: Theme.surfaceRaised
    property color iconColor: "white"
    property bool enabled: true
    signal clicked()
    signal pressAndHold()

    implicitWidth: size
    implicitHeight: size
    opacity: enabled ? 1 : 0.4
    scale: area.pressed ? 0.9 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.color
    }
    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.size * 0.5
        color: root.iconColor
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        enabled: root.enabled
        onClicked: root.clicked()
        onPressAndHold: root.pressAndHold()
    }
}
