// SPDX-License-Identifier: Apache-2.0
import QtQuick
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
            Image {
                anchors.centerIn: parent
                width: 22
                height: 22
                source: root.session.artwork || ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
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
                text: root.session.artist || root.session.appName || ""
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
