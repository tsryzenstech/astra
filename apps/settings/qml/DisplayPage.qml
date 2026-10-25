// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    title: "Display"

    ListGroup {
        title: "Brightness"
        Item {
            width: parent.width
            height: 64
            Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "brightness"; size: 18; opacity: 0.6 }
            Slider {
                x: 48
                width: parent.width - 96
                anchors.verticalCenter: parent.verticalCenter
                value: System.brightness
                onMoved: (v) => System.setBrightness(Math.max(0.02, v))
            }
            Icon { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; name: "brightness"; size: 26 }
        }
    }
}
