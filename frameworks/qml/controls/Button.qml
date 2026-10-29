// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Pill shaped button.
Item {
    id: root

    property string text
    property string iconName
    property bool primary: true
    property bool destructive: false
    property bool enabled: true
    signal clicked()

    implicitWidth: Math.max(120, row.implicitWidth + 40)
    implicitHeight: 48
    opacity: enabled ? 1 : 0.4
    scale: area.pressed ? 0.96 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.destructive ? Theme.danger : root.primary ? Theme.accent : Theme.surfaceRaised
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon { visible: root.iconName !== ""; name: root.iconName; size: 20; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            font.weight: Font.DemiBold
            color: root.primary || root.destructive ? Theme.accentText : Theme.text
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
