// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Bluetooth: power, the phone's name, paired devices and
// discovery of new ones.
Page {
    id: page
    title: qsTr("Bluetooth")

    readonly property var bt: Network.state.bluetooth || {}
    readonly property var paired: (bt.devices || []).filter(d => d.paired)
    readonly property var nearby: (bt.devices || []).filter(d => !d.paired)
    property string busy: ""
    property string error: ""

    Component.onCompleted: if (bt.powered) Network.call("btDiscover", { on: true }, null)
    Component.onDestruction: Network.call("btDiscover", { on: false }, null)

    function iconFor(kind) {
        kind = kind || ""
        if (kind.indexOf("headphones") >= 0 || kind.indexOf("headset") >= 0) return "headphones"
        if (kind.indexOf("audio") >= 0) return "speaker"
        if (kind.indexOf("computer") >= 0) return "devices"
        if (kind.indexOf("phone") >= 0) return "phone"
        return "bluetooth"
    }
    function run(method, d) {
        busy = d.address
        error = ""
        Network.call(method, { address: d.address }, function(r, err) {
            page.busy = ""
            if (err)
                page.error = qsTr("Could not reach %1").arg(d.name)
        })
    }

    ListGroup {
        footer: page.bt.powered ? qsTr("Visible to nearby devices as “%1” while this page is open.").arg(page.bt.name || "") : ""
        ListItem {
            text: qsTr("Bluetooth")
            showSwitch: true
            enabled: page.bt.available !== false
            checked: !!page.bt.powered
            onToggled: (on) => {
                Network.call("btSetPowered", { on: on }, null)
                if (on)
                    Network.call("btDiscover", { on: true }, null)
            }
        }
        ListItem {
            text: qsTr("Device name")
            value: page.bt.name || ""
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("TextEditPage.qml"), {
                title: qsTr("Device name"), text: page.bt.name || "", maximumLength: 32,
                onSave: (t) => Network.call("btSetName", { name: t }, null) })
        }
    }

    Text {
        visible: page.error !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: page.error
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        color: Theme.danger
    }

    ListGroup {
        visible: !!page.bt.powered && page.paired.length > 0
        title: qsTr("My devices")
        Repeater {
            model: page.paired
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                subtitle: modelData.connected ? qsTr("Connected") : qsTr("Not connected")
                iconName: page.iconFor(modelData.icon)
                busy: page.busy === modelData.address
                separator: index < page.paired.length - 1
                onClicked: page.run(modelData.connected ? "btDisconnect" : "btConnect", modelData)
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "more"
                    color: Theme.surfaceRaised
                    onClicked: Dialogs.show({
                        title: modelData.name,
                        message: qsTr("Forgetting a device removes its pairing. You can pair it again later."),
                        icon: page.iconFor(modelData.icon),
                        buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "forget", label: qsTr("Forget Device"), style: "destructive" } ]
                    }, function(b) { if (b === "forget") Network.call("btForget", { address: modelData.address }, null) })
                }
            }
        }
    }

    ListGroup {
        visible: !!page.bt.powered
        title: qsTr("Other devices")
        Repeater {
            model: page.nearby
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                iconName: page.iconFor(modelData.icon)
                busy: page.busy === modelData.address
                separator: index < page.nearby.length - 1
                onClicked: page.run("btPair", modelData)
            }
        }
        ListItem {
            visible: page.nearby.length === 0
            text: page.bt.discovering ? qsTr("Searching…") : qsTr("No devices found")
            busy: !!page.bt.discovering
            separator: false
        }
    }
}
