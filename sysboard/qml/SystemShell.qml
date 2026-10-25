// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Root of the system UI. Layers, bottom to top:
//   screenContent (wallpaper, home screen, app windows, lock screen)
//   panels        (Notification Center / Control Center over a live blur)
//   edge gestures, home indicator
//   status bar    (always fixed and sharp)
Item {
    id: shell

    property var compositor
    property alias appLayer: apps
    property alias home: home

    property bool locked: true
    readonly property bool appOpen: apps.activeWindow !== null
    readonly property bool panelOpen: panels.reveal > 0.001

    function lock() {
        panels.close()
        lockScreen.lock()
        locked = true
    }

    // Unlock, then optionally run an action (open Settings, Camera...).
    function unlocked(action) {
        locked = false
        if (action)
            action()
    }

    function launch(packageName, args, fromRect) {
        if (locked)
            return
        panels.close()
        apps.launch(packageName, args || {}, fromRect || null)
    }

    function goHome() {
        if (apps.activeWindow)
            apps.closeActive(0)
    }

    Item {
        id: screenContent
        anchors.fill: parent

        Image {
            id: wallpaper
            anchors.fill: parent
            source: Host.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
            // The home screen zooms slightly behind opening apps.
            scale: 1 + 0.06 * apps.progress
        }

        HomeScreen {
            id: home
            anchors.fill: parent
            shell: shell
            appProgress: apps.progress
            interactive: !shell.locked && !shell.appOpen && !shell.panelOpen
        }

        AppLayer {
            id: apps
            anchors.fill: parent
            shell: shell
        }

        LockScreen {
            id: lockScreen
            anchors.fill: parent
            shell: shell
            active: shell.locked
        }
    }

    Panels {
        id: panels
        anchors.fill: parent
        shell: shell
        blurSource: screenContent
    }

    // Pull down from the top edge: left half -> Notification Center,
    // right half -> Control Center.
    MouseArea {
        id: topEdge
        width: parent.width
        height: 44
        z: 10
        // Must not depend on panels.dragging: disabling a MouseArea mid-press cancels the gesture.
        enabled: !panels.opened && !lockScreen.pinPadVisible && !home.editing
        preventStealing: true
        property real startY: 0
        property bool dragging: false
        VelocityTracker { id: topVelocity }
        onPressed: (m) => {
            startY = m.y
            dragging = false
            topVelocity.reset()
            topVelocity.addPoint(m.x, m.y)
        }
        onPositionChanged: (m) => {
            topVelocity.addPoint(m.x, m.y)
            if (!dragging && m.y - startY > 8) {
                dragging = true
                panels.beginDrag(m.x < width / 2 ? "notifications" : "controls")
            }
            if (dragging)
                panels.drag(m.y - startY)
        }
        onReleased: {
            if (dragging)
                panels.endDrag(topVelocity.velocity().y)
            dragging = false
        }
        onCanceled: {
            if (dragging)
                panels.endDrag(0)
            dragging = false
        }
    }

    // Swipe up from the bottom edge: close the current app.
    MouseArea {
        id: bottomEdge
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.homeIndicatorHeight
        z: 10
        enabled: !shell.locked && shell.appOpen && !shell.panelOpen
        preventStealing: true
        property point start
        VelocityTracker { id: bottomVelocity }
        onPressed: (m) => {
            start = Qt.point(m.x, m.y)
            bottomVelocity.reset()
            bottomVelocity.addPoint(m.x, m.y)
            apps.beginCloseGesture()
        }
        onPositionChanged: (m) => {
            bottomVelocity.addPoint(m.x, m.y)
            apps.updateCloseGesture(m.x - start.x, start.y - m.y)
        }
        onReleased: {
            const v = bottomVelocity.velocity()
            apps.endCloseGesture(v.x, -v.y)
        }
    }

    // Home indicator: shown on every screen, like the concepts.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9
        width: 120
        height: 5
        radius: 2.5
        color: "white"
        z: 11
        opacity: lockScreen.pinPadVisible ? 0 : 1
    }

    StatusBar {
        width: parent.width
        z: 20
        showClock: !shell.locked || lockScreen.musicExpanded || shell.panelOpen || lockScreen.pinPadVisible
    }

    Loader {
        // On-screen keyboard (Qt Virtual Keyboard), shared with apps through
        // the Wayland text-input protocol. Optional at runtime.
        z: 30
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: Host.virtualKeyboard
        source: Qt.resolvedUrl("Keyboard.qml")
    }

    Rectangle {
        // Screen off
        anchors.fill: parent
        z: 100
        color: "black"
        visible: !Host.screenOn
        MouseArea { anchors.fill: parent }
    }

    Connections {
        target: Host
        function onPowerKeyPressed() {
            if (Host.screenOn) {
                shell.lock()
                Host.setScreenOn(false)
            } else {
                Host.setScreenOn(true)
            }
        }
    }

    Component.onCompleted: bootTimer.start()
    Timer {
        id: bootTimer
        interval: 400
        onTriggered: System.markBootCompleted()
    }
}
