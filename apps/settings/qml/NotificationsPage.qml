// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Notifications: Do Not Disturb, banners and which apps may notify.
Page {
    id: page
    title: qsTr("Notifications")

    property var apps: []
    function reload() { Permissions.apps("astra.permission.NOTIFICATIONS", function(list) { page.apps = (list || []).sort((a, b) => a.name.localeCompare(b.name)) }) }
    Component.onCompleted: reload()
    Connections {
        target: Permissions
        function onChanged() { page.reload() }
    }

    ListGroup {
        ListItem {
            text: qsTr("Focus")
            subtitle: qsTr("Silence notifications and calls, except for the apps you choose.")
            iconName: "moon"
            chevron: true
            onClicked: page.stack.open(Qt.resolvedUrl("FocusPage.qml"))
        }
        SwitchRow {
            text: qsTr("Show on lock screen")
            key: "notifications.lockscreen"
            fallback: true
            separator: false
        }
    }

    ListGroup {
        title: qsTr("Apps")
        footer: page.apps.length === 0 ? qsTr("No app asked to send notifications yet.") : ""
        Repeater {
            model: page.apps
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                iconSource: modelData.icon ? "file://" + modelData.icon : ""
                showSwitch: true
                checked: modelData.state === "granted"
                separator: index < page.apps.length - 1
                onToggled: (on) => Permissions.set(modelData.package, "astra.permission.NOTIFICATIONS", on ? "granted" : "denied")
            }
        }
    }

    ListGroup {
        ListItem {
            text: qsTr("Clear all notifications")
            destructive: true
            enabled: Notifications.count > 0
            separator: false
            onClicked: Notifications.clear()
        }
    }
}
