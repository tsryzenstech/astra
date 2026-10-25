// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core

// Hosts app windows (one per package) and orchestrates the open/close
// transitions between the home screen and apps.
Item {
    id: layer

    property var shell
    property var windows: ({})
    property AppWindow activeWindow: null   // the app in front, if any
    property AppWindow focusWindow: null    // the window currently animating or open
    readonly property real progress: focusWindow ? focusWindow.presence : 0

    readonly property rect centerRect: Qt.rect(width / 2 - 31, height / 2 - 31, 62, 62)

    Component {
        id: windowComponent
        AppWindow {}
    }

    function windowFor(pkg, fromRect) {
        let w = windows[pkg]
        if (!w) {
            const info = Packages.get(pkg)
            w = windowComponent.createObject(layer, { packageName: pkg, info: info, host: layer })
            windows[pkg] = w
        }
        w.fromRect = fromRect || centerRect
        return w
    }

    function bringToFront(w) {
        for (const key in windows)
            windows[key].z = 0
        w.z = 1
        activeWindow = w
        focusWindow = w
    }

    function launch(pkg, args, fromRect) {
        const w = windowFor(pkg, fromRect)
        bringToFront(w)
        w.open()
        Packages.launch(pkg, args)
    }

    function closeActive(velocity) {
        if (!activeWindow)
            return
        const w = activeWindow
        activeWindow = null
        w.close(shell.home.iconRect(w.packageName), velocity)
    }

    // Wayland: a new toplevel. Its app_id (the package name) can arrive
    // after creation.
    function addToplevel(toplevel, xdgSurface) {
        let attached = false
        const attach = () => {
            if (attached || !toplevel.appId)
                return
            attached = true
            let w = windows[toplevel.appId]
            if (!w) {
                // Started without the launcher: open from the centre.
                w = windowFor(toplevel.appId, null)
                bringToFront(w)
                w.open()
            }
            w.attach(toplevel, xdgSurface)
        }
        attach()
        if (!attached)
            toplevel.appIdChanged.connect(attach)
    }

    function windowClosed(w) {
        // The app process went away.
        if (activeWindow === w)
            closeActive(0)
    }

    // Close gesture (swipe up from the bottom edge).
    function beginCloseGesture() {
        if (activeWindow)
            activeWindow.beginGesture()
    }
    function updateCloseGesture(dx, dy) {
        if (activeWindow)
            activeWindow.updateGesture(dx, dy)
    }
    function endCloseGesture(vx, vy) {
        if (!activeWindow)
            return
        if (activeWindow.gestureShouldClose(vy)) {
            const w = activeWindow
            activeWindow = null
            w.closeFromGesture(shell.home.iconRect(w.packageName), vy)
        } else {
            activeWindow.cancelGesture(vy)
        }
    }
}
