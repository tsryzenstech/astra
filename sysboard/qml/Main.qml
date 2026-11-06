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

            // The shell, which opens on the lock screen, loads in the
            // background while the boot logo is up.
            Loader {
                id: shell
                anchors.fill: parent
                asynchronous: true
                sourceComponent: SystemShell { compositor: server }
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

                Image {
                    id: logo
                    anchors.centerIn: parent
                    width: parent.width * 0.5
                    fillMode: Image.PreserveAspectFit
                    source: Host.bootLogo
                    opacity: 0.55
                }
                SequentialAnimation {
                    running: splash.visible
                    loops: Animation.Infinite
                    OpacityAnimator { target: logo; from: 0.55; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                    OpacityAnimator { target: logo; from: 1; to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                }
            }
        }
    }

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
