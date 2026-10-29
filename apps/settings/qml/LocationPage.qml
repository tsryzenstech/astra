// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Privacy > Location Services: the switch for everything that
// finds where the phone is, and which apps may ask for it.
Page {
    id: page
    title: qsTr("Location Services")
    property var permission: null
    Component.onCompleted: Permissions.catalog(function(list) {
        page.permission = (list || []).find(p => p.name === "astra.permission.LOCATION") || null
    })

    ListGroup {
        footer: qsTr("Location Services uses the GNSS receiver and, to find the phone faster or indoors, nearby Wi-Fi networks and cell towers, looked up anonymously in BeaconDB, an open database.")
        SwitchRow {
            text: qsTr("Location Services")
            iconName: "location"
            key: "controls.location"
            fallback: true
            separator: false
        }
    }
    ListGroup {
        visible: page.permission !== null
        ListItem {
            text: qsTr("Apps")
            subtitle: qsTr("Choose which apps can use your location.")
            chevron: true
            separator: false
            onClicked: page.stack.open(Qt.resolvedUrl("PermissionAppsPage.qml"), { permission: page.permission })
        }
    }
    ListGroup {
        title: qsTr("System Services")
        ListItem {
            text: qsTr("Find My Device")
            value: Account.state.signedIn && Account.state.findMy ? qsTr("On") : qsTr("Off")
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.astraid")
        }
    }
}
