// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick
import Astra.Core

// Focus: one mode at a time silences notifications and calls, except for
// the apps the mode allows (Settings > Focus). "focus.mode" holds the mode.
QtObject {
    readonly property var modes: [
        { id: "dnd", icon: "moon", color: "#5E5CE6", label: qsTr("Do Not Disturb") },
        { id: "sleep", icon: "night", color: "#30B0C7", label: qsTr("Sleep") },
        { id: "work", icon: "briefcase", color: "#0A84FF", label: qsTr("Work") },
        { id: "personal", icon: "person", color: "#BF5AF2", label: qsTr("Personal") },
        { id: "driving", icon: "car", color: "#FF9F0A", label: qsTr("Driving") },
        { id: "game", icon: "gamepad", color: "#34D058", label: qsTr("Game Mode") }
    ]
    readonly property string current: Settings.values["focus.mode"] || ""
    readonly property var currentMode: modes.find(m => m.id === current) || null
    readonly property bool silent: Settings.values["controls.sound"] === false

    function allows(pkg) {
        if (!current)
            return true
        return (Settings.values["focus." + current + ".apps"] || []).indexOf(pkg) >= 0
    }
    // Calls ring during a Focus only when the mode allows everyone.
    readonly property bool callsAllowed: !current || Settings.values["focus." + current + ".calls"] === "everyone"
    function toggle(id) { Settings.setValue("focus.mode", current === id ? "" : id) }
}
