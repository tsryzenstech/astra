// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// Wi-Fi / Bluetooth pill: tap toggles; the chevron or a long press opens
// the menu.
Rectangle {
    id: root

    property string iconName
    property string text
    property string subtitle
    property bool checked: false
    signal toggled()
    signal details()
    signal pressAndHold()

    radius: height / 2
    color: checked ? Theme.highlight : Theme.glassButton
    Behavior on color { ColorAnimation { duration: 180 } }
    scale: area.pressed ? 0.95 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    Icon {
        id: glyph
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        name: root.iconName
        size: 23
    }
    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.right: chevron.left
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: root.text
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Bold
            color: "white"
        }
        Text {
            visible: root.subtitle !== ""
            width: parent.width
            text: root.subtitle
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.78)
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        pressAndHoldInterval: 420
        onClicked: root.toggled()
        onPressAndHold: root.pressAndHold()
    }
    Rectangle {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 27
        height: 27
        radius: 13.5
        color: root.checked ? Qt.darker(Theme.highlight, 1.45) : Qt.rgba(1, 1, 1, 0.12)
        Icon { anchors.centerIn: parent; name: "chevron-right"; size: 15 }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.details() }
    }
}
