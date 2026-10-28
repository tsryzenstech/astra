// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Control Center > Wi-Fi (long press): on/off and the networks in range.
// Tap a network to join it; secured networks ask for the password inline.
Item {
    id: root

    signal settingsRequested()

    readonly property var wifi: Network.state.wifi || {}
    property string askingFor: ""      // network id waiting for a password
    property string error: ""

    Component.onCompleted: if (wifi.powered) Network.call("wifiScan", {}, null)

    function join(n) {
        error = ""
        if (n.connected)
            return
        if (n.security !== "open" && !n.known) {
            askingFor = n.id
            return
        }
        Network.call("wifiConnect", { id: n.id }, function(r, err) { if (err) root.error = err })
    }

    // Header
    Row {
        x: 22
        y: 22
        spacing: 12
        Rectangle {
            width: 42
            height: 42
            radius: 21
            color: root.wifi.powered ? Theme.highlight : Qt.rgba(1, 1, 1, 0.12)
            Icon { anchors.centerIn: parent; name: "wifi"; size: 22 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: qsTr("Wi-Fi")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 2
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                text: !root.wifi.powered ? qsTr("Off") : root.wifi.state === "connected" ? root.wifi.ssid : qsTr("Not connected")
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
        checked: !!root.wifi.powered
        onToggled: (on) => {
            Network.call("wifiSetPowered", { on: on }, null)
            if (on)
                Network.call("wifiScan", {}, null)
        }
    }

    // Networks
    ListView {
        id: list
        x: 12
        y: 84
        width: parent.width - 24
        height: parent.height - y - 64
        clip: true
        visible: !!root.wifi.powered
        model: (root.wifi.networks || []).slice().sort((a, b) => (b.connected - a.connected) || (b.strength - a.strength))
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds

        header: Item {
            width: list.width
            height: 30
            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Networks")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
                color: Theme.textTertiary
            }
            Spinner {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                size: 16
                running: !!root.wifi.scanning
            }
        }

        delegate: Column {
            id: row
            required property var modelData
            width: list.width
            readonly property bool asking: root.askingFor === modelData.id

            Rectangle {
                width: parent.width
                height: 52
                radius: Theme.radius
                color: rowArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : modelData.connected ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                WifiGlyph {
                    id: glyph
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 15
                    strength: row.modelData.strength
                    connecting: row.modelData.connected === false && root.wifi.state === "connecting" && root.wifi.ssid === row.modelData.ssid
                }
                Text {
                    anchors.left: glyph.right
                    anchors.leftMargin: 14
                    anchors.right: trailing.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.ssid
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                    color: "white"
                }
                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Icon { visible: row.modelData.security !== "open"; name: "lock"; size: 15; color: Theme.textSecondary }
                    Icon { visible: !!row.modelData.connected; name: "check"; size: 18; color: Theme.accent }
                }
                MouseArea { id: rowArea; anchors.fill: parent; onClicked: root.join(row.modelData) }
            }

            // Inline password
            Item {
                width: parent.width
                height: row.asking ? 60 : 0
                visible: row.asking
                TextField {
                    id: pass
                    x: 8
                    width: parent.width - joinButton.width - 24
                    height: 46
                    anchors.verticalCenter: parent.verticalCenter
                    placeholder: qsTr("Password")
                    echoMode: TextInput.Password
                    onAccepted: joinButton.clicked()
                    Component.onCompleted: if (row.asking) focusInput()
                }
                Button {
                    id: joinButton
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 90
                    height: 46
                    text: qsTr("Join")
                    enabled: pass.text.length >= 8
                    onClicked: {
                        const id = row.modelData.id
                        root.askingFor = ""
                        Network.call("wifiConnect", { id: id, passphrase: pass.text }, function(r, err) {
                            if (err)
                                root.error = err.indexOf("passphrase") >= 0 ? qsTr("Wrong password") : err
                        })
                    }
                }
            }
        }
    }

    Text {
        visible: !root.wifi.powered
        anchors.centerIn: parent
        width: parent.width - 60
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.wifi.available === false ? qsTr("This device has no Wi-Fi") : qsTr("Wi-Fi is off")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.textSecondary
    }

    Text {
        visible: root.error !== ""
        anchors.bottom: settingsRow.top
        anchors.bottomMargin: 4
        x: 22
        width: parent.width - 44
        text: root.error
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.danger
    }

    // Footer
    Rectangle {
        id: settingsRow
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        x: 12
        width: parent.width - 24
        height: 44
        radius: 22
        color: settingsArea.pressed ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
        Text {
            anchors.centerIn: parent
            text: qsTr("Wi-Fi Settings")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            font.weight: Font.Medium
            color: "white"
        }
        MouseArea { id: settingsArea; anchors.fill: parent; onClicked: root.settingsRequested() }
    }
}
