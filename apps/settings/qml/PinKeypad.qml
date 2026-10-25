// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Numeric keypad with PIN dots (works without an on-screen keyboard).
Column {
    id: root

    property string value: ""
    property int maxLength: 8
    property int dots: Math.max(4, value.length)
    signal submitted(string value)

    function clear() { value = "" }

    spacing: 22

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 18
        Repeater {
            model: root.dots
            Rectangle {
                required property int index
                width: 14
                height: 14
                radius: 7
                color: index < root.value.length ? "white" : "transparent"
                border.color: "white"
                border.width: 1.5
            }
        }
    }

    Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        columnSpacing: 22
        rowSpacing: 14
        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"]
            delegate: Rectangle {
                required property string modelData
                width: 72
                height: 72
                radius: 36
                color: key.pressed ? Qt.rgba(1, 1, 1, 0.3) : Theme.surfaceRaised
                opacity: modelData === "OK" && root.value.length < 4 ? 0.35 : 1
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: parent.modelData.length > 1 ? 18 : 28
                    font.weight: parent.modelData === "OK" ? Font.DemiBold : Font.Light
                    color: parent.modelData === "OK" ? Theme.accent : "white"
                }
                MouseArea {
                    id: key
                    anchors.fill: parent
                    onClicked: {
                        const k = parent.modelData
                        if (k === "⌫")
                            root.value = root.value.slice(0, -1)
                        else if (k === "OK") {
                            if (root.value.length >= 4)
                                root.submitted(root.value)
                        } else if (root.value.length < root.maxLength)
                            root.value += k
                    }
                }
            }
        }
    }
}
