// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Account header: device owner and nebula ID.
Rectangle {
    width: parent ? parent.width : 360
    height: 102
    radius: 24
    color: Theme.surface

    Rectangle {
        id: avatar
        x: 12
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
        Icon { anchors.centerIn: parent; name: "person"; size: 34 }
    }

    Column {
        anchors.left: avatar.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2
        Text {
            width: parent.width
            text: Settings.values["account.name"] || "astra user"
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            text: Settings.values["account.service"] || "nebula ID"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            color: Theme.textSecondary
        }
    }
}
