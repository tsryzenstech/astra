// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls

// Control Center > media tile (long press): the full player.
Item {
    id: root

    signal openRequested(string pkg)

    readonly property var session: MediaController.session
    readonly property color accent: session.accent ? session.accent : Theme.accent

    function formatTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    property real position: 0
    Timer {
        interval: 250
        running: root.visible && MediaController.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const s = root.session
            const base = s.position || 0
            root.position = s.playing ? base + (Date.now() - (s.updated || Date.now())) : base
        }
    }

    // Artwork with an accent glow
    Rectangle {
        id: artFrame
        anchors.horizontalCenter: parent.horizontalCenter
        y: 26
        width: 196
        height: 196
        radius: Theme.cardRadius
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(root.accent, 1.15) }
            GradientStop { position: 1; color: Qt.darker(root.accent, 1.5) }
        }
        Image {
            id: art
            anchors.fill: parent
            anchors.margins: 0
            source: root.session.artwork || ""
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        Rectangle { id: artMask; anchors.fill: parent; radius: parent.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            visible: art.status === Image.Ready
            source: art
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Icon {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            name: "music"
            size: 72
        }
    }

    Column {
        x: 26
        y: artFrame.y + artFrame.height + 22
        width: parent.width - 52
        spacing: 2
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: MediaController.active ? root.session.title || "" : qsTr("Not Playing")
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize + 2
            font.weight: Font.Bold
            color: "white"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: MediaController.active ? (root.session.artist || root.session.appName || "") : ""
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }
        Item { width: 1; height: 14 }
        ProgressBar {
            width: parent.width
            height: 7
            color: "white"
            trackColor: Qt.rgba(1, 1, 1, 0.22)
            value: root.session.duration > 0 ? root.position / root.session.duration : 0
            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                enabled: MediaController.active
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
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "-" + root.formatTime((root.session.duration || 0) - root.position)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        spacing: 30
        opacity: MediaController.active ? 1 : 0.4
        IconButton { iconName: "previous"; size: 52; color: Qt.rgba(1, 1, 1, 0.1); enabled: MediaController.active; onClicked: MediaController.command("previous") }
        IconButton {
            iconName: root.session.playing ? "pause" : "play"
            size: 68
            color: root.accent
            enabled: MediaController.active
            onClicked: MediaController.command("toggle")
        }
        IconButton { iconName: "next"; size: 52; color: Qt.rgba(1, 1, 1, 0.1); enabled: MediaController.active; onClicked: MediaController.command("next") }
    }

    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 16
        size: 36
        iconName: "chevron-right"
        color: Qt.rgba(1, 1, 1, 0.1)
        onClicked: root.openRequested(root.session.package || "")
    }
}
