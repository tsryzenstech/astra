// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// A row of mutually exclusive options with a sliding pill.
//   SegmentedControl { model: [qsTr("Day"), qsTr("Week")]; currentIndex: 0; onActivated: (i) => ... }
Item {
    id: root

    property var model: []
    property int currentIndex: 0
    signal activated(int index)

    implicitWidth: 280
    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceRaised
    }

    Rectangle {
        readonly property real segment: root.width / Math.max(1, root.model.length)
        width: segment - 6
        height: root.height - 6
        y: 3
        x: 3 + segment * root.currentIndex
        radius: height / 2
        color: Theme.accent
        Behavior on x { SpringNumberAnimation { preset: Motion.bouncy } }
    }

    Row {
        anchors.fill: parent
        Repeater {
            model: root.model
            delegate: Item {
                required property int index
                required property var modelData
                width: root.width / Math.max(1, root.model.length)
                height: root.height
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize + 1
                    font.weight: index === root.currentIndex ? Font.DemiBold : Font.Medium
                    color: index === root.currentIndex ? "white" : Theme.textSecondary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.currentIndex = index
                        root.activated(index)
                    }
                }
            }
        }
    }
}
