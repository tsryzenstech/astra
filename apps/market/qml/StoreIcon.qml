// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Controls

// An app's icon from Market's server, in the astraOS icon shape. Astra.Controls'
// AppIcon draws the files on the phone; on the systems before 27.0-rev5 it
// cannot load a picture from the network, so Market loads it itself.
Item {
    id: root

    property url source
    property real size: 60

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: root.size * Theme.iconRadiusRatio
        color: Theme.surfaceRaised
        visible: art.status !== Image.Ready
    }
    Image {
        id: art
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(256, 256)
        asynchronous: true
        smooth: true
        visible: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.size * Theme.iconRadiusRatio
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: art
        visible: art.status === Image.Ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
