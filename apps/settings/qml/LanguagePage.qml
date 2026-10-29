// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Language & Region. Changing the language applies at once to
// the system UI and to every running app; strings an app does not
// translate stay in English.
Page {
    id: page
    title: qsTr("Language & Region")

    ListGroup {
        title: qsTr("Language")
        Repeater {
            model: Language.available
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                subtitle: modelData.name !== modelData.english ? modelData.english : ""
                selected: modelData.code === Language.current
                separator: index < Language.available.length - 1
                onClicked: Language.set(modelData.code)
            }
        }
    }

    ListGroup {
        title: qsTr("Region")
        ListItem {
            text: qsTr("Temperature")
            value: Settings.values["weather.units"] === "fahrenheit" ? "°F" : "°C"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Temperature"), key: "weather.units",
                options: [ { value: "celsius", label: qsTr("Celsius (°C)") }, { value: "fahrenheit", label: qsTr("Fahrenheit (°F)") } ] })
        }
        ListItem {
            text: qsTr("First day of the week")
            value: Number(Settings.values["region.first_day"] ?? 1) === 0 ? qsTr("Sunday") : qsTr("Monday")
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("First day of the week"), key: "region.first_day",
                options: [ { value: 1, label: qsTr("Monday") }, { value: 0, label: qsTr("Sunday") } ] })
        }
    }
}
