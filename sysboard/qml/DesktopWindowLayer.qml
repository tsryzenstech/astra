// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core

// The windows of astraOS Desktop: one DesktopWindow per package (as AppLayer on the phone), in a stacking
// order the user changes by clicking, with the same interface towards SysBoard's Main.qml
// (addToplevel) and the shell (launch, activeWindow, windows, stop).
Item {
    id: layer

    property var shell
    property var windows: ({})
    property DesktopWindow activeWindow: null
    property int revision: 0                 // bumps when the set of windows changes
    property int stack: 0
    // Where windows live: under the menu bar, above the Dock.
    property rect workArea: Qt.rect(0, 40, width, height - 40 - 96)
    // The Dock tells where each icon is (package -> point in layer coordinates).
    property var dockPoints: ({})
    signal windowMinimized(var window)

    Component {
        id: windowComponent
        DesktopWindow {}
    }

    function windowFor(pkg) {
        let w = windows[pkg]
        if (!w) {
            let info = Packages.get(pkg)
            // A Linux program that is not listed as an app: a plain resizable window.
            if (!info.package)
                info = { package: pkg, name: pkg, target: "desktop", background: "#141416", iconUrl: "", legacy: { appId: pkg } }
            w = windowComponent.createObject(layer, { packageName: pkg, info: info, host: layer })
            place(w)
            windows[pkg] = w
            revision++
        }
        w.dockPoint = dockPoints[pkg] || Qt.point(width / 2, height)
        return w
    }

    // First placement: the size the app asks for (app.json "desktop"), cascaded.
    function place(w) {
        const a = workArea
        if (w.phone) {
            w.width = w.phoneBase * w.phoneScale
            w.height = w.phoneHeight * w.phoneScale + w.titleHeight
        } else {
            const h = w.hints
            w.width = Math.min(a.width - 40, h.width || 960)
            w.height = Math.min(a.height - 24, h.height || 640)
        }
        const n = Object.keys(windows).length
        const free = Qt.point(a.width - w.width, a.height - w.height)
        w.x = a.x + Math.max(12, free.x / 2) + ((n * 34) % 170) - 60
        w.y = a.y + Math.max(8, free.y / 2) + ((n * 28) % 120) - 30
        keepOnScreen(w)
    }

    function keepOnScreen(w) {
        const a = workArea
        w.x = Math.max(-w.width + 80, Math.min(a.x + a.width - 80, w.x))
        w.y = Math.max(a.y, Math.min(a.y + a.height - 40, w.y))
    }
    function moveWindow(w, x, y) {
        w.x = x
        w.y = y
        keepOnScreen(w)
    }

    function bringToFront(w) {
        if (!w)
            return
        w.z = ++stack
        w.lastUsed = Date.now()
        activeWindow = w
    }

    function launch(pkg, args, fromRect) {
        const w = windowFor(pkg)
        bringToFront(w)
        w.open()
        Packages.launch(pkg, args || {})
    }

    // The Dock icon of a running app was clicked.
    function toggle(pkg) {
        const w = windows[pkg]
        if (!w) {
            launch(pkg, {}, null)
        } else if (w.minimized) {
            bringToFront(w)
            w.open()
        } else if (activeWindow === w) {
            w.minimize()
        } else {
            bringToFront(w)
        }
    }

    function windowMinimizedHandler(w) {
        if (activeWindow === w) {
            // The next window in front takes the focus.
            let next = null
            for (const key in windows) {
                const c = windows[key]
                if (c !== w && !c.minimized && (!next || c.z > next.z))
                    next = c
            }
            activeWindow = next
        }
    }
    onWindowMinimized: (w) => windowMinimizedHandler(w)

    // Windows in the order of use (Activities).
    function recents() {
        const out = []
        for (const key in windows)
            out.push(windows[key])
        out.sort((a, b) => b.lastUsed - a.lastUsed)
        return out
    }

    // The close button of a window: the app is stopped, the window shrinks away.
    function closeWindow(w) {
        System.call("activity.stop", { package: w.packageName }, null)
        w.doomed = true
        w.closeAnimated()
        sweepTimer.start()
    }
    function stop(pkg) {
        const w = windows[pkg]
        if (w)
            closeWindow(w)
        else
            System.call("activity.stop", { package: pkg }, null)
    }
    function stopAll() {
        for (const key in windows)
            closeWindow(windows[key])
    }
    function forget(w) {
        if (activeWindow === w) {
            activeWindow = null
            let next = null
            for (const key in windows) {
                const c = windows[key]
                if (c !== w && !c.minimized && !c.doomed && (!next || c.z > next.z))
                    next = c
            }
            if (next)
                bringToFront(next)
        }
        delete windows[w.packageName]
        revision++
        w.destroy()
    }

    // The package of a window: its app_id is the package name for an astra app; a Linux program listed as an app
    // (/Applications/<Name>.legacy.json) says its app_id there.
    function packageForAppId(appId) {
        if (Packages.get(appId).package)
            return appId
        const wanted = appId.toLowerCase()
        const entry = Packages.list().find(p => p.legacy && p.legacy.appId && p.legacy.appId.toLowerCase() === wanted)
        return entry ? entry.package : appId
    }

    // Wayland: a new toplevel. Its app_id (the package name) can arrive after creation.
    function addToplevel(toplevel, xdgSurface) {
        let attached = false
        const attach = () => {
            if (attached || !toplevel.appId)
                return
            attached = true
            console.info("window:", toplevel.appId, "title:", toplevel.title)
            const pkg = packageForAppId(toplevel.appId)
            let w = windows[pkg]
            if (!w) {
                // Started without the Dock (a notification, another app): it opens in place.
                w = windowFor(pkg)
                bringToFront(w)
                w.open()
            }
            w.closePending = false
            w.doomed = false
            w.attach(toplevel, xdgSurface)
        }
        attach()
        if (!attached)
            toplevel.appIdChanged.connect(attach)
    }

    function windowClosed(w) {
        // The process ended (quit, crashed, stopped, or restarting to pick up a permission): a short
        // grace period, since a restarted app comes back into the same window.
        w.closePending = true
        graceTimer.restart()
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
                w.doomed = true
                w.closeAnimated()
            }
            sweepTimer.start()
        }
    }
    // Windows of apps that went away leave once their closing animation ends.
    Timer {
        id: sweepTimer
        interval: 250
        repeat: true
        onTriggered: {
            let pending = false
            for (const key in layer.windows) {
                const w = layer.windows[key]
                if (!w.doomed || w.toplevel)
                    continue
                if (w.shown < 0.01)
                    layer.forget(w)
                else
                    pending = true
            }
            if (!pending)
                stop()
        }
    }
}
