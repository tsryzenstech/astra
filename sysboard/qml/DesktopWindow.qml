// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Astra.Core
import QtWayland.Compositor
import Astra.Controls
import Astra.Animation

// One app window on astraOS Desktop (docs/DESKTOP.md).
//
// Desktop apps ("target": "desktop") get a window the user moves and resizes. Mobile apps run in a
// window with a phone's aspect ratio that does not resize: SysBoard draws the phone's status bar over
// the top of it, so the app lays itself out as on the phone. Both open and close with the same springs
// as on the phone and minimise towards their Dock icon.
//
// The window frame is x, y, width, height of this item; the title strip (the grip) is on top of the app.
Item {
    id: win

    property string packageName
    property var info: ({})
    property var host                    // DesktopWindowLayer
    property var toplevel: null
    property var xdgSurface: null
    readonly property bool hasSurface: surfaceItem.surface !== null && surfaceItem.surface.hasContent
    property bool closePending: false
    property bool doomed: false
    property double lastUsed: 0
    property bool minimized: false
    property bool maximized: false
    readonly property bool focused: host.activeWindow === win
    readonly property bool phone: (info.target || "mobile") !== "desktop"
    readonly property bool resizable: !phone && !maximized
    readonly property string title: toplevel && toplevel.title ? toplevel.title : (info.name || packageName)
    // A Linux program of the system: its window is a plain one, sized by the program.
    readonly property bool legacy: !!(info.legacy && info.legacy.appId)

    readonly property real titleHeight: 30
    readonly property real frameRadius: maximized ? 0 : 26
    readonly property var hints: info.desktop || ({})
    readonly property real minWidth: Math.max(320, hints.minWidth || 480)
    readonly property real minHeight: Math.max(240, hints.minHeight || 320)

    // A phone window is as big as a phone, or smaller when the screen is.
    readonly property real phoneBase: 393
    readonly property real phoneHeight: 852
    readonly property real phoneScale: phone ? Math.min(1, (host.workArea.height - 24 - titleHeight) / phoneHeight,
                                                         (host.workArea.width - 24) / phoneBase) : 1
    // Size of the app's surface in shell pixels (before the phone scale).
    readonly property real surfaceWidth: phone ? phoneBase : width
    readonly property real surfaceHeight: phone ? phoneHeight : height - titleHeight

    // The geometry before maximising.
    property rect restored: Qt.rect(0, 0, 0, 0)
    // Where the Dock icon is: the window shrinks into it when it is minimised.
    property point dockPoint: Qt.point(host.width / 2, host.height)

    // 0 = gone (minimised, closed), 1 = in place
    Spring { id: presence; to: 0; response: 0.34; dampingFraction: 0.82 }
    readonly property real shown: presence.value
    visible: shown > 0.003 || presence.running
    opacity: Math.min(1, Math.max(0, shown * 1.6))
    transform: [
        Scale {
            origin.x: win.width / 2
            origin.y: win.height / 2
            xScale: win.minimized ? 0.35 + 0.65 * win.shown : 0.9 + 0.1 * win.shown
            yScale: xScale
        },
        Translate {
            x: win.minimized ? (win.dockPoint.x - win.x - win.width / 2) * (1 - win.shown) : 0
            y: win.minimized ? (win.dockPoint.y - win.y - win.height / 2) * (1 - win.shown) : (1 - win.shown) * 14
        }
    ]

    function open() {
        minimized = false
        lastUsed = Date.now()
        presence.animateTo(1, 0)
    }
    function minimize() {
        minimized = true
        presence.animateTo(0, 0)
        host.windowMinimized(win)
    }
    function closeAnimated() {
        presence.animateTo(0, 0)
    }
    function toggleMaximized() {
        if (!resizable && !maximized)
            return
        if (maximized) {
            maximized = false
            x = restored.x; y = restored.y; width = restored.width; height = restored.height
        } else {
            restored = Qt.rect(x, y, width, height)
            maximized = true
            const a = host.workArea
            x = a.x; y = a.y; width = a.width; height = a.height
        }
        resize()
    }

    function attach(toplevel, xdgSurface) {
        win.toplevel = toplevel
        win.xdgSurface = xdgSurface
        resize()
    }
    // The app's size is in the surface's units, which are the panel's pixels (the app scales itself
    // with QT_SCALE_FACTOR, as on the phone).
    function resize() {
        if (!toplevel)
            return
        const size = Qt.size(Math.round(surfaceWidth * Screen.devicePixelRatio), Math.round(surfaceHeight * Screen.devicePixelRatio))
        // A window of its own size, not fullscreen: the app takes the size we send (a phone window's is fixed).
        toplevel.sendConfigure(size, win.focused ? [XdgToplevel.ActivatedState] : [])
    }
    onWidthChanged: if (!phone) resizeTimer.restart()
    onHeightChanged: if (!phone) resizeTimer.restart()
    Timer { id: resizeTimer; interval: 16; onTriggered: win.resize() }
    onFocusedChanged: {
        if (toplevel && !phone)
            resize()
        if (focused && surfaceItem.surface)
            surfaceItem.takeFocus()
    }

    // Everything the user sees of the window is in `frame`, so shadow, mask and focus ring share it.
    Item {
        id: frame
        anchors.fill: parent

        // The shadow: layers of a rounded rectangle, each a little larger and fainter (cheap: no blur effect on
        // a surface that changes every frame). Stronger and lower for the window in front.
        Repeater {
            model: win.maximized ? 0 : 7
            delegate: Rectangle {
                required property int index
                readonly property real grow: 2 + index * (win.focused ? 4.2 : 2.6)
                x: -grow
                y: -grow + (win.focused ? 14 : 6) * (0.4 + index / 7)
                width: parent.width + 2 * grow
                height: parent.height + 2 * grow
                radius: win.frameRadius + grow
                color: "black"
                opacity: (win.focused ? 0.075 : 0.05) * (1 - index / 8)
            }
        }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: win.frameRadius
            color: win.phone || (win.info.background || "#000000") !== "#000000"
                   ? (win.info.background || "#000000") : (Theme.light && win.info.appearance !== "dark" ? Theme.background : "#141416")
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, win.focused ? 0.1 : 0.06)
            antialiasing: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                autoPaddingEnabled: false
            }

            // Splash until the first frame.
            AppIcon {
                anchors.centerIn: parent
                size: 84
                source: win.info.iconUrl || ""
                opacity: win.hasSurface ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // The app. A phone window shows the app at the phone's size, scaled to fit the screen.
            Item {
                id: area
                x: win.phone ? (win.width - win.phoneBase * win.phoneScale) / 2 : 0
                y: win.titleHeight
                width: win.phone ? win.phoneBase : win.width
                height: win.phone ? win.phoneHeight : win.height - win.titleHeight
                transformOrigin: Item.TopLeft
                scale: win.phone ? win.phoneScale : 1

                ShellSurfaceItem {
                    id: surfaceItem
                    shellSurface: win.xdgSurface
                    autoCreatePopupItems: true
                    inputEventsEnabled: win.shown > 0.9
                    opacity: win.hasSurface ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    onSurfaceDestroyed: {
                        win.xdgSurface = null
                        win.toplevel = null
                        win.host.windowClosed(win)
                    }
                    // A click anywhere in the window raises it.
                    TapHandler { acceptedButtons: Qt.LeftButton | Qt.RightButton; gesturePolicy: TapHandler.ReleaseWithinBounds
                                 onPressedChanged: if (pressed) win.host.bringToFront(win) }
                }
                // The phone's status bar, over the app (apps leave room for it at the top).
                StatusBar {
                    visible: win.phone
                    width: win.phoneBase
                    tint: Theme.light && win.info.appearance !== "dark" ? "#0B0B0F" : "white"
                    enabled: false
                }
            }

            // The strip on top: the grip to move the window with, and its buttons.
            Item {
                id: strip
                width: parent.width
                height: win.titleHeight

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    hoverEnabled: true
                    property point origin
                    property point startPos
                    onPressed: (m) => {
                        win.host.bringToFront(win)
                        origin = mapToItem(win.host, m.x, m.y)
                        startPos = Qt.point(win.x, win.y)
                    }
                    onPositionChanged: (m) => {
                        if (!pressed)
                            return
                        const p = mapToItem(win.host, m.x, m.y)
                        if (win.maximized && Math.hypot(p.x - origin.x, p.y - origin.y) > 8) {
                            // Pulled out of the maximised state: it comes back under the pointer.
                            const ratio = (origin.x - win.x) / Math.max(1, win.width)
                            win.maximized = false
                            win.width = win.restored.width
                            win.height = win.restored.height
                            startPos = Qt.point(origin.x - ratio * win.width, win.y)
                            win.resize()
                        }
                        if (!win.maximized)
                            win.host.moveWindow(win, startPos.x + p.x - origin.x, startPos.y + p.y - origin.y)
                    }
                    onDoubleClicked: win.toggleMaximized()
                }

                // At rest: a grip (the pill on top of the window). Hovered: the window's buttons.
                Rectangle {
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 5
                    radius: 2.5
                    color: win.phone || Theme.dark || win.info.appearance === "dark" ? "white" : "black"
                    opacity: (win.focused ? 0.5 : 0.22) * (1 - buttons.opacity)
                }
                Row {
                    id: buttons
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    opacity: drag.containsMouse || closeDot.hovered || minDot.hovered || maxDot.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    component Dot: Rectangle {
                        id: dot
                        property color tint
                        property string glyph
                        readonly property bool hovered: ma.containsMouse
                        signal activated()
                        width: 14; height: 14; radius: 7
                        color: tint
                        scale: ma.pressed ? 0.86 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        Text {
                            anchors.centerIn: parent
                            text: dot.glyph
                            visible: buttons.opacity > 0.5
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Qt.rgba(0, 0, 0, 0.55)
                        }
                        MouseArea { id: ma; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; onClicked: dot.activated() }
                    }
                    Dot { id: closeDot; tint: "#FF5F57"; glyph: "×"; onActivated: win.host.closeWindow(win) }
                    Dot { id: minDot; tint: "#FEBC2E"; glyph: "–"; onActivated: win.minimize() }
                    Dot { id: maxDot; tint: win.resizable || win.maximized ? "#28C840" : Qt.rgba(1, 1, 1, 0.25); glyph: "+"; onActivated: win.toggleMaximized() }
                }
            }
        }
    }
    Rectangle {
        id: maskShape
        anchors.fill: parent
        radius: win.frameRadius
        visible: false
        layer.enabled: true
    }

    // Resizing: the edges and corners of a desktop window.
    component Edge: MouseArea {
        id: edge
        property int dx: 0     // -1: left edge, 1: right edge
        property int dy: 0     // -1: top edge, 1: bottom edge
        enabled: win.resizable
        hoverEnabled: true
        preventStealing: true
        cursorShape: dx !== 0 && dy !== 0 ? (dx === dy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                     : dx !== 0 ? Qt.SizeHorCursor : Qt.SizeVerCursor
        property point origin
        property rect startGeometry
        onPressed: (m) => {
            win.host.bringToFront(win)
            origin = mapToItem(win.host, m.x, m.y)
            startGeometry = Qt.rect(win.x, win.y, win.width, win.height)
        }
        onPositionChanged: (m) => {
            if (!pressed)
                return
            const p = mapToItem(win.host, m.x, m.y)
            const ddx = p.x - origin.x, ddy = p.y - origin.y
            let nx = startGeometry.x, ny = startGeometry.y, nw = startGeometry.width, nh = startGeometry.height
            if (dx > 0) nw = Math.max(win.minWidth, startGeometry.width + ddx)
            if (dx < 0) { nw = Math.max(win.minWidth, startGeometry.width - ddx); nx = startGeometry.x + startGeometry.width - nw }
            if (dy > 0) nh = Math.max(win.minHeight, startGeometry.height + ddy)
            if (dy < 0) { nh = Math.max(win.minHeight, startGeometry.height - ddy); ny = startGeometry.y + startGeometry.height - nh }
            win.x = nx; win.y = Math.max(win.host.workArea.y, ny); win.width = nw; win.height = nh
        }
    }
    Edge { dx: -1; x: -4; y: 12; width: 10; height: parent.height - 24 }
    Edge { dx: 1; x: parent.width - 6; y: 12; width: 10; height: parent.height - 24 }
    Edge { dy: 1; x: 12; y: parent.height - 6; width: parent.width - 24; height: 10 }
    Edge { dy: -1; x: 12; y: -4; width: parent.width - 24; height: 8 }
    Edge { dx: -1; dy: 1; x: -4; y: parent.height - 12; width: 18; height: 18 }
    Edge { dx: 1; dy: 1; x: parent.width - 14; y: parent.height - 12; width: 18; height: 18 }
    Edge { dx: -1; dy: -1; x: -4; y: -4; width: 16; height: 16 }
    Edge { dx: 1; dy: -1; x: parent.width - 12; y: -4; width: 16; height: 16 }
}
