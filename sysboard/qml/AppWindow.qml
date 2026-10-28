// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtWayland.Compositor
import Astra.Controls
import Astra.Animation

// One app window. The frame morphs between a rectangle on screen (the
// launcher icon, or a Recents card) and the full screen. The icon on the
// home screen is hidden meanwhile, so it is the icon itself that grows into
// the app. Corners stay round for the whole morph and only square off, with
// a short spring, once the app has settled full screen.
Item {
    id: win

    property string packageName
    property var info: ({})
    property var host // the AppLayer
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    property real fromRadius: -1   // corner radius at fromRect; -1: an app icon's

    property var toplevel: null
    property var xdgSurface: null
    readonly property bool hasSurface: surfaceItem.surface !== null && surfaceItem.surface.hasContent
    property bool inBackground: false
    property url snapshot: ""       // last frame, for Recents
    property double lastUsed: 0

    // 0 = at fromRect, 1 = fullscreen
    Spring { id: openness; to: 0; response: 0.46; dampingFraction: 0.84 }
    readonly property real progress: openness.value
    readonly property bool settledOpen: progress > 0.999 && !openness.running && !gesturing
    readonly property bool morphing: !inBackground && progress > 0.002 && !settledOpen

    // Corner radius of the full screen frame (squares off once settled).
    Spring { id: corner; to: Theme.screenRadius; response: 0.3; dampingFraction: 1.0 }
    onSettledOpenChanged: {
        if (settledOpen) {
            corner.animateTo(0, 0)
            host.windowSettled(win)
        } else if (!inBackground) {
            corner.animateTo(Theme.screenRadius, 0)
        }
    }

    // Close gesture: finger offset (dx, dy) shrinks and moves the window.
    property bool gesturing: false
    Spring { id: gx; to: 0; response: 0.35; dampingFraction: 0.85 }
    Spring { id: gy; to: 0; response: 0.35; dampingFraction: 0.85 }
    readonly property real gestureX: gx.value
    readonly property real gestureY: gy.value
    readonly property real gestureScale: 1 - Math.min(0.62, Math.max(0, gy.value) / height * 1.1)
    // How much of the screen the app covers (drives the home screen fade).
    readonly property real presence: inBackground ? 0 : progress * (0.35 + 0.65 * (gestureScale - 0.38) / 0.62)

    anchors.fill: parent
    visible: !inBackground && progress > 0.002

    function open() {
        inBackground = false
        lastUsed = Date.now()
        gx.snap(0)
        gy.snap(0)
        useFrozen = false
        corner.snap(Theme.screenRadius)
        openness.animateTo(1, 0)
    }
    function close(targetRect, velocity, radius) {
        fromRect = targetRect || host.centerRect
        fromRadius = radius === undefined ? -1 : radius
        capture()
        openness.animateTo(0, velocity ? -Math.abs(velocity) / height : 0)
    }
    // Hidden behind another app or in Recents; the process keeps running.
    function sendToBackground() {
        if (inBackground)
            return
        capture()
        inBackground = true
        openness.snap(0)
        gesturing = false
        gx.snap(0)
        gy.snap(0)
    }
    function attach(toplevel, xdgSurface) {
        win.toplevel = toplevel
        win.xdgSurface = xdgSurface
        toplevel.sendFullscreen(Qt.size(win.width, win.height))
    }
    // Remembers the current frame for Recents.
    function capture() {
        if (!win.visible || !win.hasSurface)
            return
        content.grabToImage(function(result) { win.snapshot = result.url }, Qt.size(win.width / 2, win.height / 2))
    }

    function beginGesture() {
        gesturing = true
        capture()
    }
    function updateGesture(dx, dy) {
        gx.value = dx
        gy.value = Math.max(0, dy)
    }
    function gestureShouldClose(vy) { return gy.value > height * 0.12 || vy > 650 }
    function cancelGesture(vy) {
        gesturing = false
        gx.animateTo(0, 0)
        gy.animateTo(0, -vy)
    }
    function closeFromGesture(targetRect, vy, radius) {
        // Freeze the shrunken window as the new "open" geometry, then morph
        // it into the target from there, keeping the finger's momentum.
        frozen = Qt.rect(gestureRect.x, gestureRect.y, gestureRect.width, gestureRect.height)
        frozenRadius = Theme.screenRadius * gestureScale
        gesturing = false
        gx.snap(0)
        gy.snap(0)
        useFrozen = true
        close(targetRect, vy, radius)
    }

    property bool useFrozen: false
    property rect frozen
    property real frozenRadius: Theme.screenRadius
    readonly property rect gestureRect: {
        const s = gestureScale
        const w = width * s, h = height * s
        return Qt.rect(width / 2 - w / 2 + gx.value * 0.6, height / 2 - h / 2 - gy.value * 0.35, w, h)
    }
    readonly property rect openRect: useFrozen ? frozen : gestureRect
    readonly property real openRadius: useFrozen ? frozenRadius
                                                 : gesturing ? Theme.screenRadius * Math.max(0.6, gestureScale) : corner.value

    function lerp(a, b, t) { return a + (b - a) * t }

    Item {
        id: frame
        readonly property real p: Math.max(0, win.progress)
        x: win.lerp(win.fromRect.x, win.openRect.x, p)
        y: win.lerp(win.fromRect.y, win.openRect.y, p)
        width: Math.max(1, win.lerp(win.fromRect.width, win.openRect.width, p))
        height: Math.max(1, win.lerp(win.fromRect.height, win.openRect.height, p))
        readonly property real startRadius: win.fromRadius >= 0 ? win.fromRadius : win.fromRect.width * Theme.iconRadiusRatio
        readonly property real radius: Math.min(width / 2, win.lerp(startRadius, win.openRadius, Math.min(1, p)))
        readonly property bool rounded: radius > 0.5

        layer.enabled: rounded
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskShape
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Item {
            id: content
            width: win.width
            height: win.height
            anchors.centerIn: parent
            scale: frame.width / win.width

            // Splash shown until the app draws its first frame.
            Rectangle {
                anchors.fill: parent
                color: win.info.background || "#000000"
                AppIcon {
                    anchors.centerIn: parent
                    size: 96
                    source: win.info.iconUrl || ""
                    opacity: win.hasSurface ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            ShellSurfaceItem {
                id: surfaceItem
                shellSurface: win.xdgSurface
                autoCreatePopupItems: true
                inputEventsEnabled: win.settledOpen
                opacity: win.hasSurface ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                onSurfaceDestroyed: {
                    win.xdgSurface = null
                    win.toplevel = null
                    win.host.windowClosed(win)
                }
            }
        }

        // The icon artwork, filling the frame while it is still icon sized,
        // cross-fades into the app content. Opening from Recents starts
        // from the snapshot instead (fromRadius >= 0), so no artwork there.
        AppIcon {
            anchors.fill: parent
            size: parent.width
            source: win.info.iconUrl || ""
            visible: win.fromRadius < 0 && opacity > 0
            opacity: 1 - Math.min(1, Math.max(0, frame.p / 0.38))
        }
    }

    Rectangle {
        id: maskShape
        x: frame.x
        y: frame.y
        width: frame.width
        height: frame.height
        radius: frame.radius
        visible: false
        layer.enabled: frame.rounded
    }

    onProgressChanged: {
        if (progress > 0.98 && surfaceItem.surface && !surfaceItem.activeFocus)
            surfaceItem.takeFocus()
    }
}
