// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtWayland.Compositor
import Astra.Controls
import Astra.Animation

// One app window. The frame morphs between the launcher icon and the full
// screen; the app content is scaled inside it and cross-fades with the icon,
// so opening an app looks like the icon itself growing into the app.
Item {
    id: win

    property string packageName
    property var info: ({})
    property var host // the AppLayer
    property rect fromRect: Qt.rect(0, 0, 0, 0)

    property var toplevel: null
    property var xdgSurface: null
    readonly property bool hasSurface: surfaceItem.surface !== null && surfaceItem.surface.hasContent

    // 0 = icon, 1 = fullscreen
    Spring { id: openness; to: 0; response: 0.44; dampingFraction: 0.86 }
    readonly property real progress: openness.value

    // Close gesture: finger offset (dx, dy) shrinks and moves the window.
    property bool gesturing: false
    Spring { id: gx; to: 0; response: 0.35; dampingFraction: 0.85 }
    Spring { id: gy; to: 0; response: 0.35; dampingFraction: 0.85 }
    readonly property real gestureScale: 1 - Math.min(0.62, Math.max(0, gy.value) / height * 1.1)
    // How much of the screen the app covers (drives the home screen fade).
    readonly property real presence: progress * (0.35 + 0.65 * (gestureScale - 0.38) / 0.62)

    anchors.fill: parent
    visible: progress > 0.002

    function open() {
        gx.snap(0)
        gy.snap(0)
        openness.animateTo(1, 0)
    }
    function close(targetRect, velocity) {
        fromRect = targetRect || host.centerRect
        openness.animateTo(0, velocity ? -Math.abs(velocity) / height : 0)
    }
    function attach(toplevel, xdgSurface) {
        win.toplevel = toplevel
        win.xdgSurface = xdgSurface
        toplevel.sendFullscreen(Qt.size(win.width, win.height))
    }

    function beginGesture() { gesturing = true }
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
    function closeFromGesture(targetRect, vy) {
        // Freeze the shrunken window as the new "open" geometry, then morph
        // it into the icon from there, keeping the finger's momentum.
        frozen = Qt.rect(gestureRect.x, gestureRect.y, gestureRect.width, gestureRect.height)
        gesturing = false
        gx.snap(0)
        gy.snap(0)
        useFrozen = true
        close(targetRect, vy)
    }

    property bool useFrozen: false
    property rect frozen
    readonly property rect gestureRect: {
        const s = gestureScale
        const w = width * s, h = height * s
        return Qt.rect(width / 2 - w / 2 + gx.value * 0.6, height / 2 - h / 2 - gy.value * 0.35, w, h)
    }
    readonly property rect openRect: useFrozen ? frozen : gestureRect
    Connections {
        target: openness
        function onSettled() { if (openness.value >= 1) win.useFrozen = false }
    }

    function lerp(a, b, t) { return a + (b - a) * t }

    Item {
        id: frame
        readonly property real p: Math.max(0, win.progress)
        x: win.lerp(win.fromRect.x, win.openRect.x, p)
        y: win.lerp(win.fromRect.y, win.openRect.y, p)
        width: Math.max(1, win.lerp(win.fromRect.width, win.openRect.width, p))
        height: Math.max(1, win.lerp(win.fromRect.height, win.openRect.height, p))
        readonly property real radius: win.lerp(win.fromRect.width * Theme.iconRadiusRatio,
                                                win.openRect.width < win.width - 1 ? 38 * win.gestureScale : 0, p)
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
                inputEventsEnabled: win.progress > 0.98 && !win.gesturing
                opacity: win.hasSurface ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                onSurfaceDestroyed: {
                    win.xdgSurface = null
                    win.toplevel = null
                    win.host.windowClosed(win)
                }
            }
        }

        // The launcher icon fades into the app during the first part of the morph.
        AppIcon {
            anchors.fill: parent
            size: parent.width
            source: win.info.iconUrl || ""
            opacity: 1 - Math.min(1, Math.max(0, frame.p / 0.38))
            visible: opacity > 0
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
