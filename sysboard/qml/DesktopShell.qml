// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Root of the system UI of astraOS Desktop (docs/DESKTOP.md). The same system as the phone's
// SystemShell (the same springs, notifications, dialogs, alarms, lock screens, panels and permissions),
// laid out for a pointer and a keyboard. Layers, bottom to top:
//   desktop        wallpaper and widgets
//   windows        the apps' windows
//   Activities     open windows and all the apps, over a blur
//   Dock, menu bar
//   Notification Center / Control Center (the bar's clock and status open them)
//   banners, calls, alarms, system dialogs
//   lock screen, setup
Item {
    id: shell

    property var compositor
    property alias appLayer: windows
    property bool locked: true
    readonly property bool appOpen: windows.activeWindow !== null
    readonly property bool panelOpen: panels.reveal > 0.001
    readonly property url wallpaper: Settings.values["display.wallpaper"]
                                     ? System.fileUrl(Settings.values["display.wallpaper"]) : Host.wallpaper

    // ---- what the shared overlays (banners, panels, calls, pickers) expect of a shell ---
    function launch(packageName, args, fromRect) {
        if (locked)
            return
        panels.close()
        activities.close()
        windows.launch(packageName, args || {}, fromRect)
    }
    function lock() {
        panels.close()
        activities.close()
        lockScreen.lock()
        locked = true
    }
    function unlocked(action) {
        locked = false
        if (action)
            action()
    }
    function unlockForCall() { return !locked || !Lock.hasPin }
    function hideKeyboard() {}
    function openLockPicker() { lockPicker.open() }
    function goHome() { activities.close(); panels.close() }
    function openRecents() { activities.open() }
    readonly property var home: ({ iconRect: function() { return null } })

    // ---- the Dock and the menu bar ------------------------------------------------------
    function dockActivate(pkg) {
        if (locked)
            return
        activities.close()
        panels.close()
        windows.toggle(pkg)
    }
    function openActivities() {
        if (locked)
            return
        panels.close()
        activities.toggle()
    }
    // The Dock's context menu: open, keep in the Dock / remove, quit.
    function dockMenu(pkg, at) {
        dockContext.pkg = pkg
        dockContext.at = at
        dockContext.open = true
    }

    // ---- screen off: the desktop locks, then the display sleeps -------------------------
    function sleep() { blackout.fadeTo(1, function() { Host.setScreenOn(false) }) }
    function wake() { Host.setScreenOn(true) }
    Connections {
        target: Host
        function onScreenOnChanged() {
            if (Host.screenOn) {
                blackout.opacity = 1
                blackout.fadeTo(0, null)
            }
        }
        function onPowerKeyPressed() {
            if (powerMenu.active) {
                powerMenu.close()
            } else if (!Host.screenOn) {
                shell.wake()
            } else {
                if (!shell.locked)
                    shell.lock()
                shell.sleep()
            }
        }
        function onPowerKeyLongPressed() {
            Host.setScreenOn(true)
            powerMenu.open()
        }
        function onVolumeStep(delta) { volumeHud.press(delta) }
        function onLockRequested(message) { shell.lock() }
        function onScreenshotRequested() { if (Host.screenOn) screenshot.capture() }
    }

    // ---- the desktop ------------------------------------------------------------------
    Item {
        id: screenContent
        anchors.fill: parent

        Item {
            id: desktop
            anchors.fill: parent
            Image {
                id: wallpaperImage
                anchors.fill: parent
                source: shell.wallpaper
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(width, height)
                asynchronous: true
            }
            DesktopWidgets {
                id: widgets
                x: 26
                y: menuBar.height + 22
                shell: shell
                opacity: windows.activeWindow && windows.activeWindow.maximized ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }

        DesktopWindowLayer {
            id: windows
            anchors.fill: parent
            shell: shell
            workArea: Qt.rect(0, menuBar.height, width, height - menuBar.height - dock.height - 22)
        }

        DesktopActivities {
            id: activities
            anchors.fill: parent
            shell: shell
            windowLayer: windows
            blurSource: desktop
        }

        DesktopDock {
            id: dock
            shell: shell
            windowLayer: windows
            blurSource: desktop
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            // Out of the way when a maximised window covers the bottom, back when the pointer comes.
            opacity: shell.locked ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 240 } }
            enabled: !shell.locked
        }
    }

    DesktopMenuBar {
        id: menuBar
        width: parent.width
        z: 20
        locked: shell.locked
        appName: windows.activeWindow && !windows.activeWindow.minimized ? windows.activeWindow.info.name || "" : ""
        onActivitiesClicked: shell.openActivities()
        onClockClicked: { activities.close(); panels.open("notifications") }
        onStatusClicked: { activities.close(); panels.open("controls") }
        opacity: lockScreen.active ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Panels {
        id: panels
        anchors.fill: parent
        anchors.topMargin: menuBar.height - 4
        z: 3
        shell: shell
        blurSource: screenContent
        contentWidth: 393
        contentLeft: parent.width - 393 - 14
    }

    // ---- the Dock's context menu ------------------------------------------------------
    Item {
        id: dockContext
        anchors.fill: parent
        z: 18
        property bool open: false
        property string pkg
        property point at
        visible: open
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: dockContext.open = false }
        Rectangle {
            x: Math.max(8, Math.min(parent.width - width - 8, dockContext.at.x - width / 2))
            y: Math.max(8, dockContext.at.y - height - 14)
            width: 210
            height: menu.implicitHeight + 16
            radius: 18
            color: Theme.glassPanel
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)
            Column {
                id: menu
                x: 8; y: 8
                width: parent.width - 16
                Repeater {
                    model: {
                        const running = !!windows.windows[dockContext.pkg]
                        const pinned = (Settings.values["desktop.dock"] || []).indexOf(dockContext.pkg) >= 0
                        const out = [{ label: running ? qsTr("Show") : qsTr("Open"), act: "open" }]
                        out.push({ label: pinned ? qsTr("Remove from Dock") : qsTr("Keep in Dock"), act: pinned ? "unpin" : "pin" })
                        if (running)
                            out.push({ label: qsTr("Quit"), act: "quit", danger: true })
                        return out
                    }
                    delegate: Rectangle {
                        required property var modelData
                        width: menu.width
                        height: 38
                        radius: 12
                        color: itemArea.pressed ? Qt.rgba(1, 1, 1, 0.16) : itemArea.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: modelData.danger ? Theme.danger : Theme.text
                        }
                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { shell.dockMenuAction(dockContext.pkg, modelData.act); dockContext.open = false }
                        }
                    }
                }
            }
        }
    }
    function dockMenuAction(pkg, act) {
        const saved = (Settings.values["desktop.dock"] || dock.pinned).slice()
        if (act === "open")
            shell.launch(pkg, {}, null)
        else if (act === "quit")
            windows.stop(pkg)
        else if (act === "pin" && saved.indexOf(pkg) < 0)
            Settings.setValue("desktop.dock", saved.concat([pkg]))
        else if (act === "unpin")
            Settings.setValue("desktop.dock", saved.filter(p => p !== pkg))
    }

    // ---- notifications, calls, alarms, dialogs ------------------------------------------
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

    // Night light: a warm filter over everything.
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

    DesktopLock {
        id: lockScreen
        anchors.fill: parent
        z: 30
        shell: shell
        active: shell.locked
    }

    VolumeHud {
        id: volumeHud
        z: 25
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 60
    }
    PowerMenu {
        id: powerMenu
        anchors.fill: parent
        z: 40
        blurSource: screenContent
        onEmergencyRequested: close()
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
    LockPicker {
        id: lockPicker
        shell: shell
        blurSource: screenContent
        z: 60
    }

    // ---- locks after a while without the keyboard or the pointer ----------------------
    Timer {
        id: idle
        // "desktop.lock_timeout": minutes; 0, never. The display sleeps a little later than the lock.
        interval: Math.max(1, Number(Settings.values["desktop.lock_timeout"] ?? 10)) * 60000
        running: !shell.locked && Host.screenOn && Number(Settings.values["desktop.lock_timeout"] ?? 10) > 0 && !Host.development
                 && !alarm.active
        onTriggered: shell.lock()
    }
    // Any pointer movement or key restarts the timer.
    MouseArea {
        anchors.fill: parent
        z: 99
        hoverEnabled: true
        propagateComposedEvents: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: idle.restart()
    }

    // ---- shortcuts (they work while an app has the focus) ---------------------------------
    Shortcut { sequences: ["Meta+Space", "Ctrl+Space"]; onActivated: shell.openActivities() }
    Shortcut { sequences: ["Ctrl+Alt+L", "Meta+L"]; onActivated: shell.lock() }
    Shortcut { sequences: ["Alt+Tab"]; onActivated: shell.cycleWindows() }
    Shortcut { sequences: ["Ctrl+Q"]; enabled: !shell.locked && windows.activeWindow !== null
               onActivated: windows.closeWindow(windows.activeWindow) }
    function cycleWindows() {
        if (locked)
            return
        const list = windows.recents().filter(w => !w.doomed)
        if (list.length < 2)
            return
        const next = list[1]
        windows.bringToFront(next)
        next.open()
    }

    // The first start: set the computer up (full screen), then straight to the desktop.
    DesktopSetup {
        id: setup
        anchors.fill: parent
        z: 50
        onFinished: lockScreen.finishUnlock()
    }

    Rectangle {
        // Screen off
        anchors.fill: parent
        z: 100
        color: "black"
        visible: !Host.screenOn
        MouseArea { anchors.fill: parent }
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
    // Developer Options > Animation speed applies to the shell right away; Reduce Motion turns motion off.
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
