// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Phone: keypad, recent calls, favourites and contacts, and the call
// screen. Calls go through the modem (ModemManager) via astrad.
Rectangle {
    id: app
    color: Theme.background

    property string tab: "keypad"
    property string number: ""
    property var log: []
    readonly property var calls: Telephony.state.calls || []
    readonly property var call: calls.length ? calls[0] : null
    readonly property var contacts: (Contacts.state.contacts || []).slice().sort((a, b) => a.name.localeCompare(b.name))

    function reloadLog() { Telephony.call("callLog", {}, function(r) { app.log = r || [] }) }
    Component.onCompleted: {
        Permissions.request("astra.permission.PHONE")
        Permissions.request("astra.permission.CONTACTS")
        reloadLog()
        if (Application.args.dial) {
            number = Application.args.dial
            tab = "keypad"
        }
    }
    Connections {
        target: Application
        function onIntent(args) {
            if (args.dial) {
                app.number = args.dial
                app.tab = "keypad"
            }
        }
    }
    Connections {
        target: Telephony
        function onRevisionChanged() { app.reloadLog() }
    }

    function nameOf(n) {
        const d = String(n).replace(/[^0-9+]/g, "")
        for (const c of app.contacts)
            if (c.phone && c.phone.replace(/[^0-9+]/g, "") === d)
                return c.name
        return ""
    }
    function dial(n) {
        if (!n)
            return
        Telephony.call("dial", { number: n }, function(r, err) { if (err) errorText.text = err })
    }
    function two(n) { return (n < 10 ? "0" : "") + n }

    Loader {
        anchors.fill: parent
        anchors.bottomMargin: 96
        sourceComponent: app.tab === "keypad" ? keypadPage : app.tab === "recents" ? recentsPage
                         : app.tab === "contacts" ? contactsPage : favoritesPage
    }

    Text {
        id: errorText
        visible: text !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 104
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        Timer { running: errorText.text !== ""; interval: 3500; onTriggered: errorText.text = "" }
    }

    // ---- tab bar ---------------------------------------------------------------
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: parent.width - 40
        height: 60
        radius: 30
        color: Theme.surfaceRaised
        Row {
            anchors.fill: parent
            anchors.margins: 5
            Repeater {
                model: [ { id: "favorites", icon: "star", label: qsTr("Favorites") }, { id: "recents", icon: "clock", label: qsTr("Recents") },
                         { id: "contacts", icon: "contact", label: qsTr("Contacts") }, { id: "keypad", icon: "keypad", label: qsTr("Keypad") } ]
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width / 4
                    height: 50
                    radius: 25
                    color: app.tab === modelData.id ? Theme.surfacePressed : "transparent"
                    Column {
                        anchors.centerIn: parent
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 20; color: app.tab === modelData.id ? Theme.accent : Theme.text }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.family: Theme.fontFamily
                               font.pixelSize: 10; font.weight: Font.Medium; color: app.tab === modelData.id ? Theme.accent : Theme.textSecondary }
                    }
                    MouseArea { anchors.fill: parent; onClicked: app.tab = modelData.id }
                }
            }
        }
    }

    // ---- Keypad ---------------------------------------------------------------------
    Component {
        id: keypadPage
        Item {
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 60
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                text: app.number
                elide: Text.ElideLeft
                font.family: Theme.fontFamily
                font.pixelSize: app.number.length > 12 ? 30 : 40
                color: Theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 112
                text: app.nameOf(app.number)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.accent
            }
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 160
                columns: 3
                columnSpacing: 26
                rowSpacing: 16
                Repeater {
                    model: [["1", ""], ["2", "ABC"], ["3", "DEF"], ["4", "GHI"], ["5", "JKL"], ["6", "MNO"],
                            ["7", "PQRS"], ["8", "TUV"], ["9", "WXYZ"], ["*", ""], ["0", "+"], ["#", ""]]
                    delegate: Rectangle {
                        required property var modelData
                        width: 78; height: 78; radius: 39
                        color: key.pressed ? Theme.surfacePressed : Theme.surfaceRaised
                        scale: key.pressed ? 0.92 : 1
                        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; font.family: Theme.fontFamily; font.pixelSize: 32; color: Theme.text }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData[1] !== ""; text: modelData[1]
                                   font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 2; color: Theme.textSecondary }
                        }
                        MouseArea {
                            id: key
                            anchors.fill: parent
                            onClicked: app.number += modelData[0]
                            onPressAndHold: if (modelData[0] === "0") app.number += "+"
                        }
                    }
                }
            }
            // The call button stays in the middle; backspace sits to its right.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: 78
                height: 78
                Rectangle {
                    anchors.fill: parent
                    radius: 39
                    color: "#34C759"
                    Icon { anchors.centerIn: parent; name: "phone"; size: 34 }
                    MouseArea { anchors.fill: parent; onClicked: app.dial(app.number) }
                }
                IconButton {
                    anchors.left: parent.right
                    anchors.leftMargin: 36
                    anchors.verticalCenter: parent.verticalCenter
                    size: 50
                    iconName: "backspace"
                    color: "transparent"
                    visible: app.number.length > 0
                    onClicked: app.number = app.number.slice(0, -1)
                    onPressAndHold: app.number = ""
                }
            }
        }
    }

    // ---- Recents ----------------------------------------------------------------------
    Component {
        id: recentsPage
        Page {
            title: qsTr("Recents")
            actions: Button {
                visible: app.log.length > 0
                implicitWidth: 80; implicitHeight: 34
                primary: false
                text: qsTr("Clear")
                onClicked: Telephony.call("clearCallLog", {}, function() { app.reloadLog() })
            }
            EmptyState { visible: app.log.length === 0; iconName: "clock"; title: qsTr("No recent calls") }
            ListGroup {
                visible: app.log.length > 0
                Repeater {
                    model: app.log
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        readonly property bool missed: !!modelData.missed
                        text: app.nameOf(modelData.number) || modelData.number
                        textColor: missed ? Theme.danger : Theme.text
                        subtitle: (modelData.direction === "out" ? qsTr("Outgoing") : missed ? qsTr("Missed") : qsTr("Incoming"))
                        value: modelData.start ? Qt.locale().toString(new Date(modelData.start), "d MMM HH:mm") : ""
                        separator: index < app.log.length - 1
                        onClicked: app.dial(modelData.number)
                    }
                }
            }
        }
    }

    // ---- Contacts -------------------------------------------------------------------------
    Component {
        id: contactsPage
        Page {
            id: cp
            title: qsTr("Contacts")
            property bool adding: false
            actions: IconButton { iconName: "person-add"; color: Theme.surfaceRaised; onClicked: cp.adding = true }

            Card {
                visible: cp.adding
                Column {
                    width: parent.width
                    spacing: 10
                    TextField { id: nameField; width: parent.width; placeholder: qsTr("Name") }
                    TextField { id: phoneField; width: parent.width; placeholder: qsTr("Phone"); inputMethodHints: Qt.ImhDialableCharactersOnly }
                    TextField { id: mailField; width: parent.width; placeholder: qsTr("Email"); inputMethodHints: Qt.ImhEmailCharactersOnly }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Button { primary: false; text: qsTr("Cancel"); onClicked: cp.adding = false }
                        Button {
                            text: qsTr("Save")
                            enabled: nameField.text.trim() !== ""
                            onClicked: {
                                Contacts.call("add", { name: nameField.text, phone: phoneField.text, email: mailField.text }, null)
                                nameField.text = phoneField.text = mailField.text = ""
                                cp.adding = false
                            }
                        }
                    }
                }
            }
            EmptyState { visible: app.contacts.length === 0 && !cp.adding; iconName: "contact"; title: qsTr("No contacts"); message: qsTr("Tap + to add someone.") }
            ListGroup {
                visible: app.contacts.length > 0
                Repeater {
                    model: app.contacts
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        subtitle: modelData.phone || modelData.email || ""
                        separator: index < app.contacts.length - 1
                        onClicked: if (modelData.phone) app.dial(modelData.phone)
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 30
                            iconName: "star"
                            color: modelData.favorite ? Theme.accent : Theme.surfaceRaised
                            onClicked: Contacts.call("update", { id: modelData.id, favorite: !modelData.favorite }, null)
                        }
                    }
                }
            }
        }
    }

    // ---- Favorites ---------------------------------------------------------------------------
    Component {
        id: favoritesPage
        Page {
            title: qsTr("Favorites")
            readonly property var favs: app.contacts.filter(c => c.favorite)
            EmptyState { visible: parent.favs.length === 0; iconName: "star"; title: qsTr("No favorites"); message: qsTr("Star people in Contacts to call them with one tap.") }
            Grid {
                columns: 3
                spacing: 16
                Repeater {
                    model: parent.parent.favs
                    delegate: Column {
                        required property var modelData
                        spacing: 6
                        width: 100
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76; height: 76; radius: 38
                            gradient: Gradient { GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accentDeep } }
                            Text { anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); font.family: Theme.fontFamily
                                   font.pixelSize: 32; font.weight: Font.DemiBold; color: "white" }
                            MouseArea { anchors.fill: parent; onClicked: app.dial(modelData.phone) }
                        }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.name
                               font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1; color: Theme.text }
                    }
                }
            }
        }
    }

    // ---- In call -------------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: app.call !== null && app.call.state !== "ringing"
        gradient: Gradient {
            GradientStop { position: 0; color: "#0E3B2A" }
            GradientStop { position: 1; color: "#000000" }
        }
        MouseArea { anchors.fill: parent }
        property double since: 0
        property double now: 0
        Timer { running: parent.visible; interval: 1000; repeat: true; triggeredOnStart: true; onTriggered: parent.now = Date.now() }
        onVisibleChanged: since = Date.now()
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 140
            spacing: 8
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.call ? (app.nameOf(app.call.number) || app.call.number) : ""
                   font.family: Theme.fontFamily; font.pixelSize: 34; font.weight: Font.DemiBold; color: "white" }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !app.call ? "" : app.call.state === "dialing" ? qsTr("Calling…")
                      : (function(s) { return app.two(Math.floor(s / 60)) + ":" + app.two(s % 60) })(Math.floor((parent.parent.now - parent.parent.since) / 1000))
                font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; color: Theme.textSecondary
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 90
            width: 78; height: 78; radius: 39
            color: "#FF3B30"
            Icon { anchors.centerIn: parent; name: "phone-hangup"; size: 36 }
            MouseArea { anchors.fill: parent; onClicked: if (app.call) Telephony.call("hangup", { id: app.call.id }, null) }
        }
    }
}
