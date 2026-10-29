// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Control Center > Focus: pick a Focus mode (or turn it off).
Item {
    id: root
    signal settingsRequested()

    Column {
        x: 22
        y: 22
        width: parent.width - 44
        spacing: 10

        Text {
            text: qsTr("Focus")
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.Bold
            color: "white"
        }
        Repeater {
            model: FocusModes.modes
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: FocusModes.current === modelData.id
                width: parent.width
                height: 54
                radius: 27
                color: on ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.1)
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38; height: 38; radius: 19
                    color: parent.modelData.color
                    Icon { anchors.centerIn: parent; name: parent.parent.modelData.icon; size: 20 }
                }
                Text {
                    x: 58
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: parent.on ? "#0B0B0F" : "white"
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.on
                    text: qsTr("On")
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: "#3A3A3C"
                }
                MouseArea { anchors.fill: parent; onClicked: FocusModes.toggle(parent.modelData.id) }
            }
        }
        Text {
            text: qsTr("Focus Settings")
            font.family: Theme.fontFamily
            font.pixelSize: 15
            color: Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.settingsRequested() }
        }
    }
}
