// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Window
import Astra.Core

// Square app artwork in the astraOS icon shape.
Item {
    id: root

    property url source
    property real size: 60
    property bool round: false // circular badge (notifications)
    readonly property real radiusRatio: round ? 0.5 : Theme.iconRadiusRatio
    readonly property real radius: size * radiusRatio
    // In steps, so that an icon growing into an app does not draw it again each frame.
    readonly property int pixels: {
        const wanted = size * Screen.devicePixelRatio
        return wanted <= 128 ? 128 : wanted <= 256 ? 256 : 512
    }

    implicitWidth: size
    implicitHeight: size

    Image {
        anchors.fill: parent
        source: IconImages.rounded(root.source, root.radiusRatio)
        sourceSize: Qt.size(root.pixels, root.pixels)
        smooth: true
    }
}
