// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Cellular Data: SIM and network, mobile data, roaming, the APN
// and airplane mode.
Page {
    id: page
    title: qsTr("Cellular Data")

    readonly property var cell: Network.state.cellular || {}
    property string error: ""

    ListGroup {
        ListItem {
            text: qsTr("Airplane mode")
            iconName: "airplane"
            showSwitch: true
            separator: false
            checked: !!Network.state.airplane
            onToggled: (on) => Network.call("setAirplane", { on: on }, null)
        }
    }

    ListGroup {
        title: qsTr("SIM")
        footer: !page.cell.available ? qsTr("No modem was found on this device.") : ""
        ListItem { text: qsTr("Operator"); value: page.cell.simPresent ? (page.cell.operator || "—") : qsTr("No SIM card") }
        ListItem { text: qsTr("Network"); value: page.cell.registered ? (page.cell.technology || "—") : qsTr("Not registered") }
        ListItem {
            text: qsTr("Signal")
            value: page.cell.registered ? (page.cell.signal || 0) + "%" : "—"
            separator: false
            CellularGlyph {
                anchors.verticalCenter: parent.verticalCenter
                barHeight: 12
                bars: page.cell.registered ? Math.max(1, Math.ceil((page.cell.signal || 0) / 25)) : 0
            }
        }
    }

    ListGroup {
        title: qsTr("Mobile data")
        ListItem {
            text: qsTr("Cellular Data")
            subtitle: page.cell.dataConnected ? qsTr("Connected") : ""
            showSwitch: true
            enabled: !!page.cell.simPresent && !Network.state.airplane
            checked: !!page.cell.dataEnabled
            onToggled: (on) => Network.call("cellSetData", { on: on }, function(r, err) { page.error = err || "" })
        }
        ListItem {
            text: qsTr("Data roaming")
            subtitle: qsTr("Use mobile data abroad. Charges may apply.")
            showSwitch: true
            enabled: !!page.cell.simPresent
            checked: !!page.cell.allowRoaming
            onToggled: (on) => Network.call("cellSetRoaming", { on: on }, null)
        }
        ListItem {
            text: qsTr("Access point (APN)")
            value: page.cell.apn || ""
            chevron: true
            separator: false
            enabled: !!page.cell.simPresent
            onClicked: stack.open(Qt.resolvedUrl("TextEditPage.qml"), {
                title: qsTr("Access point (APN)"), text: page.cell.apn || "", placeholder: "internet",
                onSave: (t) => Network.call("cellSetApn", { apn: t }, function(r, err) { page.error = err || "" }) })
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
}
