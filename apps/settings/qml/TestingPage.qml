// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Developer testing tools: exercise the system services end to end.
Page {
    id: page
    title: "Testing"

    // ---- Notifications ------------------------------------------------------
    readonly property var apps: Packages.count >= 0 ? Packages.list() : []
    property int appIndex: Math.max(0, apps.findIndex(p => p.package === "com.astra.tips"))
    readonly property var app: apps.length ? apps[appIndex % apps.length] : null
    property int sent: 0
    readonly property var samples: [
        ["Welcome to astra! Start by configuring your device.", "Open Settings to connect to Wi-Fi and choose your widgets."],
        ["9+ Missed calls by “Mom ❤️”", "Tap to call back."],
        ["Your package is on its way", "Estimated delivery: tomorrow, 9:00 - 13:00."],
        ["Meeting in 10 minutes", "Weekly sync • Room Cosmos"]
    ]

    ListGroup {
        title: "Lock screen"
        ListItem {
            text: "Go to the lock screen"
            subtitle: "Locks the phone now, like the power button."
            iconName: "lock"
            separator: false
            onClicked: System.power("lock")
        }
    }

    ListGroup {
        title: "Notifications"
        ListItem {
            text: "Post as"
            value: page.app ? page.app.name : "—"
            iconSource: page.app ? page.app.iconUrl : ""
            chevron: true
            onClicked: page.appIndex = (page.appIndex + 1) % Math.max(1, page.apps.length)
        }
        Item {
            width: parent.width
            height: 140
            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                TextField { id: titleField; width: parent.width; placeholder: "Title (empty: sample text)" }
                TextField { id: bodyField; width: parent.width; placeholder: "Details (optional)" }
            }
        }
        ListItem {
            text: "Post notification"
            iconName: "notification"
            onClicked: {
                const sample = page.samples[page.sent++ % page.samples.length]
                Notifications.post(titleField.text || sample[0], titleField.text ? bodyField.text : sample[1],
                                   page.app ? page.app.package : "")
            }
        }
        ListItem {
            text: "Post 3 notifications, 1 s apart"
            onClicked: burst.remaining = 3
        }
        ListItem {
            text: "Clear all notifications"
            value: Notifications.count
            destructive: true
            separator: false
            enabled: Notifications.count > 0
            onClicked: Notifications.clear()
        }
        Timer {
            id: burst
            property int remaining: 0
            interval: 1000
            running: remaining > 0
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const sample = page.samples[page.sent++ % page.samples.length]
                Notifications.post(sample[0], sample[1], page.app ? page.app.package : "")
                remaining--
            }
        }
    }

    // ---- Media session --------------------------------------------------------
    property bool mediaOn: false
    property string lastCommand: "none"

    MediaSession {
        id: testSession
        active: page.mediaOn
        title: "Hell of A Life"
        artist: "astra Test Artist"
        album: "Developer Preview"
        duration: 358000
        playing: false
        Component.onCompleted: setArtworkImage(System.fileUrl("/system/media/wallpapers/default_wallpaper.png"))
        onCommand: (action, position) => {
            switch (action) {
            case "play": playing = true; break
            case "pause": playing = false; break
            case "toggle": playing = !playing; break
            case "seek": testSession.position = position; break
            case "next":
            case "previous": testSession.position = 0; break
            }
            page.lastCommand = action
        }
    }

    ListGroup {
        title: "Media session"
        ListItem {
            text: "Publish a test session"
            subtitle: "Shows the music player on the lock screen and in Control Center"
            showSwitch: true
            checked: page.mediaOn
            onToggled: (on) => page.mediaOn = on
        }
        ListItem {
            text: testSession.playing ? "Pause" : "Play"
            enabled: page.mediaOn
            onClicked: testSession.playing = !testSession.playing
        }
        ListItem {
            text: "Last command from SysBoard"
            value: page.lastCommand
            separator: false
        }
    }

    // ---- AnimationEngine ------------------------------------------------------
    ListGroup {
        title: "AnimationEngine"
        Item {
            width: parent.width
            height: 110
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 20 + ball.value * (parent.width - 40 - width)
                width: 56
                height: 56
                radius: 28
                color: Theme.accent
                scale: 0.8 + 0.2 * Math.max(0, Math.min(1.2, 1 - Math.abs(ball.velocity) / 30))
            }
            Spring {
                id: ball
                to: 0
                response: response.value
                dampingFraction: damping.value
            }
            MouseArea { anchors.fill: parent; onClicked: ball.to = ball.to > 0.5 ? 0 : 1 }
        }
        Item {
            width: parent.width
            height: 46
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Response " + response.value.toFixed(2) + " s"
                   font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.textSecondary }
            Slider { id: response; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                     width: parent.width * 0.5; from: 0.1; to: 1.5; value: 0.5 }
        }
        Item {
            width: parent.width
            height: 46
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Damping " + damping.value.toFixed(2)
                   font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.textSecondary }
            Slider { id: damping; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                     width: parent.width * 0.5; from: 0.1; to: 1.5; value: 0.7 }
        }
        Row {
            x: 12
            height: 56
            spacing: 8
            Repeater {
                model: [["Snappy", Motion.snappy], ["Smooth", Motion.smooth], ["Bouncy", Motion.bouncy], ["Gentle", Motion.gentle]]
                delegate: Button {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 78
                    implicitHeight: 34
                    primary: false
                    text: modelData[0]
                    onClicked: {
                        response.value = modelData[1].response
                        damping.value = modelData[1].dampingFraction
                        ball.to = ball.to > 0.5 ? 0 : 1
                    }
                }
            }
        }
        ListItem {
            text: "Settle time"
            value: Motion.duration(response.value, damping.value) + " ms"
            separator: false
        }
    }

    // ---- Hardware -------------------------------------------------------------
    ListGroup {
        title: "Hardware"
        ListItem { text: "Battery"; value: System.batteryLevel + "%" + (System.charging ? " • charging" : "") }
        ListItem {
            text: "Torch"
            showSwitch: true
            checked: System.torch
            enabled: System.torchAvailable
            separator: false
            onToggled: (on) => System.setTorch(on)
        }
    }

    // ---- Services ---------------------------------------------------------------
    property string pingResult: ""
    ListGroup {
        title: "System services"
        ListItem {
            text: "Ping astrad"
            value: page.pingResult
            onClicked: {
                const t = Date.now()
                System.call("system.ping", {}, (r, e) => page.pingResult = e ? e : (Date.now() - t) + " ms")
            }
        }
        ListItem {
            text: "Refresh weather"
            value: Weather.available ? Weather.current.city + " " + Weather.current.temperature + "°" : "no data"
            onClicked: System.call("weather.refresh", {}, null)
        }
        ListItem { text: "Restart SysBoard"; separator: false; onClicked: System.power("restart-sysboard") }
    }
}
