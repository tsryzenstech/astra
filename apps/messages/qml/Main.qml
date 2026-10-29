// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Messages: SMS conversations through the modem, with bubbles.
Rectangle {
    id: app
    color: Theme.background

    property var conversations: []
    property string open: ""            // number of the open conversation, "" for the list
    property bool composing: false
    property var thread: []
    readonly property var contacts: Contacts.state.contacts || []

    function nameOf(n) {
        const d = String(n).replace(/[^0-9+]/g, "")
        for (const c of contacts)
            if (c.phone && c.phone.replace(/[^0-9+]/g, "") === d)
                return c.name
        return n
    }
    function reload() {
        Telephony.call("conversations", {}, function(r) { app.conversations = r || [] })
        if (open)
            Telephony.call("messages", { number: open }, function(r) {
                app.thread = r || []
                Qt.callLater(() => threadView.positionViewAtEnd())
            })
    }
    function openThread(n) {
        open = n
        composing = false
        Telephony.call("markRead", { number: n }, null)
        reload()
    }
    function send(text) {
        if (!text.trim() || !open)
            return
        Telephony.call("sendSms", { number: open, text: text }, function(r, err) {
            if (err)
                errorText.text = err
            app.reload()
        })
    }

    Component.onCompleted: {
        Permissions.request("astra.permission.SMS")
        Permissions.request("astra.permission.CONTACTS")
        reload()
        if (Application.args.number)
            openThread(Application.args.number)
        if (Application.args.text)
            input.text = Application.args.text
    }
    Connections {
        target: Telephony
        function onRevisionChanged() { app.reload() }
    }
    Connections {
        target: Application
        function onIntent(args) {
            if (args.number) app.openThread(args.number)
            if (args.text) input.text = args.text
        }
    }

    // ---- conversations ------------------------------------------------------------
    Page {
        anchors.fill: parent
        visible: app.open === "" && !app.composing
        title: qsTr("Messages")
        actions: IconButton { iconName: "edit"; color: Theme.surfaceRaised; onClicked: app.composing = true }

        EmptyState {
            visible: app.conversations.length === 0
            iconName: "message"
            title: qsTr("No messages")
            message: qsTr("Start a conversation with the pencil button.")
        }
        ListGroup {
            visible: app.conversations.length > 0
            Repeater {
                model: app.conversations
                delegate: ListItem {
                    required property var modelData
                    required property int index
                    text: app.nameOf(modelData.number)
                    subtitle: (modelData.incoming ? "" : qsTr("You: ")) + modelData.text
                    value: Qt.locale().toString(new Date(modelData.time), new Date(modelData.time).toDateString() === new Date().toDateString() ? "HH:mm" : "d MMM")
                    chevron: true
                    separator: index < app.conversations.length - 1
                    onClicked: app.openThread(modelData.number)
                    Rectangle {
                        visible: modelData.unread > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: Theme.accent
                        Text { anchors.centerIn: parent; text: modelData.unread; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: "white" }
                    }
                }
            }
        }
    }

    // ---- new message -------------------------------------------------------------------
    Page {
        anchors.fill: parent
        visible: app.composing
        title: qsTr("New message")
        actions: Button { implicitWidth: 90; implicitHeight: 34; primary: false; text: qsTr("Cancel"); onClicked: app.composing = false }
        TextField {
            id: toField
            width: parent.width
            placeholder: qsTr("To: name or number")
            inputMethodHints: Qt.ImhNoPredictiveText
            onAccepted: if (text.trim()) app.openThread(text.trim())
        }
        ListGroup {
            readonly property var matches: toField.text.length < 1 ? [] : app.contacts.filter(c => c.phone && (c.name.toLowerCase().indexOf(toField.text.toLowerCase()) >= 0 || c.phone.indexOf(toField.text) >= 0))
            visible: matches.length > 0
            Repeater {
                model: parent.matches
                delegate: ListItem {
                    required property var modelData
                    text: modelData.name
                    subtitle: modelData.phone
                    onClicked: app.openThread(modelData.phone)
                }
            }
        }
        Button {
            width: parent.width
            text: qsTr("Continue")
            enabled: toField.text.trim() !== ""
            onClicked: app.openThread(toField.text.trim())
        }
    }

    // ---- thread ------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: app.open !== ""

        ListView {
            id: threadView
            anchors.fill: parent
            anchors.topMargin: Theme.statusBarHeight + 60
            anchors.bottomMargin: composer.height + 40
            spacing: 6
            clip: true
            model: app.thread
            delegate: Item {
                required property var modelData
                width: threadView.width
                height: bubble.height + 2
                Rectangle {
                    id: bubble
                    readonly property bool mine: !modelData.incoming
                    x: mine ? parent.width - width - 14 : 14
                    width: Math.min(parent.width * 0.74, body.implicitWidth + 28)
                    height: body.implicitHeight + 18
                    radius: 20
                    color: mine ? Theme.accent : Theme.surfaceRaised
                    Text {
                        id: body
                        x: 14
                        y: 9
                        width: Math.min(threadView.width * 0.74 - 28, implicitWidth)
                        text: modelData.text
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        color: bubble.mine ? Theme.accentText : Theme.text
                    }
                }
            }
        }

        // Header
        Rectangle {
            width: parent.width
            height: Theme.statusBarHeight + 56
            color: Theme.background
            opacity: 0.96
            IconButton { x: 12; y: Theme.statusBarHeight + 6; size: 40; iconName: "chevron-left"; color: Theme.surfaceRaised; onClicked: { app.open = ""; app.reload() } }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 14
                text: app.nameOf(app.open)
                font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text
            }
            IconButton {
                anchors.right: parent.right; anchors.rightMargin: 12; y: Theme.statusBarHeight + 6
                size: 40; iconName: "phone"; color: Theme.surfaceRaised
                onClicked: Packages.launch("com.astra.phone", { dial: app.open })
            }
        }

        // Composer
        Row {
            id: composer
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            x: 12
            spacing: 8
            height: 48
            TextField {
                id: input
                width: app.width - 24 - 56
                height: 48
                radius: 24
                placeholder: qsTr("Message")
                onAccepted: sendButton.clicked()
            }
            IconButton {
                id: sendButton
                size: 48
                iconName: "send"
                color: input.text.trim() ? Theme.accent : Theme.surfaceRaised
                onClicked: {
                    app.send(input.text)
                    input.text = ""
                }
            }
        }
        Text {
            id: errorText
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: composer.top
            anchors.bottomMargin: 8
            font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.danger
            Timer { running: errorText.text !== ""; interval: 3500; onTriggered: errorText.text = "" }
        }
    }
}
