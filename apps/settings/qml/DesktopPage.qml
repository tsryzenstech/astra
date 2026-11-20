// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Desktop (astraOS Desktop only): the automatic lock, the widgets on the desktop and the Dock.
Page {
    id: page
    title: qsTr("Desktop")
    readonly property var timeouts: [1, 5, 10, 30, 0]
    readonly property var defaultWidgets: ["com.astra.weather/home", "com.astra.calendar/home"]
    readonly property var widgets: Settings.values["desktop.widgets"] || defaultWidgets

    function setWidget(key, on) {
        const now = widgets.filter(k => k !== key)
        Settings.setValue("desktop.widgets", on ? now.concat([key]) : now)
    }

    ListGroup {
        title: qsTr("Lock")
        footer: qsTr("The computer locks after this long without the keyboard or the pointer. How the lock screen looks is in Lock Screen.")
        Repeater {
            model: page.timeouts
            delegate: ListItem {
                required property int modelData
                required property int index
                text: modelData === 0 ? qsTr("Never") : qsTr("After %n minutes", "", modelData)
                selected: Number(Settings.values["desktop.lock_timeout"] ?? 10) === modelData
                separator: index < page.timeouts.length - 1
                onClicked: Settings.setValue("desktop.lock_timeout", modelData)
            }
        }
    }
    ListGroup {
        title: qsTr("Widgets")
        ListItem {
            text: qsTr("Weather")
            showSwitch: true
            checked: page.widgets.indexOf("com.astra.weather/home") >= 0
            onToggled: (on) => page.setWidget("com.astra.weather/home", on)
        }
        ListItem {
            text: qsTr("Calendar")
            showSwitch: true
            separator: false
            checked: page.widgets.indexOf("com.astra.calendar/home") >= 0
            onToggled: (on) => page.setWidget("com.astra.calendar/home", on)
        }
    }
    ListGroup {
        footer: qsTr("The Dock keeps the apps you add with a right click on their icon.")
        ListItem {
            text: qsTr("Reset the Dock")
            separator: false
            onClicked: Settings.setValue("desktop.dock", [])
        }
    }
}
