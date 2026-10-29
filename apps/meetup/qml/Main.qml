// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// MeetUp: start or join a meeting with a code, with a live camera preview
// and microphone/camera switches. Calls need the MeetUp service, which is
// not online in this preview: the app says so instead of pretending.
Rectangle {
    id: app
    color: "#04110A"

    property bool camOn: true
    property bool micOn: true
    property string code: ""
    property string phase: "home"     // home, lobby
    readonly property var recent: Settings.values["app.com.astra.meetup.recent"] || []

    function newCode() {
        const a = "abcdefghijkmnpqrstuvwxyz"
        let s = ""
        for (let i = 0; i < 10; i++)
            s += (i === 3 || i === 7) ? "-" : a.charAt(Math.floor(Math.random() * a.length))
        return s
    }
    function enter(c) {
        code = c
        phase = "lobby"
        Settings.setValue("app.com.astra.meetup.recent", [c].concat(recent.filter(r => r !== c)).slice(0, 5))
        Permissions.request("astra.permission.CAMERA", function(ok) { app.camOn = !!ok })
        Permissions.request("astra.permission.MICROPHONE")
    }

    MediaDevices { id: devices }
    CaptureSession {
        camera: Camera {
            active: app.phase === "lobby" && app.camOn && devices.videoInputs.length > 0
            cameraDevice: {
                for (const d of devices.videoInputs)
                    if (d.position === CameraDevice.FrontFace)
                        return d
                return devices.defaultVideoInput
            }
        }
        videoOutput: selfView
    }

    // ---- home ------------------------------------------------------------------
    Page {
        anchors.fill: parent
        visible: app.phase === "home"
        title: qsTr("MeetUp")
        background: Component { Rectangle { color: "#04110A" } }

        Card {
            accented: true
            Column {
                width: parent.width
                spacing: 12
                Text { text: qsTr("Video calls for everyone"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: "white" }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Start a meeting and share the code, or join one with the code you received.")
                       font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1; color: Qt.rgba(1, 1, 1, 0.9) }
                Button { primary: false; iconName: "video"; text: qsTr("New meeting"); onClicked: app.enter(app.newCode()) }
            }
        }
        Row {
            width: parent.width
            spacing: 10
            TextField { id: codeField; width: parent.width - 110; placeholder: qsTr("Enter a code"); inputMethodHints: Qt.ImhNoPredictiveText }
            Button { implicitWidth: 100; text: qsTr("Join"); enabled: codeField.text.trim().length >= 4; onClicked: app.enter(codeField.text.trim()) }
        }
        ListGroup {
            visible: app.recent.length > 0
            title: qsTr("Recent")
            Repeater {
                model: app.recent
                delegate: ListItem {
                    required property string modelData
                    required property int index
                    text: modelData
                    iconName: "video"
                    chevron: true
                    separator: index < app.recent.length - 1
                    onClicked: app.enter(modelData)
                }
            }
        }
    }

    // ---- lobby -------------------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: app.phase === "lobby"

        Rectangle {
            id: frame
            x: 16
            y: Theme.statusBarHeight + 60
            width: parent.width - 32
            height: parent.height - y - 200
            radius: Theme.sheetRadius
            color: "#0D2418"
            VideoOutput {
                id: selfView
                anchors.fill: parent
                visible: app.camOn
                fillMode: VideoOutput.PreserveAspectCrop
                transform: Scale { xScale: -1; origin.x: selfView.width / 2 }   // mirror, like a mirror
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: frameMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            Rectangle { id: frameMask; anchors.fill: parent; radius: parent.radius; visible: false; layer.enabled: true }
            Column {
                anchors.centerIn: parent
                visible: !app.camOn || devices.videoInputs.length === 0
                spacing: 8
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "person"; size: 64; opacity: 0.6 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Camera off"); font.family: Theme.fontFamily
                       font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.statusBarHeight + 6
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.code; font.family: Theme.fontFamily
                   font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Waiting for the MeetUp service…")
                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: controls.top
            anchors.bottomMargin: 16
            width: parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: qsTr("MeetUp calls go online with a later astraOS update. Your camera and microphone are ready.")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.textTertiary
        }
        Row {
            id: controls
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 60
            spacing: 22
            IconButton { size: 62; iconName: app.micOn ? "mic" : "mic-off"; color: app.micOn ? Qt.rgba(1, 1, 1, 0.14) : "white"
                         iconColor: app.micOn ? "white" : "#111"; onClicked: app.micOn = !app.micOn }
            IconButton { size: 62; iconName: "video"; color: app.camOn ? Qt.rgba(1, 1, 1, 0.14) : "white"
                         iconColor: app.camOn ? "white" : "#111"; onClicked: app.camOn = !app.camOn }
            IconButton { size: 62; iconName: "phone-hangup"; color: "#FF3B30"; onClicked: app.phase = "home" }
        }
    }
}
