// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// iOS style PIN pad.
Item {
    id: root

    readonly property real progress: appear.value
    property string entered: ""
    property string message: ""
    readonly property int length: Lock.pinLength > 0 ? Lock.pinLength : 4

    signal accepted()
    signal cancelled()

    function show() {
        entered = ""
        message = ""
        appear.animateTo(1, 0)
    }
    function hide(immediate) {
        entered = ""
        if (immediate)
            appear.snap(0)
        else
            appear.animateTo(0, 0)
    }

    function press(digit) {
        if (entered.length >= length || busy)
            return
        entered += digit
        if (entered.length === length)
            submit()
    }

    property bool busy: false
    function submit() {
        busy = true
        Lock.verify(entered, (ok, error) => {
            busy = false
            if (ok) {
                hide(false)
                root.accepted()
            } else {
                message = error ? error : "Wrong PIN"
                entered = ""
                shake.snap(1)
                shake.animateTo(0, 0)
            }
        })
    }

    visible: progress > 0.01
    enabled: progress > 0.5

    Spring { id: appear; to: 0; response: 0.4; dampingFraction: 0.86 }
    Spring { id: shake; to: 0; response: 0.22; dampingFraction: 0.18 }

    MouseArea { anchors.fill: parent } // swallow touches behind the pad

    Item {
        anchors.fill: parent
        opacity: root.progress
        scale: 1.08 - 0.08 * root.progress

        Text {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            y: 120
            text: root.message || "Enter PIN"
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.weight: Font.Medium
            color: "white"
        }

        Row {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: shake.value * 18
            y: title.y + 48
            spacing: 22
            Repeater {
                model: root.length
                Rectangle {
                    required property int index
                    width: 13
                    height: 13
                    radius: 6.5
                    color: index < root.entered.length ? "white" : "transparent"
                    border.color: "white"
                    border.width: 1.5
                }
            }
        }

        Grid {
            id: keys
            anchors.horizontalCenter: parent.horizontalCenter
            y: dots.y + 70
            columns: 3
            columnSpacing: 26
            rowSpacing: 16

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]
                delegate: Item {
                    required property string modelData
                    width: 78
                    height: 78
                    Rectangle {
                        visible: parent.modelData !== ""
                        anchors.fill: parent
                        radius: width / 2
                        color: key.pressed ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.16)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 34
                            font.weight: Font.Light
                            color: "white"
                        }
                        MouseArea {
                            id: key
                            anchors.fill: parent
                            onClicked: root.press(parent.parent.modelData)
                        }
                    }
                }
            }
        }

        Text {
            anchors.right: keys.right
            anchors.rightMargin: 14
            anchors.top: keys.bottom
            anchors.topMargin: 26
            text: root.entered.length > 0 ? "Delete" : "Cancel"
            font.family: Theme.fontFamily
            font.pixelSize: 17
            color: "white"
            MouseArea {
                anchors.fill: parent
                anchors.margins: -14
                onClicked: {
                    if (root.entered.length > 0) {
                        root.entered = root.entered.slice(0, -1)
                    } else {
                        root.hide(false)
                        root.cancelled()
                    }
                }
            }
        }
    }
}
