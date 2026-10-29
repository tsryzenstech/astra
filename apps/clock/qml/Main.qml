// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Clock: world clock, alarms (rung by astrad even when the app is closed),
// stopwatch and timers.
Rectangle {
    id: app
    color: Theme.background

    property string tab: "alarms"
    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: app.now = new Date() }

    readonly property string citiesKey: "app.com.astra.clock.cities"
    readonly property var cities: Settings.values[citiesKey] || ["Europe/London", "America/New_York", "Asia/Tokyo"]
    readonly property var alarms: Alarms.state.alarms || []
    readonly property var timers: Alarms.state.timers || []

    function two(n) { return (n < 10 ? "0" : "") + n }
    function dayNames() { return [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")] }
    function repeatText(days) {
        if (!days || days.length === 0)
            return qsTr("Once")
        if (days.length === 7)
            return qsTr("Every day")
        const s = days.slice().sort().join(",")
        if (s === "1,2,3,4,5")
            return qsTr("Weekdays")
        if (s === "0,6")
            return qsTr("Weekends")
        return days.slice().sort().map(d => app.dayNames()[d]).join(" ")
    }

    // ---- pages ---------------------------------------------------------------
    Loader {
        anchors.fill: parent
        anchors.bottomMargin: 96
        sourceComponent: app.tab === "world" ? worldPage : app.tab === "alarms" ? alarmsPage
                         : app.tab === "stopwatch" ? stopwatchPage : timersPage
    }

    // ---- tab bar ---------------------------------------------------------------
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: parent.width - 40
        height: 60
        radius: 30
        color: Theme.surfaceRaised
        Row {
            anchors.fill: parent
            anchors.margins: 5
            Repeater {
                model: [
                    { id: "world", icon: "globe", label: qsTr("World") },
                    { id: "alarms", icon: "alarm", label: qsTr("Alarms") },
                    { id: "stopwatch", icon: "stopwatch", label: qsTr("Stopwatch") },
                    { id: "timers", icon: "timer", label: qsTr("Timers") }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: (parent.width) / 4
                    height: 50
                    radius: 25
                    color: app.tab === modelData.id ? Theme.surfacePressed : "transparent"
                    Column {
                        anchors.centerIn: parent
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 20
                               color: app.tab === modelData.id ? Theme.accent : Theme.text }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: app.tab === modelData.id ? Theme.accent : Theme.textSecondary
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: app.tab = modelData.id }
                }
            }
        }
    }

    // ---- World clock -----------------------------------------------------------
    Component {
        id: worldPage
        Page {
            title: qsTr("World Clock")
            Card {
                accented: true
                Column {
                    Text {
                        text: Qt.locale().toString(app.now, "HH:mm")
                        font.family: Theme.fontFamily; font.pixelSize: 56; font.weight: Font.Bold; color: "white"
                    }
                    Text {
                        text: Qt.locale().toString(app.now, "dddd d MMMM") + " • " + (Settings.values["system.timezone"] || "").split("/").pop().replace(/_/g, " ")
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Qt.rgba(1, 1, 1, 0.9)
                    }
                }
            }
            ListGroup {
                Repeater {
                    model: app.cities
                    delegate: ListItem {
                        required property string modelData
                        required property int index
                        readonly property var zone: { app.now; return System.zone(modelData) }
                        text: zone.city || modelData
                        subtitle: {
                            const h = Math.round((zone.offset || 0) / 360) / 10
                            const day = zone.dayShift > 0 ? qsTr("Tomorrow") : zone.dayShift < 0 ? qsTr("Yesterday") : qsTr("Today")
                            return day + ", " + (h === 0 ? qsTr("same time") : (h > 0 ? "+" : "") + h + "h")
                        }
                        value: zone.time || ""
                        separator: index < app.cities.length - 1
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 28
                            iconName: "minus"
                            color: Theme.danger
                            onClicked: Settings.setValue(app.citiesKey, app.cities.filter(c => c !== modelData))
                        }
                    }
                }
            }
            ListGroup {
                title: qsTr("Add a city")
                Item {
                    width: parent.width
                    height: 70
                    TextField {
                        id: cityField
                        anchors.fill: parent
                        anchors.margins: 11
                        placeholder: qsTr("Search a city or region")
                    }
                }
                property var zones: []
                Component.onCompleted: System.call("system.timezones", {}, (l) => zones = (l || []).filter(z => z.indexOf("/") > 0 && !z.startsWith("Etc/")))
                Repeater {
                    model: cityField.text.length < 2 ? [] : parent.zones.filter(z => z.toLowerCase().replace(/_/g, " ").indexOf(cityField.text.toLowerCase()) >= 0).slice(0, 8)
                    delegate: ListItem {
                        required property string modelData
                        text: modelData.split("/").pop().replace(/_/g, " ")
                        subtitle: modelData.split("/")[0]
                        onClicked: {
                            if (app.cities.indexOf(modelData) < 0)
                                Settings.setValue(app.citiesKey, app.cities.concat([modelData]))
                            cityField.text = ""
                        }
                    }
                }
            }
        }
    }

    // ---- Alarms ------------------------------------------------------------------
    Component {
        id: alarmsPage
        Page {
            id: ap
            title: qsTr("Alarms")
            property var editing: null      // alarm being edited, or {} for a new one
            actions: IconButton {
                iconName: "plus"
                color: Theme.surfaceRaised
                onClicked: ap.editing = { hour: app.now.getHours(), minute: app.now.getMinutes(), days: [], label: "" }
            }

            Card {
                visible: app.alarms.some(a => a.enabled) && !!Alarms.state.next && ap.editing === null
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Alarms.state.next ? qsTr("Next alarm %1").arg(Qt.locale().toString(new Date(Alarms.state.next.time || Alarms.state.next), "ddd HH:mm")) : ""
                    font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text
                }
            }

            // Editor
            Card {
                visible: ap.editing !== null
                Column {
                    width: parent.width
                    spacing: 14
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Repeater {
                            model: ["hour", "minute"]
                            delegate: Column {
                                required property string modelData
                                spacing: 4
                                IconButton { anchors.horizontalCenter: parent.horizontalCenter; size: 36; iconName: "chevron-up"; color: Theme.surfaceRaised
                                    onClicked: { const e = Object.assign({}, ap.editing); e[modelData] = (e[modelData] + 1) % (modelData === "hour" ? 24 : 60); ap.editing = e } }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: ap.editing ? app.two(ap.editing[modelData]) : ""
                                    font.family: Theme.fontFamily; font.pixelSize: 56; font.weight: Font.DemiBold; color: Theme.text
                                }
                                IconButton { anchors.horizontalCenter: parent.horizontalCenter; size: 36; iconName: "chevron-down"; color: Theme.surfaceRaised
                                    onClicked: { const e = Object.assign({}, ap.editing); const m = modelData === "hour" ? 24 : 60; e[modelData] = (e[modelData] + m - 1) % m; ap.editing = e } }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: [1, 2, 3, 4, 5, 6, 0]
                            delegate: Rectangle {
                                required property int modelData
                                readonly property bool on: ap.editing && ap.editing.days.indexOf(modelData) >= 0
                                width: 38; height: 38; radius: 19
                                color: on ? Theme.accent : Theme.surfaceRaised
                                Text { anchors.centerIn: parent; text: app.dayNames()[modelData].charAt(0); font.family: Theme.fontFamily
                                       font.pixelSize: Theme.captionSize + 1; font.weight: Font.DemiBold; color: parent.on ? Theme.accentText : Theme.text }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const e = Object.assign({}, ap.editing)
                                        e.days = parent.on ? e.days.filter(d => d !== modelData) : e.days.concat([modelData])
                                        ap.editing = e
                                    }
                                }
                            }
                        }
                    }
                    TextField {
                        id: labelField
                        width: parent.width
                        placeholder: qsTr("Label")
                        text: ap.editing ? ap.editing.label || "" : ""
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Button { primary: false; text: qsTr("Cancel"); onClicked: ap.editing = null }
                        Button {
                            text: qsTr("Save")
                            onClicked: {
                                const e = ap.editing
                                const params = { hour: e.hour, minute: e.minute, days: e.days, label: labelField.text, enabled: true }
                                if (e.id)
                                    params.id = e.id
                                Alarms.call("set", params, null)
                                ap.editing = null
                            }
                        }
                    }
                    Button {
                        visible: !!(ap.editing && ap.editing.id)
                        anchors.horizontalCenter: parent.horizontalCenter
                        destructive: true
                        text: qsTr("Delete alarm")
                        onClicked: { Alarms.call("delete", { id: ap.editing.id }, null); ap.editing = null }
                    }
                }
            }

            EmptyState {
                visible: app.alarms.length === 0 && ap.editing === null
                iconName: "alarm"
                title: qsTr("No alarms")
                message: qsTr("Tap + to wake up on time.")
            }
            ListGroup {
                visible: app.alarms.length > 0 && ap.editing === null
                Repeater {
                    model: app.alarms
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 88
                        Column {
                            x: 18
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: modelData.enabled ? 1 : 0.45
                            Text { text: app.two(modelData.hour) + ":" + app.two(modelData.minute); font.family: Theme.fontFamily
                                   font.pixelSize: 40; font.weight: Font.Light; color: Theme.text }
                            Text { text: (modelData.label ? modelData.label + ", " : "") + app.repeatText(modelData.days)
                                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary }
                        }
                        MouseArea { anchors.fill: parent; onClicked: ap.editing = Object.assign({}, modelData) }
                        Switch {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            checked: modelData.enabled
                            onToggled: (on) => Alarms.call("set", Object.assign({}, modelData, { enabled: on }), null)
                        }
                        Rectangle { visible: index < app.alarms.length - 1; anchors.bottom: parent.bottom; x: 16; width: parent.width - 32; height: 1; color: Theme.separator }
                    }
                }
            }
        }
    }

    // ---- Stopwatch ---------------------------------------------------------------
    Component {
        id: stopwatchPage
        Item {
            id: sw
            property double started: 0      // ms since epoch when running
            property double accumulated: 0
            property bool running: false
            property var laps: []
            property double tick: 0
            readonly property double elapsed: accumulated + (running ? tick - started : 0)
            Timer { interval: 33; repeat: true; running: sw.running; onTriggered: sw.tick = Date.now() }
            function fmt(ms) {
                const cs = Math.floor(ms / 10) % 100, s = Math.floor(ms / 1000) % 60, m = Math.floor(ms / 60000)
                return app.two(m) + ":" + app.two(s) + "," + app.two(cs)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 80
                text: sw.fmt(sw.elapsed)
                font.family: Theme.fontFamily
                font.pixelSize: 72
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                color: Theme.text
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 200
                spacing: 120
                Rectangle {
                    width: 84; height: 84; radius: 42
                    color: Theme.surfaceRaised
                    Text { anchors.centerIn: parent; text: sw.running ? qsTr("Lap") : qsTr("Reset"); font.family: Theme.fontFamily
                           font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (sw.running) {
                                sw.laps = [sw.elapsed].concat(sw.laps)
                            } else {
                                sw.accumulated = 0
                                sw.laps = []
                            }
                        }
                    }
                }
                Rectangle {
                    width: 84; height: 84; radius: 42
                    color: sw.running ? Qt.rgba(1, 0.27, 0.23, 0.25) : Qt.rgba(0.2, 0.82, 0.35, 0.25)
                    Text { anchors.centerIn: parent; text: sw.running ? qsTr("Stop") : qsTr("Start"); font.family: Theme.fontFamily
                           font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: sw.running ? Theme.danger : Theme.success }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (sw.running) {
                                sw.accumulated += Date.now() - sw.started
                                sw.running = false
                            } else {
                                sw.started = Date.now()
                                sw.tick = sw.started
                                sw.running = true
                            }
                        }
                    }
                }
            }
            ListView {
                x: 16
                y: Theme.statusBarHeight + 310
                width: parent.width - 32
                height: parent.height - y
                clip: true
                model: sw.laps
                delegate: Item {
                    required property real modelData
                    required property int index
                    width: ListView.view.width
                    height: 48
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Lap %1").arg(sw.laps.length - index)
                           font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: sw.fmt(modelData - (index + 1 < sw.laps.length ? sw.laps[index + 1] : 0))
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.features: { "tnum": 1 }; color: Theme.text
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
                }
            }
        }
    }

    // ---- Timers ----------------------------------------------------------------------
    Component {
        id: timersPage
        Page {
            id: tp
            title: qsTr("Timers")
            property int minutes: 5
            property int seconds: 0

            Card {
                Column {
                    width: parent.width
                    spacing: 12
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 24
                        Repeater {
                            model: [ { key: "minutes", max: 180, step: 1 }, { key: "seconds", max: 59, step: 5 } ]
                            delegate: Column {
                                required property var modelData
                                spacing: 4
                                IconButton { anchors.horizontalCenter: parent.horizontalCenter; size: 36; iconName: "chevron-up"; color: Theme.surfaceRaised
                                             onClicked: tp[modelData.key] = Math.min(modelData.max, tp[modelData.key] + modelData.step) }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: app.two(tp[modelData.key])
                                    font.family: Theme.fontFamily; font.pixelSize: 56; font.weight: Font.DemiBold; color: Theme.text
                                }
                                IconButton { anchors.horizontalCenter: parent.horizontalCenter; size: 36; iconName: "chevron-down"; color: Theme.surfaceRaised
                                             onClicked: tp[modelData.key] = Math.max(0, tp[modelData.key] - modelData.step) }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Repeater {
                            model: [1, 3, 5, 10, 15, 30]
                            delegate: Rectangle {
                                required property int modelData
                                width: 44; height: 32; radius: 16
                                color: Theme.surfaceRaised
                                Text { anchors.centerIn: parent; text: modelData + "'"; font.family: Theme.fontFamily
                                       font.pixelSize: Theme.captionSize; color: Theme.text }
                                MouseArea { anchors.fill: parent; onClicked: { tp.minutes = modelData; tp.seconds = 0 } }
                            }
                        }
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Start")
                        enabled: tp.minutes * 60 + tp.seconds > 0
                        onClicked: Alarms.call("startTimer", { seconds: tp.minutes * 60 + tp.seconds,
                                                               label: qsTr("%1 min timer").arg(tp.minutes) }, null)
                    }
                }
            }

            ListGroup {
                visible: app.timers.length > 0
                title: qsTr("Running")
                Repeater {
                    model: app.timers
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property double remaining: Math.max(0, modelData.end - app.now.getTime())
                        width: parent.width
                        height: 86
                        Column {
                            x: 18
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: app.two(Math.floor(parent.parent.remaining / 60000)) + ":" + app.two(Math.floor(parent.parent.remaining / 1000) % 60)
                                font.family: Theme.fontFamily; font.pixelSize: 36; font.weight: Font.Light; color: Theme.text
                            }
                            Text { text: modelData.label || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary }
                        }
                        ProgressBar {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            x: 18
                            width: parent.width - 36 - 60
                            height: 6
                            value: 1 - parent.remaining / (modelData.duration * 1000)
                        }
                        IconButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            color: Theme.surfaceRaised
                            onClicked: Alarms.call("cancelTimer", { id: modelData.id }, null)
                        }
                    }
                }
            }
        }
    }
}
