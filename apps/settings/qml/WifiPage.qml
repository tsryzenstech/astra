// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Wi-Fi: power, the current network, networks in range and the
// saved ones. Secured networks ask for their password.
Page {
    id: page
    title: qsTr("Wi-Fi")

    readonly property var wifi: Network.state.wifi || {}
    readonly property var networks: (wifi.networks || []).slice().sort((a, b) => (b.connected - a.connected) || (b.strength - a.strength))
    property string joining: ""
    property string error: ""

    Component.onCompleted: if (wifi.powered) Network.call("wifiScan", {}, null)
    Timer { interval: 15000; repeat: true; running: !!page.wifi.powered; onTriggered: Network.call("wifiScan", {}, null) }

    function connect(n, passphrase) {
        error = ""
        joining = n.id
        Network.call("wifiConnect", passphrase ? { id: n.id, passphrase: passphrase } : { id: n.id }, function(r, err) {
            page.joining = ""
            if (err)
                page.error = err.indexOf("passphrase") >= 0 ? qsTr("Wrong password for “%1”").arg(n.ssid) : err
        })
    }
    function select(n) {
        if (n.connected)
            stack.open(Qt.resolvedUrl("WifiNetworkPage.qml"), { network: n })
        else if (n.security === "open" || n.known)
            connect(n, "")
        else
            stack.open(Qt.resolvedUrl("WifiPasswordPage.qml"), { network: n, onJoin: (pw) => page.connect(n, pw) })
    }

    ListGroup {
        footer: page.wifi.available === false ? qsTr("No Wi-Fi hardware or service (iwd) was found on this device.") : ""
        ListItem {
            text: qsTr("Wi-Fi")
            showSwitch: true
            enabled: page.wifi.available !== false
            checked: !!page.wifi.powered
            separator: false
            onToggled: (on) => {
                Network.call("wifiSetPowered", { on: on }, null)
                if (on)
                    Network.call("wifiScan", {}, null)
            }
        }
    }

    Text {
        visible: page.error !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.error
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        color: Theme.danger
    }

    ListGroup {
        visible: !!page.wifi.powered
        title: qsTr("Networks")
        Repeater {
            model: page.networks
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.ssid
                subtitle: modelData.connected ? qsTr("Connected") : modelData.known ? qsTr("Saved") : ""
                selected: !!modelData.connected
                busy: page.joining === modelData.id
                chevron: !!modelData.connected
                separator: index < page.networks.length - 1
                onClicked: page.select(modelData)
                Icon {
                    visible: modelData.security !== "open"
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lock"
                    size: 15
                    color: Theme.textSecondary
                }
                WifiGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 14
                    strength: modelData.strength
                }
            }
        }
        ListItem {
            visible: page.networks.length === 0
            text: page.wifi.scanning ? qsTr("Searching…") : qsTr("No networks found")
            busy: !!page.wifi.scanning
            separator: false
        }
    }

    ListGroup {
        visible: (page.wifi.known || []).length > 0
        title: qsTr("Saved networks")
        Repeater {
            model: page.wifi.known || []
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.ssid
                value: qsTr("Forget")
                separator: index < (page.wifi.known || []).length - 1
                onClicked: Dialogs.show({
                    title: qsTr("Forget “%1”?").arg(modelData.ssid),
                    message: qsTr("The phone will stop joining this network automatically."),
                    icon: "wifi",
                    buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "forget", label: qsTr("Forget"), style: "destructive" } ]
                }, function(b) { if (b === "forget") Network.call("wifiForget", { ssid: modelData.ssid }, null) })
            }
        }
    }
}
