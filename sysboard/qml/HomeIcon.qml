// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// App icon on the home screen or in the dock.
Item {
    id: root

    property real iconSize: 62
    property alias source: art.source
    property string label
    property bool showLabel: true
    property bool pressed: false
    property bool jiggle: false
    property bool hidden: false

    width: iconSize
    height: iconSize
    opacity: hidden ? 0 : 1

    Item {
        id: body
        width: root.iconSize
        height: root.iconSize
        scale: root.pressed ? 0.9 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

        AppIcon {
            id: art
            size: root.iconSize
        }
        Rectangle {
            anchors.fill: parent
            radius: art.radius
            color: "black"
            opacity: root.pressed ? 0.28 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // Rearranging: a gentle wobble with a random phase per icon.
        SequentialAnimation on rotation {
            running: root.jiggle
            loops: Animation.Infinite
            alwaysRunToEnd: true
            PauseAnimation { duration: Math.round(Math.random() * 120) }
            NumberAnimation { to: 1.6; duration: 120; easing.type: Easing.InOutSine }
            NumberAnimation { to: -1.6; duration: 240; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 120; easing.type: Easing.InOutSine }
        }
    }

    Text {
        visible: root.showLabel
        width: root.iconSize + 34
        x: (root.iconSize - width) / 2
        y: root.iconSize + 6
        horizontalAlignment: Text.AlignHCenter
        text: root.label
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: 14
        color: "white"
    }
}
