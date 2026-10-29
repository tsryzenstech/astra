// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Root of the system UI. Layers, bottom to top:
//   screenContent (wallpaper, home screen, app windows, lock screen)
//   Recents, panels (Notification Center / Control Center over a live blur)
//   edge gestures, home indicator, push notification banners
//   incoming call, alarms, system dialogs
//   status bar    (always fixed and sharp)
Item {
    id: shell

    property var compositor
    property alias appLayer: apps
    property alias home: home

    property bool locked: true
    readonly property bool appOpen: apps.activeWindow !== null
    readonly property bool panelOpen: panels.reveal > 0.001
    readonly property url wallpaper: Settings.values["display.wallpaper"]
                                     ? System.fileUrl(Settings.values["display.wallpaper"]) : Host.wallpaper

    function lock() {
        panels.close()
        recents.close()
        lockScreen.lock()
        locked = true
    }

    // Unlock, then optionally run an action (open Settings, Camera...).
    function unlocked(action) {
        locked = false
        if (!appOpen)
            home.playEntrance()
        if (action)
            action()
    }

    // Answering a call: without a PIN the phone unlocks so the Phone app can
    // show the call; with one the call simply goes on.
    function unlockForCall() {
        if (!locked)
            return true
        if (Lock.hasPin)
            return false
        lockScreen.authenticate(null)
        return true
    }

    function launch(packageName, args, fromRect) {
        if (locked)
            return
        panels.close()
        recents.close()
        // An icon on the visible home page is the natural origin.
        const origin = fromRect || (!appOpen ? home.iconRect(packageName) : null)
        apps.launch(packageName, args || {}, origin)
    }

    // Leaving an app (or a text field) puts the keyboard away.
    // ---- screen off / on ----------------------------------------------------
    // The screen fades to black before the panel goes off (or to the Always
    // On Display), and fades in from black when it comes back.
    property bool aod: false
    property real savedBrightness: -1
    function sleep() {
        hideKeyboard()
        blackout.fadeTo(1, function() {
            if (Settings.values["display.aod"]) {
                shell.aod = true
                shell.savedBrightness = System.brightness
                System.setBrightness(Math.min(System.brightness, 0.08))
                blackout.opacity = 0
            } else {
                Host.setScreenOn(false)
            }
        })
    }
    function wake() {
        if (aod) {
            aod = false
            if (savedBrightness >= 0)
                System.setBrightness(savedBrightness)
            savedBrightness = -1
            blackout.opacity = 1
            blackout.fadeTo(0, null)
        } else {
            Host.setScreenOn(true)
        }
    }
    // A ringing alarm or call wakes the phone from the Always On Display.
    Connections {
        target: alarm
        function onActiveChanged() { if (alarm.active && shell.aod) shell.wake() }
    }
    Connections {
        target: call
        function onRingingFullChanged() { if (call.ringingFull && shell.aod) shell.wake() }
    }
    Connections {
        target: Host
        function onScreenOnChanged() {
            if (Host.screenOn) {
                blackout.opacity = 1
                blackout.fadeTo(0, null)
            }
        }
    }

    function hideKeyboard() {
        if (Host.keyboard)
            Host.keyboard.hide()
    }
    // Notification Center and Control Center cover what you were typing in.
    Connections {
        target: panels
        function onOpenedChanged() { if (panels.opened) shell.hideKeyboard() }
    }
    Connections {
        target: apps
        function onActiveWindowChanged() { shell.hideKeyboard() }
    }

    function goHome() {
        recents.close()
        if (apps.activeWindow)
            apps.closeActive(0)
    }

    function openRecents() {
        panels.close()
        recents.open()
        if (apps.activeWindow)
            apps.closeActiveToCard(recents.firstCardRect(), recents.cardRadius, 0)
    }

    Item {
        id: screenContent
        anchors.fill: parent

        Item {
            id: homeLayer
            anchors.fill: parent

            Image {
                id: wallpaper
                anchors.fill: parent
                source: shell.wallpaper
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
                hiddenPackage: apps.morphingPackage
                // Taps keep working until the opening app nearly covers the screen.
                interactive: !shell.locked && !shell.panelOpen && !recents.shown
                             && !(apps.activeWindow && apps.activeWindow.progress > 0.85)
                appLayer: apps
            }
        }

        // Between home and apps: windows shrink into and grow out of the
        // cards above the blur.
        Recents {
            id: recents
            anchors.fill: parent
            shell: shell
            apps: apps
            blurSource: homeLayer
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
        z: 3
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
        enabled: !panels.opened && !lockScreen.pinPadVisible && !home.editing && !dialogs.active && !alarm.active
                 && !call.ringingFull
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
                recents.close()
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

    // Swipe up from the bottom edge: close the current app. Swipe up and
    // hold still for a moment: Recents (from an app or from home).
    MouseArea {
        id: bottomEdge
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.homeIndicatorHeight
        z: 10
        enabled: !shell.locked && !shell.panelOpen && !recents.shown && !dialogs.active && !home.editing
        preventStealing: true
        property point start
        property point anchor          // where the finger last stopped
        property bool inApp: false
        property bool toRecents: false
        VelocityTracker { id: bottomVelocity }

        onPressed: (m) => {
            start = Qt.point(m.x, m.y)
            anchor = start
            toRecents = false
            inApp = shell.appOpen
            bottomVelocity.reset()
            bottomVelocity.addPoint(m.x, m.y)
            if (inApp) {
                apps.beginCloseGesture()
                indicator.following = true
                shell.hideKeyboard()
            }
            holdTimer.stop()
        }
        onPositionChanged: (m) => {
            bottomVelocity.addPoint(m.x, m.y)
            if (toRecents)
                return
            const dy = start.y - m.y
            if (!inApp) {
                // On home the bar follows the finger and the page shrinks.
                home.recentsPull = Math.max(0, Math.min(1, dy / 320))
                indicator.following = true
                indicator.followX = m.x - start.x
                indicator.followY = Math.max(0, dy) * 0.45
            }
            if (inApp) {
                apps.updateCloseGesture(m.x - start.x, dy)
                const w = apps.activeWindow
                if (w) {
                    // Sit just under the shrinking window.
                    indicator.followX = w.gestureX
                    indicator.followY = shell.height / 2 * (1 - w.gestureScale) + w.gestureY * 0.35
                }
            }
            // The finger resting anywhere after a real swipe (even with the
            // app almost gone) opens Recents. A resting finger still
            // jitters a little: speed, not position, tells it apart.
            const v = bottomVelocity.velocity()
            // A long, slowing swipe goes straight to Recents.
            if (dy > shell.height * 0.32 && Math.hypot(v.x, v.y) < 420) {
                holdTimer.stop()
                holdTimer.triggered()
                return
            }
            if (dy > 30 && Math.hypot(v.x, v.y) < 220) {
                if (!holdTimer.running)
                    holdTimer.start()
            } else {
                holdTimer.stop()
            }
        }
        onReleased: {
            holdTimer.stop()
            pullBack.restart()
            const v = bottomVelocity.velocity()
            indicator.release(v.x, v.y)
            if (toRecents)
                return
            if (inApp)
                apps.endCloseGesture(v.x, -v.y)
        }
        onCanceled: {
            holdTimer.stop()
            indicator.release(0, 0)
            if (inApp && !toRecents)
                apps.endCloseGesture(0, 0)
        }
        // The home page grows back when the finger lets go.
        NumberAnimation { id: pullBack; target: home; property: "recentsPull"; to: 0; duration: 320; easing.type: Easing.OutBack }
        Timer {
            id: holdTimer
            interval: 180
            onTriggered: {
                bottomEdge.toRecents = true
                indicator.release(0, 0)
                shell.openRecents()
            }
        }
    }

    HomeIndicator {
        id: indicator
        color: shell.lightApp ? "#0B0B0F" : "white"
        anchors.bottom: parent.bottom
        z: 11
        opacity: lockScreen.pinPadVisible || alarm.active || call.ringingFull ? 0 : 1
    }

    NotificationBanner {
        id: banner
        z: 12
        shell: shell
        suppressed: panels.opened || call.ringingFull || alarm.active
                    || (shell.locked && Settings.values["notifications.lockscreen"] === false)
    }

    CallScreen {
        id: call
        anchors.fill: parent
        z: 13
        shell: shell
    }

    AlarmScreen {
        id: alarm
        anchors.fill: parent
        z: 14
    }

    SystemDialog {
        id: dialogs
        anchors.fill: parent
        z: 15
    }

    // Night light: a warm filter over everything but the status bar.
    Rectangle {
        anchors.fill: parent
        z: 19
        enabled: false
        color: "#FF8A1F"
        readonly property real strength: Number(Settings.values["display.night_light_strength"] ?? 0.5)
        opacity: Settings.values["display.night_light"] ? 0.08 + 0.17 * strength : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    // Light apps get dark status bar content and home indicator.
    readonly property bool lightApp: Theme.light && apps.activeWindow !== null && apps.activeWindow.progress > 0.6
                                     && apps.activeWindow.info.appearance !== "dark" && !panels.opened && !recents.shown

    StatusBar {
        width: parent.width
        z: 20
        tint: shell.lightApp && !shell.locked ? "#0B0B0F" : "white"
        detailed: panels.reveal > 0.5 && panels.page > 0.5
        showClock: !shell.locked || lockScreen.musicExpanded || shell.panelOpen || lockScreen.pinPadVisible
        inCall: call.ongoing !== null && !(apps.activeWindow && apps.activeWindow.packageName === "com.astra.phone")
                && !call.ringingFull
        onCallPillClicked: shell.launch("com.astra.phone", { call: call.ongoing.id }, null)
    }

    Loader {
        // On-screen keyboard (Keyboard.qml + the astra input method), shared with apps through
        // the Wayland text-input protocol. Optional at runtime.
        z: 30
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: Host.virtualKeyboard
        source: Qt.resolvedUrl("Keyboard.qml")
        onLoaded: {
            apps.keyboardInset = Qt.binding(() => item.shown ? item.panelHeight : 0)
            item.blurSource = screenContent
        }
    }

    Rectangle {
        // Screen off
        anchors.fill: parent
        z: 100
        color: "black"
        visible: !Host.screenOn
        MouseArea { anchors.fill: parent }
    }

    // ---- hardware buttons --------------------------------------------------
    VolumeHud {
        id: volumeHud
        z: 25
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -80
    }

    PowerMenu {
        id: powerMenu
        anchors.fill: parent
        z: 40
        blurSource: screenContent
        onEmergencyRequested: {
            close()
            call.emergency = true
            Telephony.call("dial", { number: Settings.values["telephony.emergency_number"] || "112" }, function(r, err) {
                if (err)
                    call.emergency = false
            })
        }
    }

    ScreenshotPreview {
        id: screenshot
        anchors.fill: parent
        z: 41
        onEditRequested: (path) => editor.edit(path)
    }

    ScreenshotEditor {
        id: editor
        anchors.fill: parent
        z: 42
    }

    Connections {
        target: Host
        // Power: unlocked -> lock screen; on the lock screen -> screen off;
        // screen off -> on. Held: the power menu.
        function onPowerKeyPressed() {
            if (powerMenu.active) {
                powerMenu.close()
            } else if (!Host.screenOn || shell.aod) {
                shell.wake()
            } else if (!shell.locked) {
                shell.hideKeyboard()
                shell.lock()
            } else {
                shell.sleep()
            }
        }
        function onPowerKeyLongPressed() {
            Host.setScreenOn(true)
            powerMenu.open()
        }
        function onVolumeStep(delta) {
            // A ringing alarm or call is silenced by either volume button.
            if (alarm.active)
                return
            if (!Host.screenOn && !MediaController.active)
                return
            volumeHud.press(delta)
        }
        // Find My Device > Lock from the AstraID website.
        function onLockRequested(message) {
            shell.hideKeyboard()
            panels.close()
            shell.lock()
        }
        function onScreenshotRequested() {
            if (!Host.screenOn)
                return
            screenshot.capture()
        }
    }

    // Turns the screen off after the timeout chosen in Settings > Display.
    Timer {
        id: idle
        // Battery saver at 20% or less: at most 30 seconds.
        readonly property bool saving: !!Settings.values["battery.saver"] && System.batteryLevel <= 20 && !System.charging
        interval: Math.max(15, saving ? Math.min(30, Number(Settings.values["display.screen_timeout"] ?? 60)) || 30
                                      : Number(Settings.values["display.screen_timeout"] ?? 60)) * 1000
        // "Never" (0), a ringing alarm or call, or Stay awake keep it on.
        readonly property bool allowed: Host.screenOn && !shell.aod && !alarm.active && !call.ringingFull && call.ongoing === null
                 && !(Settings.values["developer.enabled"] && Settings.values["developer.stay_awake"] && System.charging)
                 && Number(Settings.values["display.screen_timeout"] ?? 60) > 0 && !Host.development
        running: allowed
        onTriggered: {
            shell.lock()
            shell.sleep()
        }
    }
    // Any touch restarts the idle timer.
    MouseArea {
        anchors.fill: parent
        z: 99
        propagateComposedEvents: true
        onPressed: (m) => {
            if (idle.allowed)
                idle.restart()
            m.accepted = false
        }
    }

    // First start: set the phone up, then straight to the home screen.
    SetupWizard {
        anchors.fill: parent
        z: 25
        onFinished: lockScreen.finishUnlock(0)
    }

    AlwaysOnDisplay {
        anchors.fill: parent
        z: 96
        active: shell.aod
        onWakeRequested: shell.wake()
    }
    Rectangle {
        id: blackout
        anchors.fill: parent
        z: 97
        color: "black"
        opacity: 0
        visible: opacity > 0.001
        property var done: null
        function fadeTo(target, then) {
            done = then
            fade.to = target
            fade.duration = target > opacity ? 260 : 340
            fade.restart()
        }
        NumberAnimation on opacity {
            id: fade
            running: false
            easing.type: Easing.InOutQuad
            onFinished: { const d = blackout.done; blackout.done = null; if (d) d() }
        }
        MouseArea { anchors.fill: parent; enabled: blackout.opacity > 0.5 }
    }

    DeveloperOverlay {
        anchors.fill: parent
        z: 98
    }
    // Developer Options > Animation speed applies to the shell right away;
    // Reduce Motion and battery saver turn motion off.
    Binding {
        target: Motion
        property: "durationScale"
        value: !!Settings.values["accessibility.reduce_motion"] ? 0
             : !Settings.values["developer.enabled"] ? 1
             : Number(Settings.values["developer.animation_scale"] ?? 1)
    }

    Component.onCompleted: bootTimer.start()
    Timer {
        id: bootTimer
        interval: 400
        onTriggered: System.markBootCompleted()
    }
}
