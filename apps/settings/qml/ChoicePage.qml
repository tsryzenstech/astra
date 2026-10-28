// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Pick one of several values. Bound to a setting (`key`), or to `current`
// with picked(value) for values that are applied through a service.
//   options: [{ value: 60, label: qsTr("1 minute"), subtitle: "" }]
Page {
    id: page

    property string key
    property var current: key ? Settings.values[key] : undefined
    property var options: []
    property string footer
    property bool popOnPick: false
    signal picked(var value)

    ListGroup {
        footer: page.footer
        Repeater {
            model: page.options
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.label
                subtitle: modelData.subtitle || ""
                selected: String(modelData.value) === String(page.current)
                separator: index < page.options.length - 1
                onClicked: {
                    if (page.key)
                        Settings.setValue(page.key, modelData.value)
                    else
                        page.current = modelData.value
                    page.picked(modelData.value)
                    if (page.popOnPick && page.stack)
                        page.stack.pop()
                }
            }
        }
    }
}
