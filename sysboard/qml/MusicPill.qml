// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Compact now-playing control on the lock screen. Only exists while an app
// publishes a media session; colours follow the artwork.
Item {
    id: root

    readonly property var session: MediaController.session
    readonly property color accent: session.accent ? session.accent : "#E5213F"
    signal expandRequested()

    width: 176
    height: 64
    visible: appear.value > 0.01
    Spring { id: appear; to: MediaController.active ? 1 : 0; response: 0.5; dampingFraction: 0.72 }
    scale: 0.6 + 0.4 * appear.value

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.darker(root.accent, 2.1)
        opacity: appear.value
    }

    Item {
        anchors.fill: parent
        opacity: appear.value

        Rectangle {
            id: disc
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 52
            radius: 26
            color: root.accent
            // A NumberAnimation, not an Animator: Animators ignore "paused"
            // and the record kept turning with the music stopped.
            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 9000
                loops: Animation.Infinite
                running: root.visible && MediaController.active
                paused: running && !root.session.playing
            }
            Image {
                id: cover
                anchors.fill: parent
                source: root.session.artwork || ""
                sourceSize: Qt.size(104, 104)
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle { id: coverMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                visible: cover.status === Image.Ready
                source: cover
                maskEnabled: true
                maskSource: coverMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Rectangle {
                anchors.centerIn: parent
                width: 9
                height: 9
                radius: 4.5
                color: "#0B0B0B"
                border.color: "#5A5A5A"
                border.width: 1
            }
        }

        Column {
            anchors.left: disc.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.session.title || ""
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: "white"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.session.artist || root.session.album || ""
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.65)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14
                topPadding: 2
                Repeater {
                    model: [
                        { icon: "previous", action: "previous", size: 11 },
                        { icon: root.session.playing ? "pause" : "play", action: "toggle", size: 15 },
                        { icon: "next", action: "next", size: 11 }
                    ]
                    delegate: Icon {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData.icon
                        size: modelData.size
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: MediaController.command(parent.modelData.action)
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.expandRequested()
    }
}
