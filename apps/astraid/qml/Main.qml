// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// AstraID Services: sign in to AstraID, Find My Device and the contacts
// backup (contacts only: no photos, videos, audio or files).
Rectangle {
    id: app
    color: Theme.background

    readonly property var acc: Account.state
    property bool working: false
    property string message: ""
    property bool registering: false

    function ago(t) {
        if (!t) return qsTr("Never")
        const s = (Date.now() - t) / 1000
        if (s < 60) return qsTr("Just now")
        if (s < 3600) return qsTr("%n minutes ago", "", Math.round(s / 60))
        if (s < 86400) return qsTr("%n hours ago", "", Math.round(s / 3600))
        return Qt.locale().toString(new Date(t), Locale.ShortFormat)
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(mainPage)
    }

    Component {
        id: mainPage
        Page {
            title: qsTr("AstraID")

            // ---- signed out: sign in or create an account
            Column {
                visible: !app.acc.signedIn
                width: parent.width
                spacing: 14
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96; height: 96; radius: 48
                    gradient: Gradient { GradientStop { position: 0; color: "#7B2FF7" } GradientStop { position: 1; color: "#00C9A7" } }
                    Icon { anchors.centerIn: parent; name: "person"; size: 46 }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: app.registering ? qsTr("Create your AstraID") : qsTr("Sign in with your AstraID")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Bold
                    color: Theme.text
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("Find your phone if you lose it and keep your contacts backed up, encrypted. Nothing else leaves your phone: no photos, videos, audio or files.")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize
                    color: Theme.textSecondary
                }
                TextField { id: name; visible: app.registering; width: parent.width; placeholder: qsTr("Name"); text: Settings.values["account.name"] || "" }
                TextField { id: email; width: parent.width; placeholder: qsTr("Email"); inputMethodHints: Qt.ImhEmailCharactersOnly }
                TextField { id: password; width: parent.width; placeholder: app.registering ? qsTr("Password (8 characters or more)") : qsTr("Password"); echoMode: TextInput.Password; onAccepted: go.clicked() }
                Text { visible: app.message !== ""; width: parent.width; wrapMode: Text.WordWrap; text: app.message; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
                Button {
                    id: go
                    width: parent.width
                    text: app.working ? qsTr("Signing In…") : app.registering ? qsTr("Create AstraID") : qsTr("Sign In")
                    enabled: !app.working && email.text.indexOf("@") > 0 && password.text.length >= (app.registering ? 8 : 1)
                    onClicked: {
                        app.working = true
                        app.message = ""
                        Account.call("signIn", { email: email.text, password: password.text, register: app.registering, name: name.text,
                                                 server: server.text.trim() }, function(r, error) {
                            app.working = false
                            if (error) app.message = error
                            else password.text = ""
                        })
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.registering ? qsTr("I already have an AstraID") : qsTr("Create an AstraID")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.accent
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: app.registering = !app.registering }
                }
                ListGroup {
                    width: parent.width
                    title: qsTr("Server")
                    footer: qsTr("The astra cloud server of AstraID. Leave it as it is unless you host your own.")
                    Item {
                        width: parent.width
                        height: 68
                        TextField { id: server; anchors.fill: parent; anchors.margins: 10; text: app.acc.server || ""; inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase }
                    }
                }
            }

            // ---- signed in
            Column {
                visible: !!app.acc.signedIn
                width: parent.width
                spacing: 18
                Card {
                    width: parent.width
                    Row {
                        spacing: 14
                        Rectangle {
                            width: 60; height: 60; radius: 30
                            gradient: Gradient { GradientStop { position: 0; color: "#7B2FF7" } GradientStop { position: 1; color: "#00C9A7" } }
                            Text { anchors.centerIn: parent; text: (app.acc.name || "?").charAt(0).toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 26; font.weight: Font.Bold; color: "white" }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: app.acc.name || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                            Text { text: app.acc.email || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                        }
                    }
                }
                ListGroup {
                    width: parent.width
                    title: qsTr("Find My Device")
                    footer: qsTr("See where this phone is, make it ring, lock it or send it a message from %1/id. Uses Location Services.").arg(app.acc.server || "")
                    ListItem {
                        text: qsTr("Find My Device")
                        iconName: "location"
                        iconTile: 30
                        tileColor: "#34D058"
                        showSwitch: true
                        checked: !!app.acc.findMy
                        onToggled: (on) => Account.call("setFindMy", { on: on }, null)
                    }
                    ListItem {
                        text: qsTr("Last report")
                        value: app.ago(app.acc.lastReport)
                        enabled: false
                    }
                    ListItem {
                        text: qsTr("Find Your Other Devices")
                        chevron: true
                        separator: false
                        onClicked: Packages.launch("com.astra.planet", { url: (app.acc.server || "") + "/id/" })
                    }
                }
                ListGroup {
                    width: parent.width
                    title: qsTr("Contacts Backup")
                    footer: qsTr("Only your contacts are backed up, encrypted on the server with a key of your account.")
                    ListItem {
                        text: qsTr("Back Up Contacts")
                        iconName: "contact"
                        iconTile: 30
                        tileColor: "#0A84FF"
                        showSwitch: true
                        checked: !!app.acc.contactsBackup
                        onToggled: (on) => Account.call("setContactsBackup", { on: on }, null)
                    }
                    ListItem {
                        text: qsTr("Last backup")
                        value: app.ago(app.acc.lastBackup)
                        enabled: false
                    }
                    ListItem {
                        text: app.working ? qsTr("Backing Up…") : qsTr("Back Up Now")
                        textColor: Theme.accent
                        busy: app.working
                        onClicked: {
                            app.working = true
                            Account.call("backupNow", {}, function(r, error) { app.working = false; app.message = error || qsTr("Contacts backed up") })
                        }
                    }
                    ListItem {
                        text: qsTr("Restore Contacts")
                        textColor: Theme.accent
                        separator: false
                        onClicked: Account.call("restoreContacts", {}, function(r, error) {
                            app.message = error || qsTr("%n contacts restored", "", r ? r.added : 0)
                        })
                    }
                }
                Text { visible: app.message !== ""; width: parent.width; wrapMode: Text.WordWrap; text: app.message; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
                ListGroup {
                    width: parent.width
                    ListItem {
                        text: qsTr("Manage AstraID on the Web")
                        chevron: true
                        onClicked: Packages.launch("com.astra.planet", { url: (app.acc.server || "") + "/id/" })
                    }
                    ListItem {
                        text: qsTr("Sign Out")
                        destructive: true
                        separator: false
                        onClicked: Dialogs.show({ title: qsTr("Sign out of AstraID?"),
                                                  message: qsTr("Find My Device and the contacts backup stop on this phone. Your contacts stay on the phone."),
                                                  buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "out", label: qsTr("Sign Out"), style: "destructive" }] },
                                                function(a) { if (a === "out") Account.call("signOut", {}, null) })
                    }
                }
            }
        }
    }
}
