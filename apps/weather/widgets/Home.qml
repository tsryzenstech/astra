// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: the weather here, on a sky that follows it. Small: the city, the glyph, the
// temperature, then the sky and the day's lowest and highest. Larger: the next hours too.
Item {
    id: root
    property string size: "small"
    readonly property var w: Weather.available ? Weather.current : null
    readonly property string cond: w ? (w.condition || "sunny") : "sunny"

    // The sky behind it (HomeWidget paints it from these two).
    readonly property color tileTop: {
        switch (cond) {
        case "sunny": return "#3A2BFF"
        case "partly-cloudy": return "#3F5BE0"
        case "clear": return "#14143F"
        case "cloudy": return "#5C6B8A"
        case "foggy": return "#7A8394"
        case "rainy": return "#3B4A6B"
        case "snowy": return "#6F89B5"
        case "stormy": return "#2A2A4A"
        }
        return "#3A2BFF"
    }
    readonly property color tileBottom: {
        switch (cond) {
        case "sunny": return "#5B6BFF"
        case "partly-cloudy": return "#6C8BF0"
        case "clear": return "#2D2F7A"
        case "cloudy": return "#8493B0"
        case "foggy": return "#A5ADBB"
        case "rainy": return "#5E6F94"
        case "snowy": return "#A9BEDD"
        case "stormy": return "#4A4A75"
        }
        return "#5B6BFF"
    }
    function conditionText(c) {
        switch (c) {
        case "sunny": return qsTr("Sunny")
        case "clear": return qsTr("Clear")
        case "partly-cloudy": return qsTr("Partly cloudy")
        case "cloudy": return qsTr("Cloudy")
        case "foggy": return qsTr("Foggy")
        case "rainy": return qsTr("Rainy")
        case "snowy": return qsTr("Snowy")
        case "stormy": return qsTr("Stormy")
        }
        return ""
    }

    Column {
        visible: root.w !== null
        spacing: 0
        Text { text: root.w ? root.w.city : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.Medium; color: "white" }
        Text { text: root.w ? Math.round(root.w.temperature) + "°" : ""; font.family: Theme.fontFamily; font.pixelSize: 46; font.weight: Font.Normal; color: "white" }
    }
    WeatherGlyph {
        visible: root.w !== null
        anchors.right: parent.right
        width: 30; height: 30
        condition: root.cond
    }
    Column {
        visible: root.w !== null
        anchors.bottom: parent.bottom
        spacing: 1
        Text { text: root.conditionText(root.cond); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: "white" }
        Text {
            text: root.w ? qsTr("%1° / %2°").arg(Math.round(root.w.min)).arg(Math.round(root.w.max)) : ""
            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Qt.rgba(1, 1, 1, 0.8)
        }
    }
    Row {
        visible: root.w !== null && root.size !== "small"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 14
        Repeater {
            model: root.w && root.w.hourly ? root.w.hourly.slice(1, root.size === "large" ? 7 : 5) : []
            delegate: Column {
                required property var modelData
                spacing: 4
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(modelData.time || "").slice(11, 16); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Qt.rgba(1, 1, 1, 0.75) }
                WeatherGlyph { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; condition: modelData.condition || "" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temperature) + "°"; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: "white" }
            }
        }
    }
    Text {
        visible: root.w === null
        anchors.centerIn: parent
        text: qsTr("Weather")
        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: "white"
    }
}
