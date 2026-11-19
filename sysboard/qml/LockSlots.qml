// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick
import Astra.Core

// The lock screens the user has: the first is the one Settings > Lock Screen always had (its
// wallpaper, clock font and widgets live in the old settings keys, which Settings still edits);
// the others are kept in "lockscreen.slots". "lockscreen.slot" says which one is shown.
QtObject {
    id: root

    readonly property var extra: Settings.values["lockscreen.slots"] || []
    readonly property var defaultSlot: ({
        id: 1,
        name: qsTr("Default"),
        wallpaper: Settings.values["display.wallpaper"] || "",
        font: Settings.values["lockscreen.clock_font"] || "",
        weight: Settings.values["lockscreen.clock_weight"] || "SemiBold",
        stretch: Number(Settings.values["lockscreen.stretch"] || 1),
        widgets: Settings.values["lockscreen.widgets"] || []
    })
    readonly property var slots: [defaultSlot].concat(extra)
    readonly property int currentId: Number(Settings.values["lockscreen.slot"] || 1)
    readonly property var current: slots.find(s => s.id === currentId) || defaultSlot

    function select(id) { Settings.setValue("lockscreen.slot", id) }

    function update(id, changes) {
        if (id === 1) {
            const keys = { wallpaper: "display.wallpaper", font: "lockscreen.clock_font", weight: "lockscreen.clock_weight",
                           stretch: "lockscreen.stretch", widgets: "lockscreen.widgets" }
            for (const k in changes)
                if (keys[k])
                    Settings.setValue(keys[k], changes[k])
            return
        }
        Settings.setValue("lockscreen.slots", extra.map(s => s.id === id ? Object.assign({}, s, changes) : s))
    }

    // A new lock screen with the wallpaper chosen; it becomes the current one.
    function add(wallpaper) {
        const id = slots.reduce((m, s) => Math.max(m, s.id), 1) + 1
        const slot = { id: id, name: qsTr("Lock Screen %1").arg(id), wallpaper: wallpaper || "", font: "", weight: "SemiBold",
                       stretch: 1, widgets: [] }
        Settings.setValue("lockscreen.slots", extra.concat([slot]))
        select(id)
        return id
    }

    function remove(id) {
        if (id === 1)
            return
        Settings.setValue("lockscreen.slots", extra.filter(s => s.id !== id))
        if (currentId === id)
            select(1)
    }
}
