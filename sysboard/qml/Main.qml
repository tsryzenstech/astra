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

            SystemShell {
                id: shell
                anchors.fill: parent
                compositor: compositor
            }
        }
    }

    XdgShell {
        onToplevelCreated: (toplevel, xdgSurface) => shell.appLayer.addToplevel(toplevel, xdgSurface)
    }

    // Text input for apps (the on-screen keyboard lives in SysBoard).
    TextInputManager {}
    QtTextInputMethodManager {}

    Component.onCompleted: Host.compositorReady(window)
}
