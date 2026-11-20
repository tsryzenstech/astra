// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Mouse & Trackpad (astraOS Desktop): how the pointer moves, and the gestures of a touchpad.
Page {
    id: page
    title: qsTr("Mouse & Trackpad")

    ListGroup {
        title: qsTr("Pointer")
        SliderRow {
            text: qsTr("Pointer speed")
            iconName: "sliders"
            key: "desktop.pointer.speed"
            fallback: 0
            from: -1
            to: 1
            valueText: ""
            separator: false
        }
    }

    ListGroup {
        title: qsTr("Trackpad")
        footer: qsTr("Two fingers scroll, and a click with two fingers is a right click.")
        SwitchRow {
            text: qsTr("Tap to click")
            key: "desktop.touchpad.tap"
            fallback: true
        }
        SwitchRow {
            text: qsTr("Natural scrolling")
            subtitle: qsTr("The content follows your fingers.")
            key: "desktop.touchpad.natural"
            fallback: true
            separator: false
        }
    }
}
