// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Window
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell

// SysBoard is a Wayland compositor: apps are clients whose windows are
// composed (and animated) inside the Shell.
WaylandCompositor {
    id: compositor

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

            // The shell loads in the background while the boot logo is up.
            Loader {
                id: shell
                anchors.fill: parent
                asynchronous: true
                sourceComponent: SystemShell { compositor: compositor }
                onLoaded: {
                    for (const w of compositor.earlyToplevels)
                        item.appLayer.addToplevel(w[0], w[1])
                    compositor.earlyToplevels = []
                }
            }

            // The boot logo (as in /system/media/bootanimation/desc.txt: centered,
            // half the screen wide, on black) until the shell is ready.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: shell.status === Loader.Ready ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.5
                    fillMode: Image.PreserveAspectFit
                    source: Host.bootLogo
                }
            }
        }
    }

    XdgShell {
        onToplevelCreated: (toplevel, xdgSurface) => {
            if (shell.item)
                shell.item.appLayer.addToplevel(toplevel, xdgSurface)
            else
                compositor.earlyToplevels.push([toplevel, xdgSurface])
        }
    }
    // Windows of apps started before the shell finished loading.
    property var earlyToplevels: []

    // Text input for apps (the on-screen keyboard lives in SysBoard).
    TextInputManager {}
    QtTextInputMethodManager {}

    Component.onCompleted: Host.compositorReady(window)
}
