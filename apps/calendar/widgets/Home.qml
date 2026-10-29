// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: today's date and your next events.
Item {
    id: root
    property string size: "small"
    property var events: []
    function reload() {
        const now = Date.now()
        Calendar.call("list", { from: now, to: now + 7 * 86400000 }, function(list) { root.events = list || [] })
    }
    Component.onCompleted: reload()
    Connections { target: Calendar; function onRevisionChanged() { root.reload() } }
    Timer { interval: 600000; repeat: true; running: true; onTriggered: root.reload() }

    Column {
        Text { text: Qt.locale().toString(new Date(), "dddd").toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: "#FF453A" }
        Text { text: new Date().getDate(); font.family: Theme.fontFamily; font.pixelSize: 38; font.weight: Font.Light; color: "white" }
    }
    Column {
        x: root.size === "small" ? 0 : parent.width * 0.38
        y: root.size === "small" ? 70 : 0
        width: parent.width - x
        spacing: 6
        Text { visible: root.events.length === 0; text: qsTr("No events"); font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.6) }
        Repeater {
            model: root.events.slice(0, root.size === "large" ? 6 : root.size === "medium" ? 3 : 1)
            delegate: Row {
                required property var modelData
                spacing: 8
                Rectangle { width: 3; height: 32; radius: 1.5; color: "#FF7A00" }
                Column {
                    Text { text: modelData.title; width: root.width * 0.55; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
                    Text { text: modelData.allDay ? qsTr("All day") : Qt.locale().toString(new Date(modelData.start), "ddd HH:mm"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.6) }
                }
            }
        }
    }
}
