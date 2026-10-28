// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Account header: the AstraID the phone is signed in with, or "Not Logged In".
Rectangle {
    id: root

    signal clicked()

    readonly property string accountName: Settings.values["account.name"] || ""

    width: parent ? parent.width : 360
    height: 102
    radius: Theme.cardRadius
    color: area.pressed ? Theme.surfaceRaised : Theme.surface
    scale: area.pressed ? 0.98 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

    Rectangle {
        id: avatar
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 66
        height: 66
        radius: 33
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2BA6DE" }
            GradientStop { position: 1.0; color: "#0B4A6E" }
        }
        border.color: "#0E6C97"
        border.width: 2
        Text {
            anchors.centerIn: parent
            visible: root.accountName !== ""
            text: root.accountName.charAt(0).toUpperCase()
            font.family: Theme.fontFamily
            font.pixelSize: 30
            font.weight: Font.DemiBold
            color: "white"
        }
        Icon { anchors.centerIn: parent; visible: root.accountName === ""; name: "person"; size: 34 }
    }

    Column {
        anchors.left: avatar.right
        anchors.leftMargin: 16
        anchors.right: chevron.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2
        Text {
            width: parent.width
            text: root.accountName || qsTr("Not Logged In")
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            text: qsTr("AstraID")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            color: Theme.textSecondary
        }
    }
    Icon {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron-right"
        size: 24
    }
    MouseArea { id: area; anchors.fill: parent; onClicked: root.clicked() }
}
