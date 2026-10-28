// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Searchable list of the IANA time zones known to the system.
Page {
    id: page
    title: qsTr("Time zone")

    property var zones: []
    property string filter: ""
    readonly property var shown: {
        const f = filter.toLowerCase().replace(/ /g, "_")
        return zones.filter(z => !f || z.toLowerCase().indexOf(f) >= 0).slice(0, 80)
    }
    Component.onCompleted: System.call("system.timezones", {}, function(list) {
        page.zones = (list || []).filter(z => z.indexOf("/") > 0 && !z.startsWith("Etc/")).sort()
    })

    TextField {
        width: parent.width
        placeholder: qsTr("Search a city or region")
        onTextChanged: page.filter = text
    }

    ListGroup {
        Repeater {
            model: page.shown
            delegate: ListItem {
                required property string modelData
                required property int index
                text: modelData.split("/").pop().replace(/_/g, " ")
                subtitle: modelData.split("/")[0]
                selected: modelData === Settings.values["system.timezone"]
                separator: index < page.shown.length - 1
                onClicked: System.call("system.setTimezone", { timezone: modelData }, function() { page.stack.pop() })
            }
        }
    }
}
