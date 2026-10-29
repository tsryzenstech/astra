// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Camera: photo and video with the front and back cameras. Shots go to
// DCIM/Camera, where Gallery finds them.
Rectangle {
    id: app
    color: "black"

    property bool granted: false
    property bool checked: false
    property string mode: Application.args.mode === "video" ? "video" : "photo"
    property bool front: false
    property string lastShot: ""
    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
    readonly property bool hasCamera: devices.videoInputs.length > 0

    function stamp() { return Qt.locale().toString(new Date(), "yyyyMMdd_HHmmss") }
    function folder() { return Application.mediaDir + "/DCIM/Camera" }

    Component.onCompleted: {
        Permissions.check("astra.permission.CAMERA", function(ok) {
            app.granted = !!ok
            app.checked = true
            if (ok)
                Permissions.request("astra.permission.MEDIA")
        })
    }

    MediaDevices { id: devices }

    CaptureSession {
        id: session
        camera: Camera {
            id: camera
            active: app.granted && app.hasCamera && Qt.application.state === Qt.ApplicationActive
            cameraDevice: {
                const list = devices.videoInputs
                for (const d of list)
                    if ((d.position === CameraDevice.FrontFace) === app.front)
                        return d
                return devices.defaultVideoInput
            }
            flashMode: flash.mode
        }
        imageCapture: ImageCapture {
            id: imageCapture
            onImageSaved: (id, path) => app.lastShot = "file://" + path
        }
        recorder: MediaRecorder {
            id: recorder
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState && actualLocation.toString()) app.lastShot = ""
        }
        audioInput: app.mode === "video" ? mic : null
        videoOutput: viewfinder
    }
    AudioInput { id: mic }

    VideoOutput {
        id: viewfinder
        anchors.fill: parent
        anchors.topMargin: 90
        anchors.bottomMargin: 210
        fillMode: VideoOutput.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: viewMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Rectangle { id: viewMask; anchors.fill: viewfinder; radius: 28; visible: false; layer.enabled: true }

    // Grid lines
    Item {
        anchors.fill: viewfinder
        opacity: 0.25
        Repeater {
            model: 2
            Rectangle { x: (index + 1) * parent.width / 3; width: 1; height: parent.height; color: "white"; required property int index }
        }
        Repeater {
            model: 2
            Rectangle { y: (index + 1) * parent.height / 3; height: 1; width: parent.width; color: "white"; required property int index }
        }
    }

    // Shutter blink
    Rectangle {
        id: blink
        anchors.fill: viewfinder
        radius: 28
        color: "black"
        opacity: 0
        SequentialAnimation on opacity {
            id: blinkAnim
            running: false
            NumberAnimation { to: 0.85; duration: 50 }
            NumberAnimation { to: 0; duration: 220 }
        }
    }

    Column {
        anchors.centerIn: viewfinder
        visible: app.checked && (!app.granted || !app.hasCamera)
        width: parent.width - 60
        spacing: 18
        EmptyState {
            iconName: "camera"
            title: !app.granted ? qsTr("Camera access") : qsTr("No camera found")
            message: !app.granted ? qsTr("Allow Camera to take photos and videos.") : qsTr("The camera of this phone is not available yet.")
        }
        Button {
            visible: !app.granted
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Allow access")
            onClicked: Permissions.request("astra.permission.CAMERA", function(ok) { app.granted = !!ok })
        }
    }

    // Top controls
    Row {
        x: 20
        y: Theme.statusBarHeight + 2
        spacing: 12
        IconButton {
            id: flash
            property int mode: Camera.FlashOff
            size: 40
            iconName: mode === Camera.FlashOff ? "flash-off" : "flash"
            iconColor: mode === Camera.FlashOn ? "#FFD60A" : "white"
            color: Qt.rgba(1, 1, 1, 0.12)
            onClicked: mode = mode === Camera.FlashOff ? Camera.FlashOn : mode === Camera.FlashOn ? Camera.FlashAuto : Camera.FlashOff
            Text {
                visible: flash.mode === Camera.FlashAuto
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                text: "A"
                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: "#FFD60A"
            }
        }
    }
    Rectangle {
        visible: app.recording
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.statusBarHeight + 6
        width: recText.implicitWidth + 24
        height: 30
        radius: 15
        color: Theme.danger
        Text {
            id: recText
            anchors.centerIn: parent
            text: { const s = Math.floor(recorder.duration / 1000); return app.two(Math.floor(s / 60)) + ":" + app.two(s % 60) }
            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white"
        }
    }
    function two(n) { return (n < 10 ? "0" : "") + n }

    // Mode switch
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 168
        spacing: 26
        Repeater {
            model: [ { id: "video", label: qsTr("VIDEO") }, { id: "photo", label: qsTr("PHOTO") } ]
            delegate: Text {
                required property var modelData
                text: modelData.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                color: app.mode === modelData.id ? "#FFD60A" : "white"
                MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !app.recording; onClicked: app.mode = modelData.id }
            }
        }
    }

    // Bottom bar
    Item {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        width: parent.width
        height: 100

        // Last shot -> Gallery
        Rectangle {
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            width: 54
            height: 54
            radius: 14
            color: Theme.surfaceRaised
            clip: true
            Image {
                anchors.fill: parent
                source: app.lastShot
                sourceSize: Qt.size(108, 108)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            MouseArea { anchors.fill: parent; onClicked: Packages.launch("com.astra.gallery") }
        }

        // Shutter
        Item {
            anchors.centerIn: parent
            width: 82
            height: 82
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 4; border.color: "white" }
            Rectangle {
                anchors.centerIn: parent
                width: app.recording ? 30 : 66
                height: width
                radius: app.recording ? 8 : width / 2
                color: app.mode === "video" ? Theme.danger : "white"
                scale: shutter.pressed ? 0.88 : 1
                Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                Behavior on width { SpringNumberAnimation { preset: Motion.bouncy } }
                Behavior on radius { NumberAnimation { duration: 160 } }
            }
            MouseArea {
                id: shutter
                anchors.fill: parent
                enabled: app.granted && app.hasCamera
                onClicked: {
                    if (app.mode === "photo") {
                        blinkAnim.restart()
                        imageCapture.captureToFile(app.folder() + "/IMG_" + app.stamp() + ".jpg")
                    } else if (app.recording) {
                        recorder.stop()
                    } else {
                        recorder.outputLocation = "file://" + app.folder() + "/VID_" + app.stamp() + ".mp4"
                        recorder.record()
                    }
                }
            }
        }

        // Switch camera
        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            size: 54
            iconName: "flip-camera"
            color: Qt.rgba(1, 1, 1, 0.12)
            enabled: devices.videoInputs.length > 1 && !app.recording
            onClicked: app.front = !app.front
            rotation: app.front ? 180 : 0
            Behavior on rotation { SpringNumberAnimation { preset: Motion.bouncy } }
        }
    }
}
