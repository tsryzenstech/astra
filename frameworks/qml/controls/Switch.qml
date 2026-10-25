// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// iOS style switch with a springy knob (SettingsHome.png).
// It does not change `checked` by itself: bind `checked` to the real state
// and update that state in onToggled, so the switch always tells the truth.
Item {
    id: root

    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    implicitWidth: 54
    implicitHeight: 28
    opacity: enabled ? 1 : 0.4

    Spring {
        id: knob
        to: root.checked ? 1 : 0
        response: 0.32
        dampingFraction: 0.72
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.tint(Theme.switchOff, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Math.max(0, Math.min(1, knob.value))))
    }

    Rectangle {
        width: parent.height - 4 + (press.pressed ? 6 : 0)
        height: parent.height - 4
        radius: height / 2
        y: 2
        x: 2 + knob.value * (root.width - width - 4)
        color: "white"
        Behavior on width { SpringNumberAnimation { preset: Motion.snappy } }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        anchors.margins: -8
        enabled: root.enabled
        onClicked: root.toggled(!root.checked)
    }
}
