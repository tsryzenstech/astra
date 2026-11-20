// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Phone Linker: link this phone with one computer running astraOS Desktop (or this computer with
// one phone) of the same AstraID. Contacts, the phone's photos and its notifications follow, as they happen.
Page {
    id: page
    title: qsTr("Phone Linker")
    readonly property var link: PhoneLink.state || ({})
    readonly property bool isPhone: link.kind !== "desktop"
    readonly property string other: isPhone ? qsTr("computer") : qsTr("phone")
    property bool working: false
    property string error: ""

    Component.onCompleted: PhoneLink.call("refresh", {}, null)
    onVisibleChanged: if (visible) PhoneLink.call("refresh", {}, null)

    EmptyState {
        visible: !page.link.signedIn
        iconName: "person"
        title: qsTr("Sign in with AstraID")
        message: qsTr("Phone Linker links a phone and a computer of the same AstraID. Sign in on both, in Settings > AstraID.")
    }

    // Linked: who with, and what is shared.
    ListGroup {
        visible: !!page.link.signedIn && !!page.link.linked
        footer: qsTr("A phone is linked with one computer at a time, and a computer with one phone.")
        ListItem {
            text: page.link.peer ? page.link.peer.name : ""
            value: qsTr("Linked")
            iconName: page.isPhone ? "desktop" : "phone"
            iconTile: 30
            tileColor: "#34D058"
            separator: false
        }
    }
    ListGroup {
        visible: !!page.link.signedIn && !!page.link.linked
        title: qsTr("Share")
        ListItem {
            text: qsTr("Phone Linker")
            showSwitch: true
            checked: !!page.link.enabled
            onToggled: (on) => Settings.setValue("phonelinker.enabled", on)
        }
        ListItem {
            text: qsTr("Notifications")
            showSwitch: true
            checked: !!(page.link.features || {}).notifications
            onToggled: (on) => Settings.setValue("phonelinker.notifications", on)
        }
        ListItem {
            text: qsTr("Contacts")
            showSwitch: true
            checked: !!(page.link.features || {}).contacts
            onToggled: (on) => Settings.setValue("phonelinker.contacts", on)
        }
        ListItem {
            text: qsTr("Photos")
            showSwitch: true
            separator: false
            checked: !!(page.link.features || {}).photos
            onToggled: (on) => Settings.setValue("phonelinker.photos", on)
        }
    }
    ListGroup {
        visible: !!page.link.signedIn && !!page.link.linked
        footer: page.isPhone ? qsTr("Notifications and new photos go to the computer. Contacts go both ways: each adds what the other lacks.")
                             : qsTr("The phone's notifications appear in the Notification Center and its new photos in Pictures. Contacts go both ways.")
        ListItem {
            text: qsTr("Sync Contacts Now")
            iconName: "refresh"
            onClicked: PhoneLink.call("syncNow", {}, null)
        }
        ListItem {
            text: qsTr("Unlink")
            iconName: "close"
            separator: false
            onClicked: { page.working = true; PhoneLink.call("unlink", {}, function(r, e) { page.working = false; page.error = e || "" }) }
        }
    }

    // Not linked: the devices it could link with.
    ListGroup {
        visible: !!page.link.signedIn && !page.link.linked
        title: page.isPhone ? qsTr("Link with a computer") : qsTr("Link with a phone")
        footer: (page.link.candidates || []).length === 0
                ? qsTr("Nothing is waiting. Sign in to the same AstraID on your other device (a phone with astraOS, a computer with astraOS Desktop) and it appears here.")
                : qsTr("Photos, contacts and notifications pass through the AstraID server, encrypted there. They are not end-to-end encrypted.")
        Repeater {
            model: page.link.candidates || []
            delegate: ListItem {
                required property var modelData
                text: modelData.name
                iconName: page.isPhone ? "desktop" : "phone"
                chevron: true
                busy: page.working
                onClicked: {
                    page.working = true
                    page.error = ""
                    PhoneLink.call("link", { peer: modelData.id }, function(r, e) { page.working = false; page.error = e || "" })
                }
            }
        }
    }
    Text { visible: page.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: page.error; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
}
