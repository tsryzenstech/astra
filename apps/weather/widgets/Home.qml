// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: the weather here, with the next hours or days.
Item {
    id: root
    property string size: "small"
    readonly property var w: Weather.available ? Weather.current : null
    Column {
        visible: root.w !== null
        spacing: 2
        Text { text: root.w ? root.w.city : ""; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
        Text { text: root.w ? Math.round(root.w.temperature) + "°" : ""; font.family: Theme.fontFamily; font.pixelSize: 40; font.weight: Font.Light; color: "white" }
    }
    WeatherGlyph {
        visible: root.w !== null
        anchors.right: parent.right
        width: 34; height: 34
        condition: root.w ? root.w.condition : ""
    }
    Text {
        visible: root.w !== null
        anchors.bottom: parent.bottom
        text: root.w ? qsTr("H:%1° L:%2°").arg(Math.round(root.w.max)).arg(Math.round(root.w.min)) : ""
        font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.8)
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
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(modelData.time || "").slice(11, 16); font.family: Theme.fontFamily; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.7) }
                WeatherGlyph { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; condition: modelData.condition || "" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temperature) + "°"; font.family: Theme.fontFamily; font.pixelSize: 13; color: "white" }
            }
        }
    }
    Text {
        visible: root.w === null
        anchors.centerIn: parent
        text: qsTr("Weather")
        font.family: Theme.fontFamily; font.pixelSize: 15; color: "white"
    }
}
