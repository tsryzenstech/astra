// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Shared screen for apps that are still being built.
Rectangle {
    id: root

    property string name
    property url icon
    property string description
    property color accent: Theme.accent
    default property alias extra: extraColumn.data

    color: Theme.background

    Rectangle {
        // Soft glow in the app colour behind the icon.
        width: parent.width * 1.2
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.12 - height / 2
        opacity: 0.22
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.accent }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Column {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.24
        width: parent.width - 64
        spacing: 14

        Spring { id: appear; value: 0; to: 1; response: 0.55; dampingFraction: 0.7 }

        AppIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.icon
            size: 96
            scale: 0.6 + 0.4 * appear.value
            opacity: Math.min(1, appear.value * 1.5)
        }
        Item { width: 1; height: 6 }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.name
            font.family: Theme.fontFamily
            font.pixelSize: 32
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.description
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: soon.implicitWidth + 28
            height: 30
            radius: 15
            color: Theme.surfaceRaised
            Text {
                id: soon
                anchors.centerIn: parent
                text: qsTr("Coming soon to astraOS")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                font.weight: Font.Medium
                color: Theme.text
            }
        }
        Column {
            id: extraColumn
            width: parent.width
            spacing: 12
        }
    }
}
