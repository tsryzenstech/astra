// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects

// Square app artwork clipped to the astraOS icon shape.
Item {
    id: root

    property url source
    property real size: 60
    property bool round: false // circular badge (notifications)
    readonly property real radius: round ? size / 2 : size * Theme.iconRadiusRatio

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        visible: false
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
