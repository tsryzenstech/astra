// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core

// Hosts app windows (one per package) and orchestrates the transitions
// between the home screen, apps and Recents.
//
// Only one app is ever visible: when an app opens over another (from a
// notification, Control Center...), the one below goes to the background
// once the new one has settled. Leaving an app always shows the home screen.
Item {
    id: layer

    property var shell
    property var windows: ({})
    property AppWindow activeWindow: null   // the app in front, if any
    property AppWindow focusWindow: null    // the window currently animating or open
    readonly property real progress: focusWindow ? focusWindow.presence : 0
    // The home screen hides this package's icon: the window is (growing out of) it.
    readonly property string morphingPackage: focusWindow && (focusWindow.morphing || focusWindow === activeWindow)
                                              ? focusWindow.packageName : ""
    property int revision: 0                 // bumps when the set of windows changes
    property real keyboardInset: 0           // apps are resized above the on-screen keyboard

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
            revision++
        }
        w.fromRect = fromRect || centerRect
        w.fromRadius = -1
        return w
    }

    function bringToFront(w) {
        for (const key in windows)
            windows[key].z = 0
        w.z = 1
        activeWindow = w
        focusWindow = w
    }

    // Windows in Recents order, most recently used first.
    function recents() {
        const out = []
        for (const key in windows)
            out.push(windows[key])
        out.sort((a, b) => b.lastUsed - a.lastUsed)
        return out
    }

    function launch(pkg, args, fromRect) {
        const existing = windows[pkg]
        if (existing && existing === activeWindow && existing.progress > 0.5) {
            Packages.launch(pkg, args) // already in front: deliver the intent
            return
        }
        const w = windowFor(pkg, fromRect)
        bringToFront(w)
        w.open()
        Packages.launch(pkg, args)
    }

    // From a Recents card: the snapshot grows back into the app.
    function resume(pkg, cardRect, radius) {
        const w = windows[pkg]
        if (!w)
            return
        w.fromRect = cardRect
        w.fromRadius = radius
        bringToFront(w)
        w.open()
        if (!w.toplevel)
            Packages.launch(pkg, {})
    }

    function windowSettled(w) {
        // The app is full screen: whatever was below goes to the background.
        for (const key in windows)
            if (windows[key] !== w)
                windows[key].sendToBackground()
    }

    function closeActive(velocity) {
        if (!activeWindow)
            return
        const w = activeWindow
        activeWindow = null
        w.close(shell.home.iconRect(w.packageName), velocity)
    }

    // Recents: the active app shrinks into its card, then waits in the background.
    function closeActiveToCard(cardRect, radius, vy) {
        if (!activeWindow)
            return
        const w = activeWindow
        activeWindow = null
        w.lastUsed = Date.now()
        w.closeFromGesture(cardRect, vy || 0, radius)
    }

    function stop(pkg) {
        const w = windows[pkg]
        if (w && w === activeWindow)
            closeActive(0)
        System.call("activity.stop", { package: pkg }, null)
        if (w)
            forget(w)
    }
    function stopAll() {
        for (const key in windows) {
            System.call("activity.stop", { package: key }, null)
            forget(windows[key])
        }
    }
    function forget(w) {
        if (activeWindow === w)
            activeWindow = null
        if (focusWindow === w)
            focusWindow = null
        delete windows[w.packageName]
        revision++
        w.destroy()
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
            w.closePending = false
            w.attach(toplevel, xdgSurface)
        }
        attach()
        if (!attached)
            toplevel.appIdChanged.connect(attach)
    }

    function windowClosed(w) {
        // The app process went away (quit, crashed, was stopped, or is
        // restarting, e.g. to pick up a permission). Wait a moment before
        // closing: a restarted app comes back into the same window.
        w.closePending = true
        Qt.callLater(function() { graceTimer.restart() })
    }
    Timer {
        id: graceTimer
        interval: 1500
        onTriggered: {
            for (const key in layer.windows) {
                const w = layer.windows[key]
                if (!w.closePending || w.toplevel)
                    continue
                w.closePending = false
                if (layer.activeWindow === w)
                    layer.closeActive(0)
                if (w.progress < 0.01)
                    layer.forget(w)
                else
                    Qt.callLater(function() { if (!w.toplevel && w.progress < 0.01) layer.forget(w) })
            }
        }
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
