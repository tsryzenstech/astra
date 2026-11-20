// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: today's date, and your next events (or a plus to make one).
Item {
    id: root
    property string size: "small"
    property var events: []
    // A dark card (HomeWidget paints it from these two).
    readonly property color tileTop: "#262628"
    readonly property color tileBottom: "#0E0E10"

    function reload() {
        const now = Date.now()
        Calendar.call("list", { from: now, to: now + 7 * 86400000 }, function(list) { root.events = list || [] })
    }
    Component.onCompleted: reload()
    Connections { target: Calendar; function onRevisionChanged() { root.reload() } }
    Timer { interval: 600000; repeat: true; running: true; onTriggered: root.reload() }

    Column {
        spacing: 0
        Text { text: Qt.locale().toString(new Date(), "dddd"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.Medium; color: "#FF3B30" }
        Text { text: new Date().getDate(); font.family: Theme.fontFamily; font.pixelSize: 46; font.weight: Font.Normal; color: "white" }
    }

    // Nothing planned: the words, and a red plus that opens the calendar.
    Text {
        visible: root.events.length === 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        text: qsTr("No Events")
        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Qt.rgba(1, 1, 1, 0.85)
    }
    Rectangle {
        visible: root.events.length === 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 38; height: 38; radius: 19
        color: "#FF3B30"
        Icon { anchors.centerIn: parent; name: "plus"; size: 20; color: "white" }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: Packages.launch("com.astra.calendar", {}) }
    }

    Column {
        visible: root.events.length > 0
        x: root.size === "small" ? 0 : parent.width * 0.4
        y: root.size === "small" ? 66 : 0
        width: parent.width - x
        spacing: 6
        Repeater {
            model: root.events.slice(0, root.size === "large" ? 6 : root.size === "medium" ? 3 : 1)
            delegate: Row {
                required property var modelData
                spacing: 8
                Rectangle { width: 3; height: 32; radius: 1.5; color: "#FF9500" }
                Column {
                    Text { text: modelData.title; width: root.width * 0.55; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
                    Text { text: modelData.allDay ? qsTr("All day") : Qt.locale().toString(new Date(modelData.start), "ddd HH:mm"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Qt.rgba(1, 1, 1, 0.6) }
                }
            }
        }
    }
}
