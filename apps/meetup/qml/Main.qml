// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// MeetUp: video and audio calls. Calls are rooms on a Jitsi Meet server
// (meet.jit.si unless you choose your own); you invite people with a link,
// sent from Messages. Before joining you see yourself full screen, with the
// controls at the top, and join when ready.
Rectangle {
    id: app
    color: "black"

    readonly property color green: "#30D158"
    readonly property string server: Settings.values["app.com.astra.meetup.server"] || "https://meet.jit.si"
    readonly property var calls: Settings.values["app.com.astra.meetup.calls"] || []
    readonly property var contacts: (Contacts.state.contacts || []).slice().sort((a, b) => a.name.localeCompare(b.name))
    readonly property string myName: Settings.values["account.name"] || qsTr("astraOS user")

    property string phase: "home"          // home, lobby, call
    property string callName: ""
    property string callNumber: ""
    property string callCode: ""
    property bool callVideo: true
    property bool camOn: true
    property bool micOn: true
    property bool frontCamera: true
    property real callStart: 0
    property real now: Date.now()
    readonly property string link: server.replace(/\/+$/, "") + "/MeetUp-" + callCode

    function newCode() {
        const a = "abcdefghijkmnpqrstuvwxyz"
        let s = ""
        for (let i = 0; i < 10; i++)
            s += (i === 3 || i === 7 ? "-" : "") + a.charAt(Math.floor(Math.random() * a.length))
        return s                                           // abc-defg-hij
    }
    // "abc-defg-hij", a MeetUp link or a link to any room on the server.
    function codeOf(text) {
        const t = text.trim()
        const m = t.match(/MeetUp-([a-z-]+)\s*$/i)
        return m ? m[1].toLowerCase() : t.replace(/^.*\//, "").toLowerCase()
    }
    function remember(entry) {
        Settings.setValue("app.com.astra.meetup.calls",
                          [Object.assign({ time: Date.now() }, entry)].concat(calls.filter(c => c.code !== entry.code)).slice(0, 40))
    }
    function prepare(name, number, code, video) {
        callName = name
        callNumber = number || ""
        callCode = code
        callVideo = video
        camOn = video
        micOn = true
        phase = "lobby"
        newSheet.close()
        linkSheet.close()
        remember({ name: name, number: callNumber, code: code, video: video })
        Permissions.request("astra.permission.CAMERA", function(ok) { if (!ok) app.camOn = false })
        Permissions.request("astra.permission.MICROPHONE", function(ok) { if (!ok) app.micOn = false })
    }
    function call(contact, video) {
        const code = newCode()
        prepare(contact.name, contact.phone || "", code, video)
        if (contact.phone)
            invite()
    }
    function invite() {
        const text = qsTr("Join my MeetUp: %1").arg(link)
        Packages.launch("com.astra.messages", callNumber ? { number: callNumber, text: text } : { text: text })
    }
    function join() {
        callStart = Date.now()
        phase = "call"
    }
    function hangUp() {
        if (callLoader.item)
            callLoader.item.leave()
        phase = "home"
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
    function duration(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const m = Math.floor(s / 60)
        return m + ":" + String(s % 60).padStart(2, "0")
    }
    component Control: IconButton {
        property bool on: false
        size: 56
        color: on ? "white" : Qt.rgba(1, 1, 1, 0.16)
        iconColor: on ? "#111" : "white"
    }
    Timer { interval: 1000; repeat: true; running: app.phase === "call"; onTriggered: app.now = Date.now() }

    // ---- the camera, before joining ---------------------------------------------
    MediaDevices { id: devices }
    CaptureSession {
        camera: Camera {
            // In the call the meeting page owns the camera.
            active: app.phase === "lobby" && app.camOn && devices.videoInputs.length > 0
            cameraDevice: {
                for (const d of devices.videoInputs)
                    if (d.position === (app.frontCamera ? CameraDevice.FrontFace : CameraDevice.BackFace))
                        return d
                return devices.defaultVideoInput
            }
        }
        videoOutput: selfView
    }

    // ---- home ----------------------------------------------------------------------
    Page {
        id: home
        anchors.fill: parent
        visible: app.phase === "home"
        title: qsTr("MeetUp")
        background: Component { Rectangle { color: "black" } }
        actions: IconButton { iconName: "settings"; color: Qt.rgba(1, 1, 1, 0.12); onClicked: settingsSheet.open() }

        Row {
            width: parent.width
            spacing: 12
            Repeater {
                model: [
                    { icon: "link", text: qsTr("Create Link"), green: false },
                    { icon: "video", text: qsTr("New MeetUp"), green: true }
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
                        onClicked: {
                            if (modelData.green) {
                                newSheet.open()
                            } else {
                                app.callCode = app.newCode()
                                linkSheet.open()
                            }
                        }
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
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("No recent calls"); color: "white"
                   font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: Theme.textSecondary
                   text: qsTr("Call your contacts or create a link and share it with anyone, on any device.")
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
                        width: 46
                        height: 46
                        radius: 23
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#A3A8B4" }
                            GradientStop { position: 1; color: "#6C717C" }
                        }
                        Text { anchors.centerIn: parent; text: app.initials(modelData.name); color: "white"
                               font.family: Theme.fontFamily; font.pixelSize: 18; font.weight: Font.DemiBold }
                    }
                    Column {
                        anchors.left: avatar.right
                        anchors.leftMargin: 14
                        anchors.right: meta.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: "white"
                               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold }
                        Row {
                            spacing: 5
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.video ? "video" : "phone"; size: 13; color: Theme.textSecondary }
                            Text { text: modelData.video ? qsTr("MeetUp Video") : qsTr("MeetUp Audio"); color: Theme.textSecondary
                                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
                        }
                    }
                    Row {
                        id: meta
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text { anchors.verticalCenter: parent.verticalCenter; text: app.when(modelData.time); color: Theme.textSecondary
                               font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
                        IconButton { anchors.verticalCenter: parent.verticalCenter; size: 30; iconName: "info"; color: "transparent"
                                     iconColor: app.green; onClicked: { app.callCode = modelData.code; app.callName = modelData.name; linkSheet.open() } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 44
                        onClicked: app.prepare(modelData.name, modelData.number, modelData.code, modelData.video)
                    }
                    Rectangle { anchors.left: avatar.right; anchors.leftMargin: 14; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.separator; visible: index < app.calls.length - 1 }
                }
            }
        }
    }

    // ---- lobby and call --------------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: app.phase !== "home"

        VideoOutput {
            id: selfView
            anchors.fill: parent
            visible: app.phase === "lobby" && app.camOn
            fillMode: VideoOutput.PreserveAspectCrop
            transform: Scale { xScale: app.frontCamera ? -1 : 1; origin.x: selfView.width / 2 }
        }
        // Camera off or audio call: the person you're calling.
        Rectangle {
            anchors.fill: parent
            visible: app.phase === "lobby" && (!app.camOn || devices.videoInputs.length === 0)
            gradient: Gradient {
                GradientStop { position: 0; color: "#3A3F4B" }
                GradientStop { position: 1; color: "#15171C" }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 128
                height: 128
                radius: 64
                color: Qt.rgba(1, 1, 1, 0.18)
                Text { anchors.centerIn: parent; text: app.initials(app.callName); color: "white"
                       font.family: Theme.fontFamily; font.pixelSize: 50; font.weight: Font.DemiBold }
            }
        }

        Loader {
            id: callLoader
            anchors.fill: parent
            active: app.phase === "call"
            source: Qt.resolvedUrl("CallView.qml")
            onLoaded: {
                item.server = app.server
                item.room = "MeetUp-" + app.callCode
                item.displayName = app.myName
                item.micOn = app.micOn
                item.camOn = app.camOn
                item.joinedNow.connect(() => app.callStart = Date.now())
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
                  ? qsTr("This version of astraOS is missing %1, which calls need.").arg("Qt WebEngine")
                  : callLoader.error
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
        }

        // The control panel at the top, like the one in a call.
        Rectangle {
            id: panel
            x: 10
            y: Theme.statusBarHeight + 4
            width: parent.width - 20
            height: panelColumn.implicitHeight + 32
            radius: 30
            color: Qt.rgba(0.16, 0.16, 0.17, 0.82)
            Column {
                id: panelColumn
                x: 18
                y: 16
                width: parent.width - 36
                spacing: 16
                Row {
                    width: parent.width
                    spacing: 12
                    Column {
                        width: parent.width - inviteButton.width - 12
                        spacing: 1
                        Text { width: parent.width; elide: Text.ElideRight; text: app.callName || qsTr("MeetUp")
                               color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize + 1; font.weight: Font.DemiBold }
                        Text {
                            text: app.phase === "call"
                                  ? (callLoader.item && callLoader.item.joined ? app.duration(app.now - app.callStart) : qsTr("Waiting…"))
                                  : (app.callVideo ? qsTr("MeetUp Video") : qsTr("MeetUp Audio"))
                            color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                        }
                    }
                    IconButton { id: inviteButton; size: 40; iconName: "message"; color: Qt.rgba(1, 1, 1, 0.16); onClicked: app.invite() }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: (panelColumn.width - 5 * 56) / 4
                    Control {
                        iconName: "flip-camera"
                        enabled: app.phase === "lobby" && app.camOn
                        opacity: enabled ? 1 : 0.4
                        onClicked: app.frontCamera = !app.frontCamera
                    }
                    Control {
                        iconName: "video"
                        on: !app.camOn
                        onClicked: {
                            app.camOn = !app.camOn
                            if (callLoader.item) callLoader.item.setCam(app.camOn)
                        }
                    }
                    Control {
                        iconName: app.micOn ? "mic" : "mic-off"
                        on: !app.micOn
                        onClicked: {
                            app.micOn = !app.micOn
                            if (callLoader.item) callLoader.item.setMic(app.micOn)
                        }
                    }
                    Control { iconName: "share"; onClicked: { linkSheet.open() } }
                    Control { iconName: "phone-hangup"; color: "#FF3B30"; iconColor: "white"; onClicked: app.hangUp() }
                }
            }
        }

        // Join, before the call.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 54
            visible: app.phase === "lobby"
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: app.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: app.callNumber ? qsTr("We opened Messages with the link for %1. Join when you're ready.").arg(app.callName)
                                     : qsTr("Share the link, then join.")
                color: "white"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 200
                height: 54
                radius: 27
                color: app.green
                scale: joinTap.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: qsTr("Join"); color: "white"
                       font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize + 1; font.weight: Font.Bold }
                MouseArea { id: joinTap; anchors.fill: parent; onClicked: app.join() }
            }
        }
    }

    // ---- new call: pick a contact -------------------------------------------------------
    Sheet {
        id: newSheet
        title: qsTr("New MeetUp")
        maxHeight: app.height * 0.92
        Column {
            width: parent.width
            spacing: 14
            TextField { id: toField; width: parent.width; placeholder: qsTr("To: name or number"); inputMethodHints: Qt.ImhNoPredictiveText }
            Column {
                width: parent.width
                Repeater {
                    model: app.contacts.filter(c => !toField.text.trim() || c.name.toLowerCase().includes(toField.text.trim().toLowerCase())
                                                     || (c.phone || "").includes(toField.text.trim())).slice(0, 30)
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 60
                        Rectangle {
                            id: face
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 20
                            color: "#8E929C"
                            Text { anchors.centerIn: parent; text: app.initials(modelData.name); color: "white"
                                   font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold }
                        }
                        Column {
                            anchors.left: face.right
                            anchors.leftMargin: 12
                            anchors.right: buttons.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: Theme.text
                                   font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize }
                            Text { text: modelData.phone || modelData.email || ""; color: Theme.textSecondary
                                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
                        }
                        Row {
                            id: buttons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            IconButton { size: 38; iconName: "phone"; color: Qt.rgba(0.19, 0.82, 0.35, 0.18); iconColor: app.green; onClicked: app.call(modelData, false) }
                            IconButton { size: 38; iconName: "video"; color: app.green; iconColor: "white"; onClicked: app.call(modelData, true) }
                        }
                    }
                }
            }
            Text {
                width: parent.width
                visible: app.contacts.length === 0
                wrapMode: Text.Wrap
                text: qsTr("Your contacts appear here. You can also create a link and send it to anyone.")
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
            }
            Button {
                width: parent.width
                visible: toField.text.trim().length > 0
                primary: false
                text: qsTr("Call “%1”").arg(toField.text.trim())
                onClicked: app.call({ name: toField.text.trim(), phone: /^[+\d\s()-]+$/.test(toField.text.trim()) ? toField.text.trim() : "" }, true)
            }
        }
    }

    // ---- the link of a call -------------------------------------------------------------
    Sheet {
        id: linkSheet
        title: qsTr("MeetUp Link")
        Column {
            width: parent.width
            spacing: 14
            Rectangle {
                width: parent.width
                height: linkText.implicitHeight + 28
                radius: 14
                color: Theme.surfaceRaised
                Text { id: linkText; x: 14; y: 14; width: parent.width - 28; wrapMode: Text.WrapAnywhere; text: app.link
                       color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize }
            }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                   text: qsTr("Anyone with the link can join from a phone or a computer, in the browser.") }
            Button { width: parent.width; primary: false; iconName: "message"; text: qsTr("Send with Messages"); onClicked: app.invite() }
            Button {
                width: parent.width
                visible: app.phase === "home"
                primary: true
                iconName: "video"
                text: qsTr("Join Now")
                onClicked: app.prepare(app.callName || qsTr("MeetUp Link"), "", app.callCode, true)
            }
            Text { width: parent.width; visible: app.phase === "home"; text: qsTr("Or join with a code or a link"); color: Theme.text
                   font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold }
            Row {
                width: parent.width
                visible: app.phase === "home"
                spacing: 10
                TextField { id: codeField; width: parent.width - 110; placeholder: qsTr("abc-defg-hij"); inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly }
                Button { implicitWidth: 100; text: qsTr("Join"); enabled: app.codeOf(codeField.text).length >= 4
                         onClicked: app.prepare(qsTr("MeetUp"), "", app.codeOf(codeField.text), true) }
            }
        }
    }

    // ---- settings ------------------------------------------------------------------------
    Sheet {
        id: settingsSheet
        title: qsTr("MeetUp")
        Column {
            width: parent.width
            spacing: 14
            Text { width: parent.width; text: qsTr("Meeting server"); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold }
            TextField {
                id: serverField
                width: parent.width
                text: app.server
                placeholder: "https://meet.jit.si"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                onAccepted: Settings.setValue("app.com.astra.meetup.server", /^https?:\/\//.test(text.trim()) ? text.trim() : "https://" + text.trim())
            }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                   text: qsTr("MeetUp uses Jitsi Meet. On meet.jit.si whoever opens a room first signs in to start it; with your own Jitsi server nobody has to.") }
            Button { width: parent.width; text: qsTr("Save"); primary: true
                     onClicked: { serverField.accepted(); settingsSheet.close() } }
            Button { width: parent.width; primary: false; text: qsTr("Clear Recent Calls"); visible: app.calls.length > 0
                     onClicked: Settings.setValue("app.com.astra.meetup.calls", []) }
        }
    }

    Component.onCompleted: Permissions.request("astra.permission.CONTACTS")
}
