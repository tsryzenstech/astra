// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The Dock: the apps the user keeps there, then the ones that are running, and a tile that opens
// Activities (all the apps). A bar under an icon says the app is running.
//
// As on a Mac the icons swell under the pointer and push their neighbours aside, with a smooth bell (not a step), and
// the Dock widens by what they take. Drag an icon sideways to put it in another place, drag it up and out of the Dock to
// remove it; apps are added from Activities (right click: Keep in Dock, or drag an app onto the Dock). The order is saved
// in `desktop.dock`.
Item {
    id: root

    property var shell
    property Item blurSource
    property var windowLayer                       // DesktopWindowLayer
    readonly property var pinned: {
        if (Host.installer)
            return ["com.astra.installer", "com.astra.diskutil", "org.astra.browser", "com.astra.terminal"].filter(p => Packages.get(p).package)
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
    readonly property real swell: 0.8                 // how much larger the icon under the pointer gets
    readonly property real reach: 140                 // how far the swell reaches

    // The pointer in the Dock, from the Dock's centre (the Dock widens on both sides, so this does not move).
    property real pointerX: 0
    property bool inside: false
    // An icon being dragged, and how far.
    property string dragPkg: ""
    property real dragDx: 0
    property real dragY: 0
    readonly property bool removing: dragPkg !== "" && dragY < -70
    readonly property bool editable: !Host.installer

    readonly property var all: pinned.concat(running)
    readonly property int slots: all.length + 1                     // and the Activities tile
    readonly property real step: iconSize + iconGap
    readonly property real baseWidth: slots * step + iconGap

    // The order while an icon is being dragged: where it would land.
    readonly property int dragFrom: dragPkg === "" ? -1 : pinned.indexOf(dragPkg)
    readonly property int dragTo: dragFrom < 0 ? -1 : Math.max(0, Math.min(pinned.length - 1, Math.round(dragFrom + dragDx / step)))
    function displayIndex(i) {
        if (dragFrom < 0 || i >= pinned.length || removing)
            return i
        if (i === dragFrom)
            return dragTo
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo)
            return i - 1
        if (dragFrom > dragTo && i >= dragTo && i < dragFrom)
            return i + 1
        return i
    }

    Spring { id: hot; to: root.inside && root.dragPkg === "" ? 1 : 0; response: 0.3; dampingFraction: 0.9 }
    Spring { id: follow; to: root.pointerX; response: 0.1; dampingFraction: 1 }

    // The swell of each slot, how much each one takes, and where it ends up.
    readonly property var layout: {
        const n = slots
        const lifts = [], extras = []
        let total = 0
        for (let i = 0; i < n; ++i) {
            const c = (displayIndex(i) + 0.5) * step + iconGap / 2 - baseWidth / 2
            const d = Math.abs(follow.value - c)
            const bell = d < reach ? 0.5 * (1 + Math.cos(Math.PI * d / reach)) : 0
            const lift = bell * hot.value
            lifts.push(lift)
            const e = iconSize * swell * lift
            extras.push(e)
            total += e
        }
        // Positions by the slot's place (displayIndex), not the slot's number.
        const byPlace = new Array(n)
        for (let i = 0; i < n; ++i)
            byPlace[displayIndex(i)] = i
        const xs = new Array(n)
        let before = 0
        for (let p = 0; p < n; ++p) {
            const i = byPlace[p]
            xs[i] = iconGap + p * step + before - baseWidth / 2 - total / 2
            before += extras[i]
            xs[i] += 0
        }
        return { lifts: lifts, xs: xs, total: total }
    }

    implicitWidth: baseWidth + layout.total
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
    onBaseWidthChanged: Qt.callLater(publish)
    Connections { target: root.windowLayer; function onRevisionChanged() { Qt.callLater(root.publish) } }

    // An app dropped from Activities: kept in the Dock.
    function addApp(pkg) {
        if (!editable || pinned.indexOf(pkg) >= 0)
            return
        Settings.setValue("desktop.dock", pinned.concat([pkg]))
    }

    Glass {
        id: bar
        anchors.fill: parent
        source: root.blurSource
        radius: 30
        tint: Theme.light ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0.1, 0.1, 0.12, 0.45)
        clickable: false
    }

    // The pointer: over the Dock's resting size, so the swell does not run away from the pointer that causes it.
    MouseArea {
        id: hit
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.baseWidth
        height: parent.height + 20
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: (m) => {
            if (!root.inside)
                follow.snap(m.x - width / 2)
            root.pointerX = m.x - width / 2
            root.inside = true
        }
        onExited: root.inside = false
    }

    Repeater {
        id: icons
        model: root.all
        delegate: Item {
            id: slot
            required property string modelData
            required property int index
            readonly property string pkg: modelData
            readonly property var info: Packages.count >= 0 ? Packages.get(pkg) : ({})
            readonly property var window: root.windowLayer && root.windowLayer.revision >= 0 ? root.windowLayer.windows[pkg] : null
            readonly property bool isRunning: !!window && !window.doomed
            readonly property bool dragged: root.dragPkg === pkg
            readonly property real lift: root.layout.lifts[index] || 0
            readonly property real size: root.iconSize * (1 + root.swell * lift)
            // The slot is as wide as the icon is swollen; the icon stays at the Dock's bottom edge.
            width: size
            height: root.iconSize
            x: root.width / 2 + (root.layout.xs[index] || 0) + (dragged ? root.dragDx - (root.removing ? 0 : (root.dragTo - root.dragFrom) * root.step) : 0)
            y: 12 - (size - root.iconSize) + (dragged ? Math.min(0, root.dragY) : 0)
            z: dragged ? 10 : 0
            Behavior on x { enabled: !slot.dragged; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            Item {
                id: iconBox
                width: parent.width
                height: parent.width
                opacity: slot.dragged && root.removing ? 0.45 : 1
                scale: tap.pressed && !slot.dragged ? 0.92 : slot.dragged ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: 110 } }
                AppIcon {
                    size: parent.width
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
                y: slot.height + 6 + (slot.size - root.iconSize) * 0
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
            // Drag to rearrange (kept apps only) or out of the Dock to remove.
            DragHandler {
                target: null
                enabled: root.editable && root.pinned.indexOf(slot.pkg) >= 0
                acceptedButtons: Qt.LeftButton
                dragThreshold: 8
                xAxis.enabled: true
                yAxis.enabled: true
                onActiveChanged: {
                    if (active) {
                        root.dragPkg = slot.pkg
                    } else if (root.dragPkg === slot.pkg) {
                        const saved = root.pinned.slice()
                        if (root.removing) {
                            Settings.setValue("desktop.dock", saved.filter(p => p !== slot.pkg))
                        } else if (root.dragTo !== root.dragFrom && root.dragTo >= 0) {
                            saved.splice(root.dragFrom, 1)
                            saved.splice(root.dragTo, 0, slot.pkg)
                            Settings.setValue("desktop.dock", saved)
                        }
                        root.dragPkg = ""
                        root.dragDx = 0
                        root.dragY = 0
                    }
                }
                onTranslationChanged: {
                    if (active) {
                        root.dragDx = translation.x
                        root.dragY = translation.y
                    }
                }
            }
            // The name, above the icon, while the pointer is on it.
            HoverHandler { id: hover }
            Rectangle {
                visible: hover.hovered && root.dragPkg === ""
                anchors.horizontalCenter: parent.horizontalCenter
                y: -34
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
            // "Remove" while it is carried out of the Dock.
            Rectangle {
                visible: slot.dragged && root.removing
                anchors.horizontalCenter: parent.horizontalCenter
                y: -34
                width: removeLabel.implicitWidth + 22
                height: 28
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.7)
                Text {
                    id: removeLabel
                    anchors.centerIn: parent
                    text: qsTr("Remove")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.danger
                }
            }
        }
    }

    // Activities: the tile with the first apps, as in the design. The last place.
    Item {
        id: tile
        readonly property int place: root.all.length
        readonly property real lift: root.layout.lifts[root.all.length] || 0
        width: root.iconSize * (1 + root.swell * lift)
        height: root.iconSize
        x: root.width / 2 + (root.layout.xs[root.all.length] || 0)
        y: 12 - (width - root.iconSize)
        Behavior on x { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Rectangle {
            width: parent.width
            height: parent.width
            radius: width * Theme.iconRadiusRatio
            color: Qt.rgba(1, 1, 1, 0.88)
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 3 * parent.width / root.iconSize
                Repeater {
                    model: Math.min(4, root.pinned.length)
                    AppIcon { required property int index; size: 18 * tile.width / root.iconSize; source: Packages.get(root.pinned[index]).iconUrl || "" }
                }
            }
        }
        TapHandler { onTapped: root.shell.openActivities() }
    }
}
