// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Date & Time: time zone and the 24-hour clock.
Page {
    id: page
    title: qsTr("Date & Time")

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: page.now = new Date() }

    Card {
        accented: true
        Column {
            width: parent.width
            Text {
                text: Settings.values["clock.24h"] === false ? Qt.locale().toString(page.now, "h:mm AP") : Qt.locale().toString(page.now, "HH:mm")
                font.family: Theme.fontFamily
                font.pixelSize: 44
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                text: Qt.locale().toString(page.now, "dddd d MMMM yyyy")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Qt.rgba(1, 1, 1, 0.9)
            }
        }
    }

    ListGroup {
        footer: qsTr("The time is set automatically from the network.")
        ListItem {
            text: qsTr("Time zone")
            value: (Settings.values["system.timezone"] || "UTC").replace(/_/g, " ")
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("TimezonePage.qml"))
        }
        SwitchRow { text: qsTr("24-hour time"); key: "clock.24h"; fallback: true; separator: false }
    }
}
