// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Convert: lengths, weights, temperatures, volumes, speeds, areas, data and
// time. Type a value, pick the units, and every other unit shows at once.
Rectangle {
    id: app
    color: Theme.background

    // Each unit: [name, symbol, factor to the base unit]. Temperature has its own rules.
    readonly property var kinds: [
        { id: "length", name: qsTr("Length"), icon: "navigation", units: [["Meter", "m", 1], ["Kilometer", "km", 1000], ["Centimeter", "cm", 0.01], ["Millimeter", "mm", 0.001], ["Mile", "mi", 1609.344], ["Yard", "yd", 0.9144], ["Foot", "ft", 0.3048], ["Inch", "in", 0.0254], ["Nautical mile", "nmi", 1852]] },
        { id: "weight", name: qsTr("Weight"), icon: "storage", units: [["Kilogram", "kg", 1], ["Gram", "g", 0.001], ["Milligram", "mg", 0.000001], ["Tonne", "t", 1000], ["Pound", "lb", 0.45359237], ["Ounce", "oz", 0.028349523125], ["Stone", "st", 6.35029318]] },
        { id: "temperature", name: qsTr("Temperature"), icon: "thermometer", units: [["Celsius", "°C"], ["Fahrenheit", "°F"], ["Kelvin", "K"]] },
        { id: "volume", name: qsTr("Volume"), icon: "layers", units: [["Liter", "L", 1], ["Milliliter", "mL", 0.001], ["Cubic meter", "m³", 1000], ["US gallon", "gal", 3.785411784], ["US quart", "qt", 0.946352946], ["US cup", "cup", 0.2365882365], ["Fluid ounce", "fl oz", 0.0295735295625], ["Tablespoon", "tbsp", 0.0147867647813], ["Teaspoon", "tsp", 0.00492892159375]] },
        { id: "speed", name: qsTr("Speed"), icon: "walk", units: [["Meter per second", "m/s", 1], ["Kilometer per hour", "km/h", 0.2777777778], ["Mile per hour", "mph", 0.44704], ["Knot", "kn", 0.5144444444], ["Foot per second", "ft/s", 0.3048]] },
        { id: "area", name: qsTr("Area"), icon: "scene", units: [["Square meter", "m²", 1], ["Square kilometer", "km²", 1000000], ["Hectare", "ha", 10000], ["Square foot", "ft²", 0.09290304], ["Acre", "ac", 4046.8564224], ["Square mile", "mi²", 2589988.110336]] },
        { id: "data", name: qsTr("Data"), icon: "memory", units: [["Byte", "B", 1], ["Kilobyte", "kB", 1000], ["Megabyte", "MB", 1e6], ["Gigabyte", "GB", 1e9], ["Terabyte", "TB", 1e12], ["Kibibyte", "KiB", 1024], ["Mebibyte", "MiB", 1048576], ["Gibibyte", "GiB", 1073741824]] },
        { id: "time", name: qsTr("Time"), icon: "timer", units: [["Second", "s", 1], ["Minute", "min", 60], ["Hour", "h", 3600], ["Day", "d", 86400], ["Week", "wk", 604800], ["Year", "yr", 31557600]] }
    ]
    property int kind: 0
    property int from: 0
    property string text: "1"
    readonly property var units: kinds[kind].units
    readonly property real value: Number(text.replace(",", "."))

    function toBase(v, i) {
        if (kinds[kind].id === "temperature") {
            const u = units[i][1]
            return u === "°C" ? v : u === "°F" ? (v - 32) * 5 / 9 : v - 273.15
        }
        return v * units[i][2]
    }
    function fromBase(b, i) {
        if (kinds[kind].id === "temperature") {
            const u = units[i][1]
            return u === "°C" ? b : u === "°F" ? b * 9 / 5 + 32 : b + 273.15
        }
        return b / units[i][2]
    }
    function format(n) {
        if (!isFinite(n)) return "–"
        if (n === 0) return "0"
        const a = Math.abs(n)
        if (a >= 1e12 || a < 1e-6) return n.toExponential(4).replace(/\.?0+e/, "e")
        return String(Number(n.toPrecision(10)))
    }
    function selectKind(i) { kind = i; from = 0; text = "1" }
    function key(k) {
        if (k === "⌫") text = text.length > 1 ? text.slice(0, -1) : "0"
        else if (k === "±") text = text.startsWith("-") ? text.slice(1) : (text === "0" ? "-" : "-" + text)
        else if (k === ".") { if (text.indexOf(".") < 0) text += "." }
        else if (text.length < 14) text = text === "0" ? k : text + k
    }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(mainPage) }

    Component {
        id: mainPage
        Page {
            title: qsTr("Convert")
            Flickable {
                width: parent.width
                height: 44
                contentWidth: kindRow.width
                clip: true
                Row {
                    id: kindRow
                    spacing: 8
                    Repeater {
                        model: app.kinds
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: label.implicitWidth + 32; height: 38; radius: 19
                            color: app.kind === index ? Theme.accent : Theme.surfaceRaised
                            Text { id: label; anchors.centerIn: parent; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; font.weight: Font.Medium; color: app.kind === index ? Theme.accentText : Theme.text }
                            MouseArea { anchors.fill: parent; onClicked: app.selectKind(index) }
                        }
                    }
                }
            }
            Card {
                accented: true
                Column {
                    width: parent.width
                    spacing: 2
                    Text { text: qsTr(app.units[app.from][0]); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.accentText; opacity: 0.85 }
                    Text { width: parent.width; text: app.text + " " + app.units[app.from][1]; elide: Text.ElideLeft; font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize - 4; font.weight: Font.DemiBold; color: Theme.accentText }
                }
            }
            ListGroup {
                Repeater {
                    model: app.units
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: qsTr(modelData[0])
                        subtitle: modelData[1]
                        selected: app.from === index
                        separator: index < app.units.length - 1
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: app.format(app.fromBase(app.toBase(app.value, app.from), index))
                            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold
                            color: app.from === index ? Theme.accent : Theme.text
                        }
                        onClicked: app.from = index
                    }
                }
            }
            Grid {
                width: parent.width
                columns: 3
                spacing: 10
                Repeater {
                    model: ["7", "8", "9", "4", "5", "6", "1", "2", "3", "±", "0", "."]
                    delegate: Rectangle {
                        required property string modelData
                        width: (parent.width - 20) / 3; height: 54; radius: 16
                        color: area.pressed ? Theme.surfacePressed : Theme.surface
                        Text { anchors.centerIn: parent; text: modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; color: Theme.text }
                        MouseArea { id: area; anchors.fill: parent; onClicked: app.key(modelData) }
                    }
                }
            }
            Row {
                spacing: 10
                width: parent.width
                Button { width: (parent.width - 10) / 2; primary: false; text: qsTr("Clear"); onClicked: app.text = "0" }
                Button { width: (parent.width - 10) / 2; primary: false; iconName: "backspace"; text: qsTr("Delete"); onClicked: app.key("⌫") }
            }
        }
    }
}
