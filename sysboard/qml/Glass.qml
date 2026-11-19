// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects

// A frosted button or bar: what is behind it, blurred, under a light tint, with rounded corners.
Item {
    id: root

    property Item source
    property real radius: height / 2
    property color tint: Qt.rgba(1, 1, 1, 0.14)
    property bool clickable: true     // false when it holds controls of its own
    default property alias content: inner.data
    signal clicked()

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: glassMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        BlurLayer {
            readonly property point origin: root.source ? root.mapToItem(root.source, 0, 0) : Qt.point(0, 0)
            x: -origin.x
            y: -origin.y
            width: root.source ? root.source.width : 0
            height: root.source ? root.source.height : 0
            source: root.source
            amount: root.source && root.visible ? 1 : 0
            dim: 0
        }
        Rectangle { anchors.fill: parent; color: root.tint }
        Rectangle { anchors.fill: parent; color: "white"; opacity: area.pressed ? 0.18 : 0 }
    }
    Rectangle { id: glassMask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
    }
    Item { id: inner; anchors.fill: parent }
    MouseArea { id: area; anchors.fill: parent; enabled: root.clickable; onClicked: root.clicked() }
}
