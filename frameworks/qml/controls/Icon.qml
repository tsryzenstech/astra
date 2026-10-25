// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects

// A symbolic icon from the system icon set, optionally tinted.
//   Icon { name: "settings"; size: 24; color: "black" }
Item {
    id: root

    property string name
    property real size: 24
    property color color: "white"
    readonly property bool tinted: !Qt.colorEqual(color, "white") && !name.startsWith("weather-")

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image
        anchors.fill: parent
        source: root.name ? Qt.resolvedUrl("icons/" + root.name + ".svg") : ""
        sourceSize: Qt.size(Math.max(1, root.width * 2), Math.max(1, root.height * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: !root.tinted
        layer.enabled: root.tinted
    }

    // Tinting: a solid colour masked by the icon's alpha.
    Rectangle {
        id: fill
        anchors.fill: parent
        color: root.color
        visible: false
        layer.enabled: root.tinted
    }

    Loader {
        anchors.fill: parent
        active: root.tinted
        sourceComponent: MultiEffect {
            source: fill
            maskEnabled: true
            maskSource: image
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
}
