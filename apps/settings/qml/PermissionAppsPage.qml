// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Every app that asked for one permission, and the user's answer.
Page {
    id: page
    property var permission: ({})
    title: Catalog.tr(permission.label)

    property var apps: []
    function reload() { Permissions.apps(permission.name, function(list) { page.apps = list || [] }) }
    Component.onCompleted: reload()
    Connections {
        target: Permissions
        function onChanged() { page.reload() }
    }

    readonly property var allowed: apps.filter(a => a.state === "granted")
    readonly property var others: apps.filter(a => a.state !== "granted")

    EmptyState {
        visible: page.apps.length === 0
        iconName: page.permission.icon || "shield"
        title: qsTr("No apps")
        message: qsTr("No installed app asked for this permission.")
    }

    ListGroup {
        visible: page.allowed.length > 0
        title: qsTr("Allowed")
        Repeater {
            model: page.allowed
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                iconSource: modelData.icon ? "file://" + modelData.icon : ""
                chevron: true
                separator: index < page.allowed.length - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: modelData.package })
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: true
                    onToggled: Permissions.set(modelData.package, page.permission.name, "denied")
                }
            }
        }
    }

    ListGroup {
        visible: page.others.length > 0
        title: qsTr("Not allowed")
        Repeater {
            model: page.others
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                subtitle: modelData.state === "ask" ? qsTr("Asks every time") : ""
                iconSource: modelData.icon ? "file://" + modelData.icon : ""
                chevron: true
                separator: index < page.others.length - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: modelData.package })
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: false
                    onToggled: Permissions.set(modelData.package, page.permission.name, "granted")
                }
            }
        }
    }
}
