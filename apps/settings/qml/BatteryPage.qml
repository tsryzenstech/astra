// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Battery: charge, health and the power supply, read from the
// kernel (power_supply class).
Page {
    id: page
    title: qsTr("Battery")

    readonly property var b: System.battery
    readonly property int level: System.batteryLevel

    function status(s) {
        switch (s) {
        case "Charging": return qsTr("Charging")
        case "Discharging": return qsTr("On battery")
        case "Full": return qsTr("Fully charged")
        case "Not charging": return qsTr("Not charging")
        }
        return s || "—"
    }

    Card {
        accented: true
        Column {
            width: parent.width
            spacing: 14
            Row {
                spacing: 14
                BatteryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    level: page.level
                    charging: System.charging
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.level + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    color: "white"
                }
            }
            Text {
                text: page.b.present === false ? qsTr("No battery found") : page.status(page.b.status)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Qt.rgba(1, 1, 1, 0.9)
            }
            ProgressBar {
                width: parent.width
                height: 10
                value: page.level / 100
                color: "white"
                trackColor: Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }

    ListGroup {
        SwitchRow {
            text: qsTr("Battery saver")
            subtitle: qsTr("At 20% or less, apps open without animations and the screen turns off sooner.")
            iconName: "battery"
            key: "battery.saver"
        }
        SwitchRow { text: qsTr("Show percentage in the status bar"); key: "battery.show_percentage"; fallback: true; separator: false }
    }

    ListGroup {
        title: qsTr("Details")
        ListItem { text: qsTr("Health"); value: page.b.health || "—" }
        ListItem { text: qsTr("Temperature"); value: page.b.temperature !== undefined ? (page.b.temperature).toFixed(1) + " °C" : "—" }
        ListItem { text: qsTr("Voltage"); value: page.b.voltage !== undefined ? (page.b.voltage).toFixed(2) + " V" : "—" }
        ListItem { text: qsTr("Technology"); value: page.b.technology || "—" }
        ListItem { text: qsTr("Capacity"); value: page.b.capacityPercent !== undefined ? page.b.capacityPercent + "%" : "—" }
        ListItem { text: qsTr("Current"); value: page.b.current !== undefined ? Math.round(page.b.current) + " mA" : "—" }
        ListItem { text: qsTr("Charger"); value: System.charging ? qsTr("Connected") : qsTr("Not connected"); separator: false }
    }
}
