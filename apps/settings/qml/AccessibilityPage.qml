// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Accessibility.
Page {
    id: page
    title: qsTr("Accessibility")

    ListGroup {
        title: qsTr("Vision")
        ListItem {
            text: qsTr("Text size")
            value: Math.round(Theme.fontScale * 100) + "%"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Text size"), key: "display.font_scale",
                options: [ { value: 0.9, label: qsTr("Small") }, { value: 1, label: qsTr("Default") },
                           { value: 1.15, label: qsTr("Large") }, { value: 1.3, label: qsTr("Largest") } ] })
        }
        SwitchRow {
            text: qsTr("Night light")
            subtitle: qsTr("Tints the screen amber.")
            key: "display.night_light"
            separator: false
        }
    }

    ListGroup {
        title: qsTr("Motion")
        SwitchRow {
            text: qsTr("Reduce motion")
            subtitle: qsTr("Apps open without animations. Applies to apps opened from now on.")
            key: "accessibility.reduce_motion"
            separator: false
        }
    }
}
