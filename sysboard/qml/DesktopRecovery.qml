// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The recovery environment of the live ISO, in the middle of the desktop: Install astraOS, Disk Utility, a web browser,
// a terminal, and Restart / Shut Down. It is what is there when nothing else is open.
Item {
    id: root

    property var shell
    readonly property var utilities: [
        { package: "com.astra.installer", label: qsTr("Install astraOS"), detail: qsTr("Put astraOS on a disk of this computer") },
        { package: "com.astra.diskutil", label: qsTr("Disk Utility"), detail: qsTr("Erase, format and partition disks") },
        { package: "org.astra.browser", label: qsTr("Browser"), detail: qsTr("Get help online, download what you need") },
        { package: "org.astra.terminal", label: qsTr("Terminal"), detail: qsTr("Commands, for the ones who know") }
    ]
    property string selected: "com.astra.installer"

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 520
        height: 98 + list.height + 84
        radius: Theme.sheetRadius
        color: Qt.rgba(0.08, 0.08, 0.1, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        Image {
            id: logo
            anchors.horizontalCenter: parent.horizontalCenter
            y: 26
            width: 64; height: 40
            source: Host.bootLogo
            fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 68
            text: qsTr("Utilities")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.DemiBold
            color: "white"
        }
        Column {
            id: list
            x: 24
            y: 98
            width: parent.width - 48
            spacing: 6
            Repeater {
                model: root.utilities
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var info: Packages.count >= 0 ? Packages.get(modelData.package) : ({})
                    readonly property bool on: root.selected === modelData.package
                    width: list.width
                    radius: Theme.radius
                    visible: !!info.package
                    color: on ? Theme.accent : hover.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    height: visible ? 56 : 0
                    AppIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 36; source: row.info.iconUrl || "" }
                    Column {
                        x: 60
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: row.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
                        Text { text: row.modelData.detail; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Qt.rgba(1, 1, 1, 0.7) }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: root.selected = row.modelData.package; onDoubleTapped: root.shell.launch(row.modelData.package, {}, null) }
                }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            spacing: 10
            Rectangle {
                width: 96; height: 38; radius: 19; color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: qsTr("Shut Down"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; font.weight: Font.DemiBold; color: "white" }
                TapHandler { onTapped: System.power("poweroff") }
            }
            Rectangle {
                width: 96; height: 38; radius: 19; color: Qt.rgba(1, 1, 1, 0.12)
                Text { anchors.centerIn: parent; text: qsTr("Restart"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; font.weight: Font.DemiBold; color: "white" }
                TapHandler { onTapped: System.power("reboot") }
            }
            Rectangle {
                width: 110; height: 38; radius: 19; color: Theme.accent
                Text { anchors.centerIn: parent; text: qsTr("Continue"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; font.weight: Font.DemiBold; color: Theme.accentText }
                TapHandler { onTapped: root.shell.launch(root.selected, {}, null) }
            }
        }
    }
}
