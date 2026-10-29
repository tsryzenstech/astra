// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// "It's / Sunny / outside" headline driven by the weather service
// (HomeConfig1.png, MusicPlayerConfig1.png).
Item {
    id: root

    readonly property var weather: Weather.current
    readonly property string condition: weather && weather.condition ? weather.condition : ""
    readonly property bool night: condition === "clear"

    readonly property string word: {
        switch (condition) {
        case "sunny": return qsTr("Sunny")
        case "clear": return qsTr("Clear", "weather")
        case "partly-cloudy": return qsTr("Cloudy")
        case "cloudy": return qsTr("Cloudy")
        case "foggy": return qsTr("Foggy")
        case "rainy": return qsTr("Rainy")
        case "snowy": return qsTr("Snowy")
        case "stormy": return qsTr("Stormy")
        }
        return Qt.locale().toString(SystemClock.now, "dddd")
    }
    readonly property string tail: condition === "" ? qsTr("today") : night ? qsTr("tonight") : qsTr("outside")

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        spacing: -16

        Text {
            text: qsTr("It’s")
            font.family: Theme.fontFamily
            font.pixelSize: 54
            font.weight: Font.Light
            color: "white"
        }
        Row {
            spacing: 10
            Text {
                id: word
                text: root.word
                font.family: Theme.fontFamily
                font.pixelSize: 56
                font.weight: Font.DemiBold
                color: "white"
            }
            WeatherGlyph {
                visible: root.condition !== ""
                condition: root.condition
                size: 36
                anchors.verticalCenter: word.verticalCenter
                anchors.verticalCenterOffset: -2
            }
        }
        Text {
            text: root.tail
            font.family: Theme.fontFamily
            font.pixelSize: 44
            font.weight: Font.ExtraLight
            color: "white"
        }
    }
}
