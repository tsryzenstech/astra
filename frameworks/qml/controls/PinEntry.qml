// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// PIN prompt with dots and a round keypad, for apps (Settings uses it to
// set the PIN and to confirm sensitive changes).
//   PinEntry { title: qsTr("Enter your PIN"); length: 4; onEntered: (pin) => ... }
Column {
    id: root

    property string title
    property string message
    property int length: 4          // digits; 0 = 4 to 8 digits, confirmed with OK
    property string pin: ""
    signal entered(string pin)

    function clear() { pin = "" }
    function shake() { shakeAnim.restart(); pin = "" }

    width: parent ? parent.width : 320
    spacing: 22

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.titleSize - 2
        font.weight: Font.DemiBold
        color: Theme.text
    }
    Text {
        visible: root.message !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.message
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        color: Theme.textSecondary
    }

    Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16
        height: 16
        Repeater {
            model: root.length > 0 ? root.length : Math.max(4, root.pin.length)
            delegate: Rectangle {
                required property int index
                width: 14
                height: 14
                radius: 7
                color: index < root.pin.length ? Theme.accent : "transparent"
                border.width: 2
                border.color: index < root.pin.length ? Theme.accent : Theme.textTertiary
                scale: index === root.pin.length - 1 ? 1.15 : 1
                Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
            }
        }
        SequentialAnimation on anchors.horizontalCenterOffset {
            id: shakeAnim
            running: false
            NumberAnimation { to: -18; duration: 50 }
            NumberAnimation { to: 16; duration: 70 }
            NumberAnimation { to: -10; duration: 70 }
            NumberAnimation { to: 6; duration: 60 }
            NumberAnimation { to: 0; duration: 50 }
        }
    }

    Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        columnSpacing: 22
        rowSpacing: 14
        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "ok", "0", "del"]
            delegate: Item {
                required property string modelData
                width: 72
                height: 72
                readonly property bool isKey: modelData.length === 1
                // Hidden, not removed: the Grid keeps "0" in the middle column.
                opacity: modelData !== "ok" || root.length === 0 ? 1 : 0
                enabled: opacity > 0
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: parent.isKey ? (key.pressed ? Theme.surfacePressed : Theme.surfaceRaised)
                                        : (key.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    scale: key.pressed ? 0.92 : 1
                    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                }
                Text {
                    anchors.centerIn: parent
                    visible: parent.modelData !== "del"
                    text: parent.modelData === "ok" ? qsTr("OK") : parent.modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: parent.isKey ? 28 : Theme.headlineSize
                    font.weight: parent.isKey ? Font.Normal : Font.DemiBold
                    color: parent.modelData === "ok" ? Theme.accent : Theme.text
                }
                Icon { anchors.centerIn: parent; visible: parent.modelData === "del"; name: "backspace"; size: 28 }
                MouseArea {
                    id: key
                    anchors.fill: parent
                    onClicked: {
                        const k = parent.modelData
                        if (k === "del") {
                            root.pin = root.pin.slice(0, -1)
                        } else if (k === "ok") {
                            if (root.pin.length >= 4)
                                root.entered(root.pin)
                        } else if (root.length === 0 ? root.pin.length < 8 : root.pin.length < root.length) {
                            root.pin += k
                            if (root.length > 0 && root.pin.length === root.length)
                                Qt.callLater(function() { root.entered(root.pin) })
                        }
                    }
                }
            }
        }
    }
}
