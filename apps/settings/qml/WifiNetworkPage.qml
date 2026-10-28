// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// The network the phone is connected to.
Page {
    id: page
    property var network: ({})
    title: network.ssid || qsTr("Network")

    readonly property var live: {
        for (const n of ((Network.state.wifi || {}).networks || []))
            if (n.id === network.id)
                return n
        return network
    }

    ListGroup {
        ListItem { text: qsTr("Status"); value: page.live.connected ? qsTr("Connected") : qsTr("Not connected") }
        ListItem { text: qsTr("Signal"); value: (page.live.strength || 0) + "%" }
        ListItem {
            text: qsTr("Security")
            value: page.live.security === "open" ? qsTr("None") : page.live.security === "8021x" ? qsTr("Enterprise") : "WPA2/WPA3"
            separator: false
        }
    }

    ListGroup {
        ListItem {
            visible: !!page.live.connected
            text: qsTr("Disconnect")
            textColor: Theme.accent
            onClicked: Network.call("wifiDisconnect", {}, null)
        }
        ListItem {
            text: qsTr("Forget This Network")
            destructive: true
            separator: false
            onClicked: Dialogs.show({
                title: qsTr("Forget “%1”?").arg(page.network.ssid),
                message: qsTr("The phone will stop joining this network automatically."),
                icon: "wifi",
                buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "forget", label: qsTr("Forget"), style: "destructive" } ]
            }, function(b) {
                if (b === "forget") {
                    Network.call("wifiForget", { ssid: page.network.ssid }, null)
                    page.stack.pop()
                }
            })
        }
    }
}
