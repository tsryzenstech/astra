// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: what's playing, with play / pause.
Item {
    id: root
    property string size: "small"
    readonly property bool active: MediaController.active
    readonly property var s: MediaController.session
    Rectangle {
        width: root.size === "small" ? 56 : parent.height
        height: width
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.12)
        clip: true
        Image { anchors.fill: parent; source: root.s.artwork || ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
        Icon { anchors.centerIn: parent; name: "music"; size: 26; visible: !root.s.artwork }
    }
    Column {
        x: root.size === "small" ? 0 : parent.height + 14
        y: root.size === "small" ? 66 : 8
        width: parent.width - x
        Text { width: parent.width; elide: Text.ElideRight; text: root.active ? root.s.title || "" : qsTr("Not Playing"); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
        Text { width: parent.width; elide: Text.ElideRight; text: root.active ? root.s.artist || "" : "Tune"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.7) }
    }
    Row {
        visible: root.active && root.size !== "small"
        x: parent.height + 14
        anchors.bottom: parent.bottom
        spacing: 18
        IconButton { iconName: "previous"; size: 36; color: "transparent"; onClicked: MediaController.command("previous") }
        IconButton { iconName: root.s.playing ? "pause" : "play"; size: 40; color: Qt.rgba(1, 1, 1, 0.2); onClicked: MediaController.command("toggle") }
        IconButton { iconName: "next"; size: 36; color: "transparent"; onClicked: MediaController.command("next") }
    }
}
