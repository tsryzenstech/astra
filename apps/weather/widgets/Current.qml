// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Lock screen widget (wide): city and today's min / max.
Item {
    readonly property var w: Weather.current

    WeatherGlyph {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        condition: (Weather.available && w.condition) || "cloudy"
        size: 40
    }
    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: -3
        Text {
            width: parent.width
            text: (Weather.available && w.city) || Settings.values["weather.city"] || "Weather"
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            color: "white"
        }
        Text {
            text: Weather.available ? w.min + "° / " + w.max + "°" : "--° / --°"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: "white"
        }
    }
}
