// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// A small round button for an app's toolbar: an icon, dimmed when disabled, lit under the pointer.
Rectangle {
    id: root

    property string iconName
    property bool checked: false
    property string tip
    signal clicked()

    implicitWidth: 34
    implicitHeight: 34
    radius: width / 2
    color: checked ? Theme.surfacePressed : area.pressed ? Theme.surfacePressed : area.containsMouse ? Theme.surfaceRaised : "transparent"
    opacity: enabled ? 1 : 0.35

    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: 18
        color: Theme.text
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
