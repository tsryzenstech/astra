// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Calendar: month grid with the events of the selected day underneath,
// event editor with alerts and repeats. Events are shared through astrad
// (alerts arrive as notifications even when Calendar is closed).
Rectangle {
    id: app
    color: Theme.background

    property bool granted: false
    property date month: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selected: new Date()
    property var events: []          // occurrences around the shown month

    readonly property var colors: ({ orange: "#FF7A00", red: "#FF453A", green: "#34D058", blue: "#0A84FF", purple: "#BF5AF2", yellow: "#FFD60A" })

    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    function dayEvents(d) {
        const s = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const e = s + 86400000
        return events.filter(x => x.start < e && x.end > s)
    }
    function reload() {
        if (!granted)
            return
        const from = new Date(month.getFullYear(), month.getMonth() - 1, 1).getTime()
        const to = new Date(month.getFullYear(), month.getMonth() + 2, 1).getTime()
        Calendar.call("list", { from: from, to: to }, function(list) { app.events = list || [] })
    }
    function time(t) { return Qt.locale().toString(new Date(t), Qt.locale().timeFormat(Locale.ShortFormat)) }
    onMonthChanged: reload()
    Connections { target: Calendar; function onRevisionChanged() { app.reload() } }
    Component.onCompleted: Permissions.request("astra.permission.CALENDAR", function(ok) { app.granted = !!ok; app.reload() })

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(monthPage)
    }

    Component {
        id: monthPage
        Page {
            id: mp
            title: Qt.locale().toString(app.month, "MMMM yyyy")
            actions: Row {
                spacing: 8
                IconButton {
                    iconName: "calendar"
                    size: 38
                    onClicked: {
                        app.selected = new Date()
                        app.month = new Date(app.selected.getFullYear(), app.selected.getMonth(), 1)
                    }
                }
                IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: stack.open(editPage, { event: null, day: app.selected }) }
            }

            EmptyState {
                visible: !app.granted
                iconName: "calendar"
                title: qsTr("Calendar")
                message: qsTr("Allow Calendar in Settings › Apps › Calendar to see your events.")
            }

            // Weekday header
            Row {
                visible: app.granted
                width: parent.width
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        width: parent.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((index + Qt.locale().firstDayOfWeek) % 7, Locale.NarrowFormat)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.footnoteSize
                        color: Theme.textSecondary
                    }
                }
            }
            // Month grid (swipe sideways for the next / previous month)
            Grid {
                id: grid
                visible: app.granted
                width: parent.width
                columns: 7
                readonly property int offset: (app.month.getDay() - Qt.locale().firstDayOfWeek + 7) % 7
                readonly property int days: new Date(app.month.getFullYear(), app.month.getMonth() + 1, 0).getDate()
                Repeater {
                    model: Math.ceil((grid.offset + grid.days) / 7) * 7
                    delegate: Item {
                        required property int index
                        readonly property int dayNumber: index - grid.offset + 1
                        readonly property date day: new Date(app.month.getFullYear(), app.month.getMonth(), dayNumber)
                        readonly property bool inMonth: dayNumber >= 1 && dayNumber <= grid.days
                        readonly property bool today: app.sameDay(day, new Date())
                        readonly property bool chosen: app.sameDay(day, app.selected)
                        readonly property var list: inMonth ? app.dayEvents(day) : []
                        width: grid.width / 7
                        height: 54
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 36; height: 36; radius: 18
                            visible: parent.inMonth && (parent.chosen || parent.today)
                            color: parent.chosen ? (parent.today ? Theme.accent : Theme.text) : "transparent"
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            height: 36
                            verticalAlignment: Text.AlignVCenter
                            visible: parent.inMonth
                            text: parent.dayNumber
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.weight: parent.today || parent.chosen ? Font.DemiBold : Font.Normal
                            color: parent.chosen ? (parent.today ? "white" : Theme.background) : parent.today ? Theme.accent : Theme.text
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 44
                            spacing: 3
                            Repeater {
                                model: Math.min(3, parent.parent.list.length)
                                delegate: Rectangle {
                                    required property int index
                                    width: 5; height: 5; radius: 2.5
                                    color: app.colors[parent.parent.list[index].color] || Theme.accent
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.inMonth
                            onClicked: app.selected = parent.day
                            onDoubleClicked: stack.open(editPage, { event: null, day: parent.day })
                        }
                    }
                }
                // Swipe sideways for the next or previous month.
                DragHandler {
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active)
                            return
                        const dx = centroid.position.x - centroid.pressPosition.x
                        if (Math.abs(dx) > 60)
                            app.month = new Date(app.month.getFullYear(), app.month.getMonth() + (dx < 0 ? 1 : -1), 1)
                    }
                }
            }
            Rectangle { visible: app.granted; width: parent.width; height: 1; color: Theme.separator }

            // Agenda of the selected day
            Text {
                visible: app.granted
                text: Qt.locale().toString(app.selected, "dddd d MMMM")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.Bold
                color: Theme.text
            }
            Text {
                visible: app.granted && app.dayEvents(app.selected).length === 0
                text: qsTr("No Events")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.textSecondary
            }
            Repeater {
                model: app.granted ? app.dayEvents(app.selected) : []
                delegate: Card {
                    required property var modelData
                    width: parent.width
                    padding: 14
                    pressable: true
                    onClicked: stack.open(editPage, { event: modelData, day: app.selected })
                    Row {
                        spacing: 12
                        Rectangle { width: 4; height: 44; radius: 2; color: app.colors[modelData.color] || Theme.accent }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: modelData.title; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                            Text {
                                text: (modelData.allDay ? qsTr("All day") : app.time(modelData.start) + " – " + app.time(modelData.end))
                                      + (modelData.location ? " • " + modelData.location : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.footnoteSize
                                color: Theme.textSecondary
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- editor ----------------------------------------------------------------
    Component {
        id: editPage
        Page {
            id: ep
            property var event: null
            property date day: new Date()
            property date start: event ? new Date(event.start) : new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.min(22, new Date().getHours() + 1))
            property date end: event ? new Date(event.end) : new Date(start.getTime() + 3600000)
            property bool allDay: event ? !!event.allDay : false
            property int alert: event ? event.alert : 15
            property string repeat: event ? event.repeat || "none" : "none"
            property string color: event ? event.color || "orange" : "orange"
            title: event ? qsTr("Edit Event") : qsTr("New Event")
            function shift(which, minutes) {
                if (which === "start") {
                    const len = end.getTime() - start.getTime()
                    start = new Date(start.getTime() + minutes * 60000)
                    end = new Date(start.getTime() + len)
                } else {
                    end = new Date(Math.max(start.getTime() + 15 * 60000, end.getTime() + minutes * 60000))
                }
            }
            actions: Text {
                text: qsTr("Save")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: Theme.accent
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        const s = ep.allDay ? new Date(ep.start.getFullYear(), ep.start.getMonth(), ep.start.getDate()) : ep.start
                        const e = ep.allDay ? new Date(s.getTime() + 86400000 - 1) : ep.end
                        const data = { title: titleField.text.trim() || qsTr("New Event"), location: placeField.text, notes: notesField.text,
                                       start: s.getTime(), end: e.getTime(), allDay: ep.allDay, alert: ep.alert, repeat: ep.repeat, color: ep.color }
                        if (ep.event) Calendar.call("update", Object.assign({ id: ep.event.id }, data), null)
                        else Calendar.call("add", data, null)
                        stack.pop()
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 10
                TextField { id: titleField; width: parent.width; placeholder: qsTr("Title"); text: ep.event ? ep.event.title : "" }
                TextField { id: placeField; width: parent.width; placeholder: qsTr("Location"); text: ep.event ? ep.event.location || "" : "" }
            }
            ListGroup {
                ListItem { text: qsTr("All-day"); showSwitch: true; checked: ep.allDay; onToggled: (on) => ep.allDay = on }
                Stepper {
                    label: qsTr("Starts")
                    value: Qt.locale().toString(ep.start, ep.allDay ? "ddd d MMM yyyy" : "ddd d MMM  HH:mm")
                    onMinus: ep.shift("start", ep.allDay ? -1440 : -15)
                    onPlus: ep.shift("start", ep.allDay ? 1440 : 15)
                    onBigMinus: ep.shift("start", -1440)
                    onBigPlus: ep.shift("start", 1440)
                }
                Stepper {
                    visible: !ep.allDay
                    label: qsTr("Ends")
                    value: Qt.locale().toString(ep.end, "ddd d MMM  HH:mm")
                    onMinus: ep.shift("end", -15)
                    onPlus: ep.shift("end", 15)
                    onBigMinus: ep.shift("end", -60)
                    onBigPlus: ep.shift("end", 60)
                }
            }
            ListGroup {
                ListItem {
                    text: qsTr("Repeat")
                    value: ({ none: qsTr("Never"), daily: qsTr("Every Day"), weekly: qsTr("Every Week"), monthly: qsTr("Every Month"), yearly: qsTr("Every Year") })[ep.repeat]
                    chevron: true
                    onClicked: {
                        const order = ["none", "daily", "weekly", "monthly", "yearly"]
                        ep.repeat = order[(order.indexOf(ep.repeat) + 1) % order.length]
                    }
                }
                ListItem {
                    text: qsTr("Alert")
                    value: ep.alert < 0 ? qsTr("None") : ep.alert === 0 ? qsTr("At time of event") : ep.alert < 60 ? qsTr("%1 minutes before").arg(ep.alert)
                         : ep.alert < 1440 ? qsTr("%n hours before", "", ep.alert / 60) : qsTr("%n days before", "", ep.alert / 1440)
                    chevron: true
                    separator: false
                    onClicked: {
                        const order = [-1, 0, 5, 15, 30, 60, 120, 1440, 2880]
                        ep.alert = order[(order.indexOf(ep.alert) + 1) % order.length]
                    }
                }
            }
            Row {
                spacing: 12
                Repeater {
                    model: Object.keys(app.colors)
                    delegate: Rectangle {
                        required property string modelData
                        width: 34; height: 34; radius: 17
                        color: app.colors[modelData]
                        border.width: ep.color === modelData ? 3 : 0
                        border.color: Theme.text
                        MouseArea { anchors.fill: parent; onClicked: ep.color = parent.modelData }
                    }
                }
            }
            TextField { id: notesField; width: parent.width; placeholder: qsTr("Notes"); text: ep.event ? ep.event.notes || "" : "" }
            Button {
                visible: ep.event !== null
                width: parent.width
                text: qsTr("Delete Event")
                destructive: true
                primary: false
                onClicked: {
                    Calendar.call("delete", { id: ep.event.id }, null)
                    stack.pop()
                }
            }
        }
    }

    // A row with − / + buttons (tap: small step, hold: big step).
    component Stepper: Item {
        id: st
        property string label
        property string value
        signal minus()
        signal plus()
        signal bigMinus()
        signal bigPlus()
        width: parent ? parent.width : 300
        height: Theme.rowHeight
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: st.label; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            IconButton { iconName: "minus"; size: 32; onClicked: st.minus(); onPressAndHold: st.bigMinus() }
            Text { anchors.verticalCenter: parent.verticalCenter; text: st.value; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.accent }
            IconButton { iconName: "plus"; size: 32; onClicked: st.plus(); onPressAndHold: st.bigPlus() }
        }
    }
}
