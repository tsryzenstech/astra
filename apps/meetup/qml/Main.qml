// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// MeetUp: video calls on Google Meet. A new meeting or a code or link to join opens Meet in a web
// view, where you sign in to Google as in any browser; MeetUp adds the list of recent meetings, a
// call to a contact (a new meeting whose link is sent to them from Messages) and the bar above
// the call to leave it and to invite more people.
Rectangle {
    id: app
    color: "black"

    readonly property color green: "#30D158"
    readonly property var calls: Settings.values["app.com.astra.meetup.calls"] || []
    readonly property var contacts: (Contacts.state.contacts || []).slice().sort((a, b) => a.name.localeCompare(b.name))

    property string phase: "home"          // home, call
    property string room: "new"
    property string callName: ""
    property string callNumber: ""
    property string code: ""
    property bool inviteWhenReady: false
    readonly property string link: code ? "https://meet.google.com/" + code : ""

    // "abc-defg-hij", or a Meet link, in whatever the user typed or pasted.
    function codeOf(text) {
        const m = String(text).toLowerCase().match(/([a-z]{3}-[a-z]{4}-[a-z]{3})/)
        return m ? m[1] : ""
    }
    function remember(entry) {
        Settings.setValue("app.com.astra.meetup.calls",
                          [Object.assign({ time: Date.now() }, entry)].concat(calls.filter(c => c.code !== entry.code)).slice(0, 40))
    }
    function start(room, name, number, invite) {
        app.room = room
        app.code = room === "new" ? "" : room
        app.callName = name || ""
        app.callNumber = number || ""
        app.inviteWhenReady = !!invite
        app.phase = "call"
        newSheet.close()
        joinSheet.close()
        Permissions.request("astra.permission.CAMERA", function() { })
        Permissions.request("astra.permission.MICROPHONE", function() { })
    }
    function invite() {
        if (!link)
            return
        const text = qsTr("Join my meeting: %1").arg(link)
        Packages.launch("com.astra.messages", callNumber ? { number: callNumber, text: text } : { text: text })
    }
    function hangUp() {
        if (callLoader.item)
            callLoader.item.leave()
        app.phase = "home"
    }
    function initials(name) {
        const parts = (name || "?").trim().split(/\s+/)
        return (parts[0].charAt(0) + (parts.length > 1 ? parts[parts.length - 1].charAt(0) : "")).toUpperCase()
    }
    function when(t) {
        const d = new Date(t), today = new Date()
        if (d.toDateString() === today.toDateString())
            return Qt.locale().toString(d, Settings.values["clock.24h"] === false ? "h:mm AP" : "HH:mm")
        const yesterday = new Date(today.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString())
            return qsTr("Yesterday")
        return Qt.formatDate(d, "d/M/yy")
    }

    // ---- home --------------------------------------------------------------------------
    Page {
        id: home
        anchors.fill: parent
        visible: app.phase === "home"
        title: qsTr("MeetUp")
        background: Component { Rectangle { color: "black" } }

        Row {
            width: parent.width
            spacing: 12
            Repeater {
                model: [
                    { icon: "link", text: qsTr("Join with a Code"), green: false },
                    { icon: "video", text: qsTr("New Meeting"), green: true }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: (home.width - 32 - 12) / 2
                    height: 52
                    radius: 14
                    color: modelData.green ? app.green : Qt.rgba(1, 1, 1, 0.14)
                    scale: tap.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 20; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; color: "white"
                               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        onClicked: modelData.green ? newSheet.open() : joinSheet.open()
                    }
                }
            }
        }

        Column {
            width: parent.width
            visible: app.calls.length === 0
            topPadding: 80
            spacing: 10
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "video"; size: 56; color: Theme.textTertiary }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("No recent meetings"); color: "white"
                   font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: Theme.textSecondary
                   text: qsTr("Start a meeting, call a contact or join one with its code. Meetings are Google Meet: anyone can join from a phone or a computer.")
                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1 }
        }

        Column {
            width: parent.width
            visible: app.calls.length > 0
            spacing: 6
            Text { text: qsTr("Recent"); color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold }
            Repeater {
                model: app.calls
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 68
                    Rectangle {
                        id: avatar
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 46; radius: 23
                        color: Theme.surfaceRaised
                        Text { anchors.centerIn: parent; text: app.initials(modelData.name || modelData.code); color: "white"
                               font.family: Theme.fontFamily; font.pixelSize: 18; font.weight: Font.DemiBold }
                    }
                    Column {
                        anchors.left: avatar.right
                        anchors.leftMargin: 14
                        anchors.right: when.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name || modelData.code; color: "white"
                               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold }
                        Row {
                            spacing: 5
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "video"; size: 13; color: Theme.textSecondary }
                            Text { text: modelData.code; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
                        }
                    }
                    Text { id: when; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                           text: app.when(modelData.time); color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
                    MouseArea { anchors.fill: parent; onClicked: app.start(modelData.code, modelData.name, modelData.number, false) }
                    Rectangle { anchors.left: avatar.right; anchors.leftMargin: 14; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.separator; visible: index < app.calls.length - 1 }
                }
            }
            Button {
                width: parent.width
                primary: false
                text: qsTr("Clear Recent Meetings")
                onClicked: Settings.setValue("app.com.astra.meetup.calls", [])
            }
        }
    }

    // ---- the call: Meet, with a bar above it ---------------------------------------------
    Item {
        anchors.fill: parent
        visible: app.phase === "call"

        Loader {
            id: callLoader
            anchors.fill: parent
            anchors.topMargin: Theme.statusBarHeight + 52
            active: app.phase === "call"
            source: Qt.resolvedUrl("CallView.qml")
            onLoaded: {
                item.room = app.room
                item.codeKnown.connect(function(code) {
                    app.code = code
                    app.remember({ name: app.callName, number: app.callNumber, code: code })
                    if (app.inviteWhenReady) {
                        app.inviteWhenReady = false
                        app.invite()
                    }
                })
            }
            // Why it failed: the system module missing, or an error in the call view.
            readonly property string error: status === Loader.Error ? Qt.createComponent(source).errorString().trim() : ""
            onErrorChanged: if (error) console.warn("MeetUp:", error)
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: callLoader.status === Loader.Error
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: /module "QtWebEngine" is not installed/.test(callLoader.error)
                  ? qsTr("This version of astraOS is missing %1, which meetings need.").arg("Qt WebEngine")
                  : callLoader.error
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
        }

        // The bar above Meet.
        Item {
            x: 10
            y: Theme.statusBarHeight
            width: parent.width - 20
            height: 52
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: leaveRow.implicitWidth + 28
                height: 40
                radius: 20
                color: Theme.danger
                Row {
                    id: leaveRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "phone-hangup"; size: 18; color: "white" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Leave"); color: "white"
                           font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; onClicked: app.hangUp() }
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - 220
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: app.callName || app.code
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: app.link !== ""
                width: inviteRow.implicitWidth + 28
                height: 40
                radius: 20
                color: Qt.rgba(1, 1, 1, 0.16)
                Row {
                    id: inviteRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "person-add"; size: 18; color: "white" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Invite"); color: "white"
                           font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; onClicked: { app.callNumber = ""; app.invite() } }
            }
        }
    }

    // ---- a new meeting: now, or with a contact --------------------------------------------
    Sheet {
        id: newSheet
        title: qsTr("New Meeting")
        Column {
            width: parent.width
            spacing: 10
            Button { width: parent.width; text: qsTr("Start a Meeting"); iconName: "video"; onClicked: app.start("new", "", "", false) }
            Text { visible: app.contacts.length > 0; text: qsTr("Or call a contact"); color: Theme.textSecondary
                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1 }
            Flickable {
                visible: app.contacts.length > 0
                width: parent.width
                height: Math.min(contentHeight, 360)
                contentHeight: contactColumn.height
                clip: true
                Column {
                    id: contactColumn
                    width: parent.width
                    Repeater {
                        model: app.contacts.filter(c => c.phone).slice(0, 80)
                        delegate: ListItem {
                            required property var modelData
                            text: modelData.name
                            subtitle: modelData.phone
                            onClicked: app.start("new", modelData.name, modelData.phone, true)
                        }
                    }
                }
            }
        }
    }

    // ---- join with a code or a link -----------------------------------------------------------
    Sheet {
        id: joinSheet
        title: qsTr("Join a Meeting")
        Column {
            width: parent.width
            spacing: 12
            TextField { id: codeField; width: parent.width; placeholder: "abc-defg-hij"; onAccepted: joinButton.clicked() }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.textSecondary
                   text: qsTr("Type the code, or paste the link someone sent you.")
                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1 }
            Button {
                id: joinButton
                width: parent.width
                text: qsTr("Join")
                enabled: app.codeOf(codeField.text) !== ""
                onClicked: app.start(app.codeOf(codeField.text), "", "", false)
            }
        }
    }

    // A meeting link opened from Messages or Planet.
    function route(args) {
        if (!args)
            return
        const code = codeOf(args.url || args.text || "")
        if (code)
            start(code, "", "", false)
    }
    Component.onCompleted: route(Application.args)
    Connections {
        target: Application
        function onIntent(args) { app.route(args) }
    }
}
