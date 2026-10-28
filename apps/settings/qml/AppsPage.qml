// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Apps: every installed app, searchable, user apps first.
Page {
    id: page
    title: qsTr("Apps")

    property string filter: ""
    readonly property var apps: {
        const f = filter.toLowerCase()
        return (Packages.count >= 0 ? Packages.list() : [])
            .filter(p => !f || p.name.toLowerCase().indexOf(f) >= 0 || p.package.indexOf(f) >= 0)
            .sort((a, b) => (a.system - b.system) || a.name.localeCompare(b.name))
    }

    TextField {
        width: parent.width
        placeholder: qsTr("Search apps")
        onTextChanged: page.filter = text
    }

    ListGroup {
        footer: qsTr("%n apps installed", "", Packages.count)
        Repeater {
            model: page.apps
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                subtitle: modelData.version + (modelData.system ? " • " + qsTr("System app") : "")
                iconSource: modelData.iconUrl
                chevron: true
                separator: index < page.apps.length - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: modelData.package })
            }
        }
    }
}
