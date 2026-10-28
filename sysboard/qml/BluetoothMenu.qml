// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Control Center > Bluetooth (long press): on/off and paired devices.
// Tap a device to connect or disconnect it.
Item {
    id: root

    signal settingsRequested()

    readonly property var bt: Network.state.bluetooth || {}
    readonly property var paired: (bt.devices || []).filter(d => d.paired)
    property string busy: ""

    function iconFor(kind) {
        if (!kind)
            return "bluetooth"
        if (kind.indexOf("headphones") >= 0 || kind.indexOf("headset") >= 0)
            return "headphones"
        if (kind.indexOf("audio") >= 0)
            return "speaker"
        if (kind.indexOf("computer") >= 0)
            return "devices"
        if (kind.indexOf("phone") >= 0)
            return "phone"
        return "bluetooth"
    }

    Row {
        x: 22
        y: 22
        spacing: 12
        Rectangle {
            width: 42
            height: 42
            radius: 21
            color: root.bt.powered ? Theme.highlight : Qt.rgba(1, 1, 1, 0.12)
            Icon { anchors.centerIn: parent; name: "bluetooth"; size: 22 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: qsTr("Bluetooth")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 2
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                text: root.bt.powered ? qsTr("Visible as “%1”").arg(root.bt.name || "") : qsTr("Off")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
        }
    }
    Switch {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 29
        checked: !!root.bt.powered
        onToggled: (on) => Network.call("btSetPowered", { on: on }, null)
    }

    ListView {
        id: list
        x: 12
        y: 84
        width: parent.width - 24
        height: parent.height - y - 64
        clip: true
        visible: !!root.bt.powered
        model: root.paired
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        header: Item {
            width: list.width
            height: 30
            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("My devices")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
                color: Theme.textTertiary
            }
        }
        delegate: Rectangle {
            id: row
            required property var modelData
            width: list.width
            height: 56
            radius: Theme.radius
            color: rowArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            Rectangle {
                id: badge
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: 19
                color: row.modelData.connected ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
                Icon { anchors.centerIn: parent; name: root.iconFor(row.modelData.icon); size: 20 }
            }
            Column {
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: row.modelData.name
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.weight: Font.Medium
                    color: "white"
                }
                Text {
                    text: row.modelData.connected ? qsTr("Connected") : qsTr("Not connected")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize + 1
                    color: row.modelData.connected ? Theme.accent : Theme.textTertiary
                }
            }
            Spinner {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                running: root.busy === row.modelData.address
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                enabled: root.busy === ""
                onClicked: {
                    const d = row.modelData
                    if (d.connected) {
                        Network.call("btDisconnect", { address: d.address }, null)
                    } else {
                        root.busy = d.address
                        Network.call("btConnect", { address: d.address }, function() { root.busy = "" })
                    }
                }
            }
        }
    }

    Text {
        visible: !root.bt.powered || root.paired.length === 0
        anchors.centerIn: parent
        width: parent.width - 60
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.bt.available === false ? qsTr("This device has no Bluetooth")
              : !root.bt.powered ? qsTr("Bluetooth is off") : qsTr("No paired devices yet")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.textSecondary
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        x: 12
        width: parent.width - 24
        height: 44
        radius: 22
        color: settingsArea.pressed ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
        Text {
            anchors.centerIn: parent
            text: qsTr("Bluetooth Settings")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            font.weight: Font.Medium
            color: "white"
        }
        MouseArea { id: settingsArea; anchors.fill: parent; onClicked: root.settingsRequested() }
    }
}
