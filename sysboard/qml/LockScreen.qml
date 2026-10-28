// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Lock screen (LockScreen1.png).
//  - swipe up anywhere: PIN pad (or unlock right away without a PIN)
//  - long press on an empty area: PIN, then Settings > Lock Screen
//  - long press the torch / camera buttons (they grow while held)
//  - music pill when something plays; tap it to expand, swipe down to close
Item {
    id: root

    property var shell
    property bool active: true
    readonly property bool pinPadVisible: pinPad.progress > 0.01
    readonly property bool musicExpanded: music.expanded
    property var pendingAction: null

    readonly property var clockWeights: ({
        "Thin": Font.Thin, "ExtraLight": Font.ExtraLight, "Light": Font.Light, "Regular": Font.Normal,
        "Medium": Font.Medium, "SemiBold": Font.DemiBold, "Bold": Font.Bold, "ExtraBold": Font.ExtraBold,
        "Black": Font.Black
    })

    visible: active || exit.running || exit.value < 0.999

    function lock() {
        exit.snap(0)
        swipe.snap(0)
        pinPad.hide(true)
        music.expanded = false
        pendingAction = null
    }

    // Ask for the PIN (if any), then run action after unlocking.
    function authenticate(action) {
        pendingAction = action
        if (Lock.hasPin) {
            swipe.animateTo(1, 0)
            pinPad.show()
        } else {
            finishUnlock()
        }
    }

    function finishUnlock() {
        const action = pendingAction
        pendingAction = null
        exit.animateTo(1, 0)
        root.shell.unlocked(action)
    }

    // 0 = lock screen, 1 = content swiped away (PIN pad or unlocked)
    Spring { id: swipe; to: 0; response: 0.42; dampingFraction: 0.9 }
    // 0 = visible, 1 = dissolved after a successful unlock
    Spring { id: exit; to: 0; response: 0.45; dampingFraction: 1.0 }

    opacity: 1 - exit.value
    scale: 1 + 0.12 * exit.value

    Item {
        id: lockContent
        anchors.fill: parent

        Image {
            anchors.fill: parent
            source: root.shell ? root.shell.wallpaper : Host.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
        }

        Item {
            id: faceplate
            anchors.fill: parent
            opacity: (1 - swipe.value) * (1 - music.progress)
            y: -swipe.value * 120

            Icon {
                name: "lock"
                size: 22
                anchors.horizontalCenter: parent.horizontalCenter
                y: 78
                opacity: 0.85
            }

            Text {
                id: time
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.baseline: parent.top
                anchors.baselineOffset: 228
                text: SystemClock.time
                // Settings > Lock Screen: Poppins at any weight, or another installed family.
                font.family: Settings.values["lockscreen.clock_font"] || Theme.fontFamily
                font.pixelSize: 118
                font.weight: root.clockWeights[Settings.values["lockscreen.clock_weight"] || "SemiBold"] ?? Font.DemiBold
                font.letterSpacing: -3
                color: "white"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.baseline: parent.top
                anchors.baselineOffset: 263
                text: SystemClock.longDate
                font.family: Theme.fontFamily
                font.pixelSize: 21
                color: "white"
            }

            LockWidgets {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 278
            }
        }

        LockButton {
            id: torchButton
            x: 23
            anchors.verticalCenter: parent.bottom
            anchors.verticalCenterOffset: -79
            iconName: "flashlight"
            checked: System.torch
            opacity: faceplate.opacity
            onActivated: System.setTorch(!System.torch)
        }

        LockButton {
            id: cameraButton
            anchors.right: parent.right
            anchors.rightMargin: 23
            anchors.verticalCenter: parent.bottom
            anchors.verticalCenterOffset: -79
            iconName: "camera"
            opacity: faceplate.opacity
            onActivated: root.authenticate(() => root.shell.launch("com.astra.camera"))
        }

        MusicPill {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.bottom
            anchors.verticalCenterOffset: -77
            opacity: faceplate.opacity
            onExpandRequested: music.expanded = true
        }
    }

    MusicPlayer {
        id: music
        anchors.fill: parent
    }

    // Gestures on the lock screen surface.
    MouseArea {
        id: surface
        anchors.fill: parent
        z: -1
        enabled: root.active && !root.pinPadVisible
        property point start
        property bool moved: false
        VelocityTracker { id: velocity }

        onPressed: (m) => {
            start = Qt.point(m.x, m.y)
            moved = false
            velocity.reset()
            velocity.addPoint(m.x, m.y)
        }
        onPositionChanged: (m) => {
            velocity.addPoint(m.x, m.y)
            const dy = m.y - start.y
            if (!moved && Math.abs(dy) > 10)
                moved = true
            if (!moved)
                return
            if (music.expanded)
                music.drag(Math.max(0, dy))
            else if (dy < 0)
                swipe.value = Math.min(1, -dy / (root.height * 0.45))
        }
        onReleased: {
            const vy = velocity.velocity().y
            if (music.expanded) {
                music.release(vy)
            } else if (moved) {
                if (swipe.value > 0.3 || vy < -600)
                    root.authenticate(null)
                else
                    swipe.animateTo(0, -vy / (root.height * 0.45))
            }
        }
        pressAndHoldInterval: 650
        onPressAndHold: {
            if (!moved && !music.expanded)
                root.authenticate(() => root.shell.launch("com.astra.settings", { page: "lockscreen" }))
        }
    }

    BlurLayer {
        anchors.fill: parent
        source: lockContent
        amount: pinPad.progress
        dim: 0.35
    }

    PinPad {
        id: pinPad
        anchors.fill: parent
        onAccepted: root.finishUnlock()
        onCancelled: {
            root.pendingAction = null
            swipe.animateTo(0, 0)
        }
    }

    Connections {
        target: Lock
        // Removing the PIN while the pad is open unlocks right away.
        function onChanged() { if (!Lock.hasPin && root.pinPadVisible) root.finishUnlock() }
    }
}
