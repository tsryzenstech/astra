// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The Dock: the apps the user keeps there, then the ones that are running, and a tile that opens
// Activities (all the apps). A bar under an icon says the app is running. Icons grow towards the
// pointer, with the same springs as everything that moves.
Item {
    id: root

    property var shell
    property Item blurSource
    property var windowLayer                       // DesktopWindowLayer
    readonly property var pinned: {
        if (Host.installer)
            return ["com.astra.installer", "com.astra.diskutil", "org.astra.browser", "org.astra.terminal"].filter(p => Packages.get(p).package)
        const saved = Settings.values["desktop.dock"]
        const wanted = saved && saved.length ? saved
            : ["com.astra.tune", "com.astra.planet", "com.astra.settings", "com.astra.gallery", "com.astra.notes", "com.astra.weather"]
        return Packages.count >= 0 ? wanted.filter(p => Packages.get(p).package) : wanted
    }
    // Running apps that are not pinned.
    readonly property var running: {
        const rev = windowLayer ? windowLayer.revision : 0
        const out = []
        for (const key in (windowLayer ? windowLayer.windows : ({})))
            if (pinned.indexOf(key) < 0 && Packages.get(key).package && !windowLayer.windows[key].doomed)
                out.push(key)
        return out
    }
    readonly property real iconSize: 52
    readonly property real iconGap: 14
    property real pointer: -1000               // x of the pointer in the Dock, -1000: away

    readonly property int slots: pinned.length + running.length + 1
    implicitWidth: slots * (iconSize + iconGap) + iconGap
    implicitHeight: iconSize + 26
    width: implicitWidth
    height: implicitHeight

    // Where the icon of a package is, for the windows that shrink into it.
    function pointOf(pkg) {
        for (let i = 0; i < icons.count; ++i) {
            const it = icons.itemAt(i)
            if (it && it.pkg === pkg) {
                const p = it.mapToItem(windowLayer, it.width / 2, it.height / 2)
                return p
            }
        }
        return Qt.point(width / 2, height)
    }
    function publish() {
        if (!windowLayer)
            return
        const points = {}
        for (let i = 0; i < icons.count; ++i) {
            const it = icons.itemAt(i)
            if (it)
                points[it.pkg] = it.mapToItem(windowLayer, it.width / 2, it.height / 2)
        }
        windowLayer.dockPoints = points
        for (const key in windowLayer.windows)
            if (points[key])
                windowLayer.windows[key].dockPoint = points[key]
    }
    onWidthChanged: Qt.callLater(publish)
    Connections { target: root.windowLayer; function onRevisionChanged() { Qt.callLater(root.publish) } }

    Glass {
        id: bar
        anchors.fill: parent
        source: root.blurSource
        radius: 30
        tint: Theme.light ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0.1, 0.1, 0.12, 0.45)
        clickable: false
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: (m) => root.pointer = m.x
        onExited: root.pointer = -1000
    }

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        spacing: root.iconGap

        Repeater {
            id: icons
            model: root.pinned.concat(root.running)
            delegate: Item {
                id: slot
                required property string modelData
                required property int index
                readonly property string pkg: modelData
                readonly property var info: Packages.count >= 0 ? Packages.get(pkg) : ({})
                readonly property var window: root.windowLayer && root.windowLayer.revision >= 0 ? root.windowLayer.windows[pkg] : null
                readonly property bool isRunning: !!window && !window.doomed
                width: root.iconSize
                height: root.iconSize

                // Magnification: nearest to the pointer grows most.
                readonly property real centreX: x + width / 2 + row.x
                readonly property real lift: Math.max(0, 1 - Math.abs(root.pointer - centreX) / 110)
                Spring { id: grow; to: slot.lift; response: 0.28; dampingFraction: 0.8 }

                Item {
                    id: iconBox
                    width: root.iconSize
                    height: root.iconSize
                    transformOrigin: Item.Bottom
                    scale: 1 + 0.32 * grow.value - (tap.pressed ? 0.08 : 0)
                    y: -10 * grow.value
                    AppIcon {
                        size: root.iconSize
                        source: slot.info.iconUrl || ""
                    }
                    // Bounces while the app starts.
                    SequentialAnimation on y {
                        id: bounce
                        running: false
                        NumberAnimation { to: -18; duration: 180; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 0; duration: 220; easing.type: Easing.OutBounce }
                    }
                }
                Rectangle {
                    visible: slot.isRunning
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.iconSize + 6
                    width: slot.window && slot.window.focused && !slot.window.minimized ? 16 : 5
                    height: 4
                    radius: 2
                    color: "white"
                    opacity: slot.window && slot.window.minimized ? 0.45 : 0.95
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                TapHandler {
                    id: tap
                    onTapped: {
                        if (!slot.isRunning)
                            bounce.restart()
                        root.shell.dockActivate(slot.pkg)
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.shell.dockMenu(slot.pkg, slot.mapToItem(root.shell, slot.width / 2, 0))
                }
                // The name, above the icon, while the pointer is on it.
                HoverHandler { id: hover }
                Rectangle {
                    visible: hover.hovered
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -44 - 10 * grow.value
                    width: label.implicitWidth + 22
                    height: 28
                    radius: 14
                    color: Qt.rgba(0, 0, 0, 0.7)
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: slot.info.name || slot.pkg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: "white"
                    }
                }
            }
        }

        // Activities: the tile with the first apps, as in the design.
        Item {
            width: root.iconSize
            height: root.iconSize
            Rectangle {
                anchors.fill: parent
                radius: root.iconSize * Theme.iconRadiusRatio
                color: Qt.rgba(1, 1, 1, 0.88)
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: Math.min(4, root.pinned.length)
                        AppIcon { required property int index; size: 18; source: Packages.get(root.pinned[index]).iconUrl || "" }
                    }
                }
            }
            TapHandler { onTapped: root.shell.openActivities() }
        }
    }
}
