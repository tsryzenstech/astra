// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Centered icon, title and message for empty lists.
Column {
    id: root

    property string iconName: "info"
    property string title
    property string message

    width: parent ? parent.width : implicitWidth
    spacing: 10
    topPadding: 40
    bottomPadding: 40

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 72
        height: 72
        radius: 36
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.accent }
            GradientStop { position: 1; color: Theme.accentDeep }
        }
        Icon { anchors.centerIn: parent; name: root.iconName; size: 34 }
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headlineSize + 1
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
}
