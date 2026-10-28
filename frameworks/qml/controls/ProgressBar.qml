// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Rounded progress (0..1), or a sweeping bar when indeterminate.
Item {
    id: root

    property real value: 0
    property bool indeterminate: false
    property color color: Theme.accent
    property color trackColor: Theme.surfaceRaised

    implicitWidth: 240
    implicitHeight: 8

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
        clip: true

        Rectangle {
            height: parent.height
            radius: height / 2
            width: root.indeterminate ? parent.width * 0.35 : Math.max(height, parent.width * Math.max(0, Math.min(1, root.value)))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.color }
                GradientStop { position: 1; color: Qt.lighter(root.color, 1.25) }
            }
            Behavior on width { enabled: !root.indeterminate; SpringNumberAnimation { preset: Motion.smooth } }
            SequentialAnimation on x {
                running: root.indeterminate
                loops: Animation.Infinite
                NumberAnimation { from: -track.width * 0.35; to: track.width; duration: 1100; easing.type: Easing.InOutQuad }
            }
        }
    }
}
