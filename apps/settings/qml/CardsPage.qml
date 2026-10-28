// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Cards: the eight round controls of Control Center, in order.
Page {
    id: page
    title: qsTr("Cards")

    // Must match ControlCenter.qml (SysBoard).
    readonly property var catalog: [
        { id: "location", icon: "location", label: qsTr("Location") },
        { id: "sound", icon: "sound", label: qsTr("Sound") },
        { id: "game", icon: "gamepad", label: qsTr("Game mode") },
        { id: "cast", icon: "cast", label: qsTr("Screen cast") },
        { id: "focus", icon: "focus", label: qsTr("Focus") },
        { id: "scanner", icon: "qr", label: qsTr("Code scanner") },
        { id: "work", icon: "briefcase", label: qsTr("Work profile") },
        { id: "dnd", icon: "moon", label: qsTr("Do Not Disturb") },
        { id: "airplane", icon: "airplane", label: qsTr("Airplane mode") },
        { id: "torch", icon: "flashlight", label: qsTr("Flashlight") },
        { id: "nightlight", icon: "night", label: qsTr("Night light") },
        { id: "data", icon: "signal", label: qsTr("Cellular Data") },
        { id: "screenshot", icon: "image", label: qsTr("Screenshot") }
    ]
    readonly property var defaults: ["location", "sound", "game", "cast", "focus", "scanner", "work", "dnd"]
    readonly property var tiles: Settings.values["controls.tiles"] || defaults
    readonly property var rest: catalog.filter(c => !tiles.includes(c.id))
    function info(id) { return catalog.find(c => c.id === id) }
    function save(list) { Settings.setValue("controls.tiles", list) }

    ListGroup {
        title: qsTr("In Control Center")
        footer: qsTr("Control Center shows eight controls. Remove one to make room for another.")
        Repeater {
            model: page.tiles
            delegate: ListItem {
                required property string modelData
                required property int index
                readonly property var entry: page.info(modelData) || { icon: "info", label: modelData }
                text: entry.label
                iconName: entry.icon
                iconTile: 32
                tileColor: Theme.highlight
                separator: index < page.tiles.length - 1
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "chevron-up"
                    color: Theme.surfaceRaised
                    enabled: index > 0
                    onClicked: {
                        const l = page.tiles.slice()
                        l.splice(index - 1, 0, l.splice(index, 1)[0])
                        page.save(l)
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "minus"
                    color: Theme.danger
                    onClicked: page.save(page.tiles.filter((t, i) => i !== index))
                }
            }
        }
    }

    ListGroup {
        title: qsTr("More controls")
        Repeater {
            id: rest
            model: page.rest
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.label
                iconName: modelData.icon
                iconTile: 32
                tileColor: Theme.switchOff
                enabled: page.tiles.length < 8
                separator: index < rest.count - 1
                onClicked: page.save(page.tiles.concat([modelData.id]))
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "plus"
                    color: Theme.success
                    enabled: page.tiles.length < 8
                    onClicked: page.save(page.tiles.concat([modelData.id]))
                }
            }
        }
    }

    ListGroup {
        ListItem {
            text: qsTr("Reset to default")
            textColor: Theme.accent
            separator: false
            onClicked: Settings.reset("controls.tiles")
        }
    }
}
