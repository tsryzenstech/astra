// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core

// A symbolic icon from the system icon set, optionally tinted.
//   Icon { name: "settings"; size: 24; color: "black" }
Item {
    id: root

    property string name
    property real size: 24
    property color color: "white"
    readonly property bool tinted: !Qt.colorEqual(color, "white") && !name.startsWith("weather-")
    readonly property url file: name ? Qt.resolvedUrl("icons/" + name + ".svg") : ""

    implicitWidth: size
    implicitHeight: size

    Image {
        anchors.fill: parent
        source: root.tinted ? IconImages.tinted(root.file, root.color) : root.file
        sourceSize: Qt.size(Math.max(1, root.width * 3), Math.max(1, root.height * 3))
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
