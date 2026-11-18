// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > AstraID: who owns the phone and the AstraID status. Sign-in,
// Find My Device and the contacts backup live in AstraID Services.
Page {
    id: page
    title: qsTr("AstraID")
    readonly property var acc: Account.state

    EmptyState {
        iconName: "person"
        title: page.acc.signedIn ? (page.acc.name || page.acc.email) : qsTr("Not Logged In")
        message: page.acc.signedIn ? page.acc.email
                                   : qsTr("Sign in with AstraID to find this phone if you lose it and to back up your contacts.")
    }
    ListGroup {
        ListItem {
            text: page.acc.signedIn ? qsTr("AstraID Services") : qsTr("Sign In")
            subtitle: qsTr("Find My Device and contacts backup")
            iconName: "cloud"
            chevron: true
            onClicked: Packages.launch("com.astra.astraid")
        }
        ListItem {
            visible: !!page.acc.signedIn
            text: qsTr("Find My Device")
            value: page.acc.findMy ? qsTr("On") : qsTr("Off")
            enabled: false
        }
        ListItem {
            visible: !!page.acc.signedIn
            text: qsTr("Contacts Backup")
            value: page.acc.contactsBackup ? qsTr("On") : qsTr("Off")
            enabled: false
            separator: false
        }
    }
}
