// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// One row of an app's sidebar: an icon and a label, highlighted when it is the place being shown.
Rectangle {
    id: root

    property string text
    property string iconName
    property bool selected: false
    signal clicked()

    implicitWidth: 180
    implicitHeight: 34
    radius: Theme.radiusSmall
    color: selected ? Theme.accent : area.containsMouse ? Theme.surfaceRaised : "transparent"

    Icon {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        name: root.iconName
        size: 18
        color: root.selected ? Theme.accentText : Theme.accent
    }
    Text {
        x: 38
        width: parent.width - 48
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        color: root.selected ? Theme.accentText : Theme.text
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
