// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Privacy Options: screen lock PIN, permissions by type, and
// location.
Page {
    id: page
    title: qsTr("Privacy Options")

    property var catalog: []
    function reload() { Permissions.catalog(function(list) { page.catalog = list || [] }) }
    Component.onCompleted: reload()

    ListGroup {
        title: qsTr("Screen lock")
        ListItem {
            text: qsTr("Screen lock PIN")
            iconName: "lock"
            value: Lock.hasPin ? qsTr("On") : qsTr("Off")
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("PinPage.qml"))
        }
    }

    ListGroup {
        title: qsTr("Permissions")
        footer: qsTr("Apps ask before using these. You can change your answer at any time.")
        Repeater {
            model: page.catalog
            delegate: ListItem {
                required property var modelData
                required property int index
                text: Catalog.tr(modelData.label)
                iconName: modelData.icon
                chevron: true
                separator: index < page.catalog.length - 1
                onClicked: stack.open(Qt.resolvedUrl("PermissionAppsPage.qml"), { permission: modelData })
            }
        }
    }

    ListGroup {
        title: qsTr("Location")
        SwitchRow {
            text: qsTr("Use location")
            subtitle: qsTr("Apps with the location permission can find where the phone is.")
            iconName: "location"
            key: "controls.location"
            separator: false
        }
    }
}
