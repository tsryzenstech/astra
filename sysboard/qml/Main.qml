// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Window
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell

// SysBoard is a Wayland compositor: apps are clients whose windows are
// composed (and animated) inside the Shell.
WaylandCompositor {
    id: server

    socketName: Host.socketName

    // The layout of the desktop's keyboard (Settings > Keyboard) for every app: they get the keymap and the raw key codes.
    Binding { target: server.defaultSeat.keymap; property: "layout"; value: Host.keyboardLayout; when: Host.desktop }
    Binding { target: server.defaultSeat.keymap; property: "variant"; value: Host.keyboardVariant; when: Host.desktop }

    WaylandOutput {
        id: output
        sizeFollowsWindow: true
        window: Window {
            id: window
            width: Host.windowSize.width
            height: Host.windowSize.height
            visibility: Host.fullscreen ? Window.FullScreen : Window.Windowed
            visible: true
            color: "black"
            title: "astraOS"

            // The desktop's pointer: an arrow over everything, at the place libinput put it (inputbridge.cpp).
            Canvas {
                id: pointer
                z: 100000
                width: 22; height: 28
                x: Host.pointerPosition.x - 1.5
                y: Host.pointerPosition.y - 1.5
                visible: Host.desktop && Host.pointerVisible
                antialiasing: true
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.beginPath()
                    c.moveTo(2, 2)
                    c.lineTo(2, 20)
                    c.lineTo(6.5, 15.8)
                    c.lineTo(9.6, 23.2)
                    c.lineTo(12.6, 22)
                    c.lineTo(9.6, 14.8)
                    c.lineTo(15.8, 14.4)
                    c.closePath()
                    c.fillStyle = "#ffffff"
                    c.strokeStyle = "#1a1a1a"
                    c.lineWidth = 1.6
                    c.lineJoin = "round"
                    c.stroke()
                    c.fill()
                }
            }

            // The shell, which opens on the lock screen, loads in the
            // background while the boot logo is up.
            Loader {
                id: shell
                anchors.fill: parent
                asynchronous: true
                sourceComponent: Host.desktop ? desktopShell : phoneShell
                onLoaded: {
                    for (const w of server.earlyToplevels)
                        item.appLayer.addToplevel(w[0], w[1])
                    server.earlyToplevels = []
                    console.info("sysboard: shell ready")
                    Host.shellLoaded()
                }
            }

            // Boot animation: the logo, breathing, then a fade to the lock
            // screen. Its animators run on the render thread, so loading the
            // shell does not make it stutter.
            Rectangle {
                id: splash
                anchors.fill: parent
                color: "black"
                opacity: shell.status === Loader.Ready ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                Image { id: natural; source: Host.bootLogo; visible: false }
                Image {
                    id: logo
                    anchors.centerIn: parent
                    // (the natural size comes from a copy of the picture without a size of its own: no binding loop)
                    readonly property real aspect: natural.implicitHeight > 0 ? natural.implicitWidth / natural.implicitHeight : 3
                    // Desktop: exactly the boot animation's logo (same size, full strength), so nothing seems to change.
                    width: Host.desktop ? Math.min(parent.width * 0.14, parent.height * 0.16 * aspect) : parent.width * 0.5
                    fillMode: Image.PreserveAspectFit
                    source: Host.bootLogo
                    opacity: Host.desktop ? 1 : 0.55
                }
                SequentialAnimation {
                    running: splash.visible && !Host.desktop
                    loops: Animation.Infinite
                    OpacityAnimator { target: logo; from: 0.55; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                    OpacityAnimator { target: logo; from: 1; to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    Component { id: phoneShell; SystemShell { compositor: server } }
    // astraOS Desktop: windows, a menu bar and a Dock (docs/DESKTOP.md).
    Component { id: desktopShell; DesktopShell { compositor: server } }

    XdgShell {
        onToplevelCreated: (toplevel, xdgSurface) => {
            if (shell.item)
                shell.item.appLayer.addToplevel(toplevel, xdgSurface)
            else
                server.earlyToplevels.push([toplevel, xdgSurface])
        }
    }
    // Windows of apps started before the shell finished loading.
    property var earlyToplevels: []

    // Text input for apps (the on-screen keyboard lives in SysBoard).
    TextInputManager {}
    QtTextInputMethodManager {}

    Component.onCompleted: Host.compositorReady(window)
}
