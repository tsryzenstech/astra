// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Personal Hotspot: share the mobile data connection over Wi-Fi.
Page {
    id: page
    title: qsTr("Personal Hotspot")
    readonly property var hs: Network.state.hotspot || ({})
    readonly property var cell: Network.state.cellular || ({})
    property bool working: false
    property bool showPassword: false
    property string error: ""

    EmptyState {
        visible: !page.hs.supported
        iconName: "hotspot"
        title: qsTr("Personal Hotspot")
        message: qsTr("This phone has no Wi-Fi that can share the connection.")
    }
    ListGroup {
        visible: !!page.hs.supported
        footer: page.cell.dataConnected ? qsTr("Other devices can join “%1” and use this phone's mobile data. Wi-Fi is turned off while the hotspot is on.").arg(page.hs.name || "")
                                        : qsTr("Turn on Cellular Data to share the connection.")
        ListItem {
            text: qsTr("Allow Others to Join")
            iconName: "hotspot"
            iconTile: 30
            tileColor: "#34D058"
            showSwitch: true
            busy: page.working
            checked: !!page.hs.active
            separator: false
            onToggled: (on) => {
                page.working = true
                page.error = ""
                Network.call("setHotspot", { on: on }, function(r, error) { page.working = false; page.error = error || "" })
            }
        }
    }
    Text { visible: page.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: page.error; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
    ListGroup {
        visible: !!page.hs.supported
        ListItem {
            text: qsTr("Network Name")
            value: page.hs.name || ""
            chevron: true
            onClicked: page.stack.open(Qt.resolvedUrl("TextEditPage.qml"), { title: qsTr("Network Name"), text: Settings.values["hotspot.name"] || page.hs.name || "", placeholder: "astraOS",
                                                                             maximumLength: 32, onSave: (t) => Settings.setValue("hotspot.name", t) })
        }
        ListItem {
            text: qsTr("Wi-Fi Password")
            value: page.showPassword ? (Settings.values["hotspot.password"] || qsTr("Set when you turn it on")) : "••••••••"
            chevron: true
            separator: false
            onClicked: page.stack.open(Qt.resolvedUrl("TextEditPage.qml"), { title: qsTr("Wi-Fi Password"), text: Settings.values["hotspot.password"] || "", placeholder: qsTr("At least 8 characters"),
                                                                             onSave: (t) => { if (t.length >= 8) Settings.setValue("hotspot.password", t) } })
        }
    }
    ListGroup {
        visible: !!page.hs.supported
        ListItem {
            text: page.showPassword ? qsTr("Hide Password") : qsTr("Show Password")
            iconName: page.showPassword ? "eye-off" : "eye"
            separator: false
            onClicked: page.showPassword = !page.showPassword
        }
    }
}
