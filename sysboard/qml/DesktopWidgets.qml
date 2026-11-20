// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The widgets on the left of the desktop. At most two (the apps' home screen widgets: app.json "widgets" with
// "home"), or one giant folder: a tall tile with apps in it. They can be moved (dragged: they swap places),
// removed, and added: right click a widget or the desktop. `desktop.widgets` holds them: widget keys
// ("com.astra.weather/home") or { folder: { name, apps: [package...] } }; Weather and Calendar to begin with.
Item {
    id: root

    property var shell
    readonly property real tile: 168
    readonly property real gap: 18
    readonly property var defaults: ["com.astra.weather/home", "com.astra.calendar/home"]

    // What is shown: a folder alone, or up to two widgets that exist.
    readonly property var entries: {
        const saved = Settings.values["desktop.widgets"]
        const list = Array.isArray(saved) ? saved : defaults
        const folder = list.find(e => e && typeof e === "object" && e.folder)
        if (folder)
            return [folder]
        return Packages.count >= 0 ? list.filter(k => typeof k === "string" && Packages.widget(k).key).slice(0, 2) : []
    }
    readonly property bool hasFolder: entries.length > 0 && typeof entries[0] === "object"
    readonly property real slotHeight: tile + gap

    function save(list) { Settings.setValue("desktop.widgets", list) }
    function remove(index) { save(entries.filter((e, i) => i !== index)) }
    function swap(from, to) {
        if (from === to || to < 0 || to >= entries.length)
            return
        const list = entries.slice()
        const moved = list.splice(from, 1)[0]
        list.splice(to, 0, moved)
        save(list)
    }
    function addWidget(key) {
        if (hasFolder)
            return
        if (entries.indexOf(key) >= 0)
            return
        const list = entries.concat([key])
        save(list.slice(-2))      // a third replaces the oldest
    }
    function setFolder(name, apps) {
        save([{ folder: { name: name || qsTr("Apps"), apps: apps } }])
    }
    // The height of what is there, for the desktop to leave room.
    implicitWidth: tile
    implicitHeight: hasFolder ? tile * 2 + gap : entries.length * slotHeight - (entries.length > 0 ? gap : 0)

    signal menuRequested(int index, real x, real y)

    Repeater {
        model: root.entries
        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property bool isFolder: typeof modelData === "object"
            width: root.tile
            height: isFolder ? root.tile * 2 + root.gap : root.tile
            property bool dragging: false
            property real dragY: 0
            x: 0
            y: dragging ? dragY : index * root.slotHeight
            z: dragging ? 5 : 0
            scale: dragging ? 1.04 : 1
            opacity: dragging ? 0.92 : 1
            Behavior on y { enabled: !slot.dragging; SpringNumberAnimation { preset: Motion.snappy } }
            Behavior on scale { NumberAnimation { duration: 120 } }

            Loader {
                anchors.fill: parent
                sourceComponent: slot.isFolder ? folderTile : widgetTile
                property var entry: slot.modelData
            }

            // Drag to move (the widgets swap places), right click for the menu.
            DragHandler {
                id: drag
                target: null
                yAxis.enabled: root.entries.length > 1
                xAxis.enabled: false
                acceptedButtons: Qt.LeftButton
                dragThreshold: 14
                onActiveChanged: {
                    if (active) {
                        slot.dragY = slot.index * root.slotHeight
                        slot.dragging = true
                    } else {
                        const to = Math.max(0, Math.min(root.entries.length - 1, Math.round(slot.dragY / root.slotHeight)))
                        slot.dragging = false
                        root.swap(slot.index, to)
                    }
                }
                onTranslationChanged: if (active) slot.dragY = slot.index * root.slotHeight + translation.y
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (p) => root.menuRequested(slot.index, slot.x + p.position.x, slot.y + p.position.y)
            }
        }
    }

    Component {
        id: widgetTile
        HomeWidget {
            widgetKey: entry
            size: "small"
            shell: root.shell
        }
    }

    // The giant folder: a name and the apps in a grid, each opens its app.
    Component {
        id: folderTile
        Rectangle {
            radius: Theme.cardRadius
            color: Qt.rgba(0.08, 0.08, 0.1, 0.55)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true
            readonly property var apps: (entry.folder.apps || []).filter(p => Packages.count >= 0 && Packages.get(p).package)
            Text {
                x: 16; y: 12
                text: entry.folder.name
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                visible: parent.apps.length === 0
                anchors.centerIn: parent
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Right click to choose the apps in this folder.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Grid {
                x: 16; y: 44
                columns: 3
                spacing: 12
                Repeater {
                    model: parent.parent.apps.slice(0, 18)
                    delegate: Column {
                        required property string modelData
                        readonly property var info: Packages.get(modelData)
                        spacing: 4
                        scale: tap.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        AppIcon { size: 38; source: parent.info.iconUrl || "" }
                        Text {
                            width: 44
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: parent.info.name || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: "white"
                        }
                        TapHandler { id: tap; onTapped: root.shell.launch(parent.modelData, {}, null) }
                    }
                }
            }
        }
    }
}
