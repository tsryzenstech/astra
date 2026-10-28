// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// AstraID. Online sign-in is provided by the AstraID Services app; until
// then the phone keeps a local owner name.
Page {
    id: page
    title: qsTr("AstraID")

    readonly property bool signedIn: (Settings.values["account.name"] || "") !== ""

    EmptyState {
        iconName: "person"
        title: page.signedIn ? Settings.values["account.name"] : qsTr("Not Logged In")
        message: page.signedIn ? qsTr("This name is shown on your phone and to nearby devices.")
                               : qsTr("Sign in with AstraID to sync your settings, purchases and backups across devices.")
    }

    ListGroup {
        title: qsTr("Owner")
        footer: qsTr("Leave it empty to sign out of this phone.")
        Item {
            width: parent.width
            height: 72
            TextField {
                id: nameField
                anchors.fill: parent
                anchors.margins: 12
                placeholder: qsTr("Your name")
                text: Settings.values["account.name"] || ""
                maximumLength: 40
                onAccepted: Settings.setValue("account.name", text.trim())
            }
        }
        ListItem {
            text: qsTr("Save")
            textColor: Theme.accent
            separator: false
            onClicked: Settings.setValue("account.name", nameField.text.trim())
        }
    }

    ListGroup {
        ListItem {
            text: qsTr("AstraID Services")
            subtitle: qsTr("Sign in, backups and Find My Device")
            iconName: "cloud"
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.astraid")
        }
    }
}
