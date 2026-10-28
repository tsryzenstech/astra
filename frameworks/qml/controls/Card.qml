// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Rounded surface for free-form content. With `accented` it uses the
// accent gradient (the playful, vivid surfaces of the design language).
Rectangle {
    id: root

    default property alias content: inner.data
    property real padding: 18
    property bool accented: false
    property bool pressable: false
    signal clicked()

    width: parent ? parent.width : implicitWidth
    implicitHeight: inner.childrenRect.height + 2 * padding
    radius: Theme.cardRadius
    color: Theme.surface
    gradient: accented ? accentGradient : null
    scale: pressable && area.pressed ? 0.97 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

    Gradient {
        id: accentGradient
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Theme.accent }
        GradientStop { position: 1; color: Theme.accentDeep }
    }

    Item {
        id: inner
        x: root.padding
        y: root.padding
        width: root.width - 2 * root.padding
        height: childrenRect.height
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.pressable
        onClicked: root.clicked()
    }
}
