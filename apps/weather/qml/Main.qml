// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Weather: the forecast astrad keeps for the chosen place (Open-Meteo),
// hour by hour and for the week, plus a city search.
Rectangle {
    id: app

    readonly property var w: Weather.available ? Weather.current : null
    readonly property bool ready: w !== null
    readonly property bool night: w && w.isDay === false
    readonly property string unit: (Settings.values["weather.units"] || "") === "fahrenheit" ? "°F" : "°"

    function conditionName(c) {
        switch (c) {
        case "sunny": return qsTr("Sunny")
        case "clear": return qsTr("Clear", "weather")
        case "partly-cloudy": return qsTr("Partly cloudy")
        case "cloudy": return qsTr("Cloudy")
        case "foggy": return qsTr("Fog")
        case "rainy": return qsTr("Rain")
        case "snowy": return qsTr("Snow")
        case "stormy": return qsTr("Thunderstorms")
        }
        return ""
    }
    // Sky colours by condition and time of day.
    readonly property var sky: {
        const c = w ? w.condition : ""
        if (night) return ["#0B1026", "#1B2A55"]
        if (c === "rainy" || c === "stormy") return ["#2C3E50", "#4A6274"]
        if (c === "cloudy" || c === "foggy") return ["#5B6B82", "#8FA0B5"]
        if (c === "snowy") return ["#7A8FA8", "#C9D6E3"]
        return ["#1E73E8", "#5AB2FF"]
    }
    gradient: Gradient {
        GradientStop { position: 0; color: app.sky[0]; Behavior on color { ColorAnimation { duration: 600 } } }
        GradientStop { position: 1; color: app.sky[1]; Behavior on color { ColorAnimation { duration: 600 } } }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.height + 80
        boundsBehavior: Flickable.DragOverBounds

        Column {
            id: content
            width: parent.width
            topPadding: Theme.statusBarHeight + 40
            spacing: 18

            // Headline
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.w ? app.w.city : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 32
                    font.weight: Font.Medium
                    color: "white"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.ready ? app.w.temperature + "°" : "—"
                    font.family: Theme.fontFamily
                    font.pixelSize: 96
                    font.weight: Font.Light
                    color: "white"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.ready ? app.conditionName(app.w.condition) : qsTr("Loading the forecast…")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.headlineSize + 3
                    font.weight: Font.Medium
                    color: Qt.rgba(1, 1, 1, 0.9)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: app.ready
                    text: qsTr("H:%1° L:%2°").arg(app.w ? app.w.max : 0).arg(app.w ? app.w.min : 0)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.headlineSize
                    color: "white"
                }
            }

            // Hourly
            Rectangle {
                visible: app.ready
                x: 16
                width: parent.width - 32
                height: 132
                radius: Theme.cardRadius
                color: Qt.rgba(1, 1, 1, 0.14)
                Text {
                    x: 16; y: 12
                    text: qsTr("Hourly forecast")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
                ListView {
                    x: 8; y: 36
                    width: parent.width - 16
                    height: 88
                    orientation: ListView.Horizontal
                    clip: true
                    model: app.w ? app.w.hourly : []
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: 58
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: index === 0 ? qsTr("Now") : modelData.time.substring(11, 13)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                            font.weight: Font.Medium
                            color: "white"
                        }
                        WeatherGlyph { anchors.horizontalCenter: parent.horizontalCenter; condition: modelData.condition; size: 30 }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.temperature + "°"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                    }
                }
            }

            // Daily
            Rectangle {
                visible: app.ready
                x: 16
                width: parent.width - 32
                height: days.height + 48
                radius: Theme.cardRadius
                color: Qt.rgba(1, 1, 1, 0.14)
                readonly property var list: app.w ? app.w.daily : []
                readonly property int lo: list.length ? Math.min.apply(null, list.map(d => d.min)) : 0
                readonly property int hi: list.length ? Math.max.apply(null, list.map(d => d.max)) : 1
                Text {
                    x: 16; y: 12
                    text: qsTr("7-day forecast")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
                Column {
                    id: days
                    x: 16; y: 36
                    width: parent.width - 32
                    Repeater {
                        model: parent.parent.list
                        delegate: Item {
                            id: day
                            required property var modelData
                            required property int index
                            width: days.width
                            height: 46
                            readonly property var card: days.parent
                            Text {
                                width: 64
                                anchors.verticalCenter: parent.verticalCenter
                                text: day.index === 0 ? qsTr("Today") : Qt.locale().toString(new Date(day.modelData.date + "T12:00:00"), "ddd")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize
                                font.weight: Font.Medium
                                color: "white"
                            }
                            WeatherGlyph { x: 66; anchors.verticalCenter: parent.verticalCenter; condition: day.modelData.condition; size: 26 }
                            Text {
                                x: 104
                                width: 36
                                horizontalAlignment: Text.AlignRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: day.modelData.min + "°"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize
                                color: Qt.rgba(1, 1, 1, 0.7)
                            }
                            // Temperature range bar
                            Rectangle {
                                id: track
                                x: 150
                                width: parent.width - 150 - 48
                                height: 6
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(0, 0, 0, 0.18)
                                readonly property real span: Math.max(1, day.card.hi - day.card.lo)
                                Rectangle {
                                    x: (day.modelData.min - day.card.lo) / track.span * track.width
                                    width: Math.max(6, (day.modelData.max - day.modelData.min) / track.span * track.width)
                                    height: parent.height
                                    radius: 3
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "#7CD4FF" }
                                        GradientStop { position: 1; color: "#FFB020" }
                                    }
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: day.modelData.max + "°"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize
                                font.weight: Font.DemiBold
                                color: "white"
                            }
                        }
                    }
                }
            }

            // Details
            Grid {
                visible: app.ready
                x: 16
                columns: 2
                spacing: 12
                readonly property real tile: (app.width - 32 - 12) / 2
                Repeater {
                    model: [
                        { label: qsTr("Feels like"), value: app.w ? app.w.feelsLike + "°" : "" },
                        { label: qsTr("Humidity"), value: app.w ? app.w.humidity + "%" : "" },
                        { label: qsTr("Wind"), value: app.w ? app.w.wind + " km/h" : "" },
                        { label: qsTr("UV index"), value: app.w && app.w.daily.length ? Math.round(app.w.daily[0].uv) : "" },
                        { label: qsTr("Sunrise"), value: app.w && app.w.daily.length ? app.w.daily[0].sunrise.substring(11) : "" },
                        { label: qsTr("Sunset"), value: app.w && app.w.daily.length ? app.w.daily[0].sunset.substring(11) : "" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.tile
                        height: 96
                        radius: Theme.cardRadius
                        color: Qt.rgba(1, 1, 1, 0.14)
                        Column {
                            x: 16; y: 14
                            Text { text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Qt.rgba(1, 1, 1, 0.75) }
                            Text { text: modelData.value; font.family: Theme.fontFamily; font.pixelSize: 30; font.weight: Font.DemiBold; color: "white" }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: app.ready
                text: qsTr("Updated %1 • Open-Meteo").arg(app.w ? Qt.locale().toString(new Date(app.w.updated), "HH:mm") : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize + 1
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }

    // Places button
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: Theme.statusBarHeight + 4
        iconName: "search"
        color: Qt.rgba(1, 1, 1, 0.2)
        onClicked: search.open()
    }

    // ---- city search ---------------------------------------------------------
    Rectangle {
        id: search
        anchors.fill: parent
        color: "#0B0B10"
        visible: opacity > 0
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        property var results: []
        property bool busy: false
        function open() { opacity = 1; field.text = ""; results = []; field.focusInput() }
        function close() { opacity = 0 }
        function find(q) {
            if (q.trim().length < 2) {
                results = []
                return
            }
            busy = true
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                search.busy = false
                try {
                    search.results = JSON.parse(xhr.responseText).results || []
                } catch (e) {
                    search.results = []
                }
            }
            xhr.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=10&language=" + Language.current + "&name=" + encodeURIComponent(q))
            xhr.send()
        }
        function choose(r) {
            Settings.setValue("weather.city", r.name)
            Settings.setValue("weather.latitude", r.latitude)
            Settings.setValue("weather.longitude", r.longitude)
            Weather.refresh()
            close()
        }

        Column {
            x: 16
            y: Theme.statusBarHeight + 10
            width: parent.width - 32
            spacing: 14
            Row {
                spacing: 10
                TextField {
                    id: field
                    width: search.width - 32 - 90
                    placeholder: qsTr("Search for a city")
                    onTextChanged: debounce.restart()
                }
                Button { implicitWidth: 80; primary: false; text: qsTr("Cancel"); onClicked: search.close() }
            }
            Timer { id: debounce; interval: 350; onTriggered: search.find(field.text) }
            Spinner { visible: search.busy; running: search.busy; anchors.horizontalCenter: parent.horizontalCenter }
            ListGroup {
                visible: search.results.length > 0
                Repeater {
                    model: search.results
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        subtitle: [modelData.admin1, modelData.country].filter(x => !!x).join(", ")
                        separator: index < search.results.length - 1
                        onClicked: search.choose(modelData)
                    }
                }
            }
            ListGroup {
                title: qsTr("Units")
                ListItem {
                    text: qsTr("Fahrenheit")
                    showSwitch: true
                    separator: false
                    checked: (Settings.values["weather.units"] || "") === "fahrenheit"
                    onToggled: (on) => {
                        Settings.setValue("weather.units", on ? "fahrenheit" : "celsius")
                        Weather.refresh()
                    }
                }
            }
        }
    }
}
