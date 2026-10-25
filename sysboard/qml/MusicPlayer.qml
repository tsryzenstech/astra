// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Expanded now-playing view on the lock screen (MusicPlayerConfig1.png).
// Swipe down to go back to the lock screen.
Item {
    id: root

    property bool expanded: false
    readonly property real progress: open.value
    readonly property var session: MediaController.session
    readonly property color accent: session.accent ? session.accent : "#E5213F"

    function drag(dy) {
        open.value = Math.max(0, 1 - dy / (height * 0.5))
    }
    function release(vy) {
        if (open.value < 0.65 || vy > 700)
            expanded = false
        open.animateTo(expanded ? 1 : 0, -vy / (height * 0.5))
    }

    onExpandedChanged: open.animateTo(expanded ? 1 : 0, 0)
    Connections {
        target: MediaController
        function onActiveChanged() { if (!MediaController.active) root.expanded = false }
    }

    visible: open.value > 0.01
    Spring { id: open; to: 0; response: 0.5; dampingFraction: 0.82 }

    function formatTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // Playback position, extrapolated between session updates.
    property real position: 0
    Timer {
        interval: 250
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const s = root.session
            const base = s.position || 0
            root.position = s.playing ? base + (Date.now() - (s.updated || Date.now())) : base
        }
    }

    Greeting {
        x: 22
        y: 98 - 30 * (1 - open.value)
        opacity: open.value
    }

    Item {
        id: disc
        width: Math.min(root.width - 44, 349)
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: 452 - height / 2
        scale: 0.55 + 0.45 * open.value
        opacity: Math.min(1, open.value * 1.4)

        Item {
            anchors.fill: parent
            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 9000
                loops: Animation.Infinite
                running: root.visible && !!root.session.playing
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.accent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.08) }
                    GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.12) }
                }
            }
            Image {
                anchors.centerIn: parent
                width: parent.width * 0.4
                height: width
                source: root.session.artwork || ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.19
                height: width
                radius: width / 2
                color: "#0B0B0B"
                border.color: "#5A5A5A"
                border.width: width * 0.08
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.32
                    height: width
                    radius: width / 2
                    color: Qt.darker(root.accent, 2.4)
                }
            }
        }
    }

    Rectangle {
        id: card
        x: 24
        width: parent.width - 48
        height: 168
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 37 - 60 * (1 - open.value)
        radius: 28
        color: Qt.rgba(0, 0, 0, 0.3)
        opacity: open.value

        Column {
            x: 35
            y: 28
            width: parent.width - 70
            spacing: 2
            Text {
                width: parent.width
                text: root.session.title || ""
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: "white"
            }
            Text {
                width: parent.width
                text: root.session.artist || ""
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Item { width: 1; height: 18 }
            Rectangle {
                width: parent.width
                height: 7
                radius: 3.5
                color: Qt.rgba(1, 1, 1, 0.3)
                Rectangle {
                    width: parent.width * Math.min(1, root.session.duration > 0 ? root.position / root.session.duration : 0)
                    height: parent.height
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: (m) => MediaController.command("seek", root.session.duration * m.x / width)
                }
            }
            Item {
                width: parent.width
                height: 20
                Text {
                    anchors.bottom: parent.bottom
                    text: root.formatTime(root.position)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: "-" + root.formatTime((root.session.duration || 0) - root.position)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            spacing: 34
            Repeater {
                model: [
                    { icon: "previous", action: "previous", size: 16 },
                    { icon: root.session.playing ? "pause" : "play", action: "toggle", size: 24 },
                    { icon: "next", action: "next", size: 16 }
                ]
                delegate: Icon {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.icon
                    size: modelData.size
                    opacity: 0.9
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        onClicked: MediaController.command(parent.modelData.action)
                    }
                }
            }
        }
    }
}
