// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Focus: the Focus modes, and for each one the apps whose
// notifications still come through and whether calls ring.
Page {
    id: page
    title: qsTr("Focus")
    readonly property var modes: [
        { id: "dnd", icon: "moon", color: "#5E5CE6", label: qsTr("Do Not Disturb") },
        { id: "sleep", icon: "night", color: "#30B0C7", label: qsTr("Sleep") },
        { id: "work", icon: "briefcase", color: "#0A84FF", label: qsTr("Work") },
        { id: "personal", icon: "person", color: "#BF5AF2", label: qsTr("Personal") },
        { id: "driving", icon: "car", color: "#FF9F0A", label: qsTr("Driving") },
        { id: "game", icon: "gamepad", color: "#34D058", label: qsTr("Game Mode") }
    ]
    readonly property string current: Settings.values["focus.mode"] || ""

    ListGroup {
        footer: qsTr("A Focus keeps notifications in Notification Center without banners or sounds. Game Mode also gives games all of the processor's speed.")
        Repeater {
            model: page.modes
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.label
                iconName: modelData.icon
                iconTile: 30
                tileColor: modelData.color
                value: page.current === modelData.id ? qsTr("On") : ""
                chevron: true
                separator: index < page.modes.length - 1
                onClicked: page.stack.open(modeEditor, { mode: modelData })
            }
        }
    }
    ListGroup {
        visible: page.current !== ""
        ListItem {
            text: qsTr("Turn Off Focus")
            destructive: true
            separator: false
            onClicked: Settings.setValue("focus.mode", "")
        }
    }

    Component {
        id: modeEditor
        Page {
            id: ed
            property var mode
            title: mode.label
            readonly property string appsKey: "focus." + mode.id + ".apps"
            readonly property var allowed: Settings.values[appsKey] || []
            readonly property var apps: (Packages.count >= 0 ? Packages.list() : []).filter(p => p.launcher).sort((a, b) => a.name.localeCompare(b.name))
            ListGroup {
                ListItem {
                    text: mode.label
                    showSwitch: true
                    checked: Settings.values["focus.mode"] === ed.mode.id
                    onToggled: (on) => Settings.setValue("focus.mode", on ? ed.mode.id : "")
                }
                ListItem {
                    text: qsTr("Calls")
                    value: Settings.values["focus." + ed.mode.id + ".calls"] === "everyone" ? qsTr("Ring") : qsTr("Silent")
                    chevron: true
                    separator: false
                    onClicked: Settings.setValue("focus." + ed.mode.id + ".calls",
                                                 Settings.values["focus." + ed.mode.id + ".calls"] === "everyone" ? "" : "everyone")
                }
            }
            ListGroup {
                title: qsTr("Allowed Notifications")
                footer: qsTr("Banners and sounds from these apps still come through.")
                Repeater {
                    model: ed.apps
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        iconSource: modelData.iconUrl
                        showSwitch: true
                        checked: ed.allowed.indexOf(modelData.package) >= 0
                        separator: index < ed.apps.length - 1
                        onToggled: (on) => Settings.setValue(ed.appsKey, on ? ed.allowed.concat([modelData.package])
                                                                           : ed.allowed.filter(p => p !== modelData.package))
                    }
                }
            }
        }
    }
}
