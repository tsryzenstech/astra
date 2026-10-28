// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Now playing tile in Control Center.
Rectangle {
    id: root

    readonly property var session: MediaController.session
    signal openRequested(string pkg)
    signal expandRequested()

    radius: 30
    color: Theme.glassButton

    scale: tileArea.pressed ? 0.96 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    // Tap opens the player app, long press expands the tile.
    MouseArea {
        id: tileArea
        anchors.fill: parent
        pressAndHoldInterval: 420
        onClicked: root.openRequested(root.session.package || "")
        onPressAndHold: root.expandRequested()
    }

    Item {
        anchors.fill: parent
        anchors.margins: 16

        Image {
            id: art
            width: 44
            height: 44
            source: root.session.artwork || ""
            fillMode: Image.PreserveAspectCrop
            visible: MediaController.active && status === Image.Ready
        }
        AppIcon {
            visible: MediaController.active && !art.visible
            size: 44
            source: root.session.iconUrl || ""
        }
        Icon {
            visible: !MediaController.active
            name: "sound"
            size: 30
            opacity: 0.5
        }

        Column {
            y: 58
            width: parent.width
            Text {
                width: parent.width
                text: MediaController.active ? root.session.title : qsTr("Not Playing")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                width: parent.width
                text: MediaController.active ? (root.session.artist || root.session.appName) : "Tune"
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 15
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 26
            opacity: MediaController.active ? 1 : 0.4
            Repeater {
                model: [
                    { icon: "previous", action: "previous", size: 15 },
                    { icon: root.session.playing ? "pause" : "play", action: "toggle", size: 22 },
                    { icon: "next", action: "next", size: 15 }
                ]
                delegate: Icon {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.icon
                    size: modelData.size
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        enabled: MediaController.active
                        onClicked: MediaController.command(parent.modelData.action)
                    }
                }
            }
        }
    }
}
