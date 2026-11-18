// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Habits: things to do every day, with the streak you keep and the last week at a glance.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/habits.json"
    property var habits: []      // [{ id, name, days: ["2026-11-18", ...] }]
    property int nextId: 1
    property int editing: 0
    property int tick: 0         // changes at midnight so "today" follows

    function key(date) {
        const d = date || new Date()
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
    }
    function dayAgo(n) { const d = new Date(); d.setDate(d.getDate() - n); return d }
    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        habits = s.habits || []
        nextId = s.nextId || 1
    }
    function save() { saveTimer.restart() }
    Timer { id: saveTimer; interval: 300; onTriggered: Files.writeText(app.storePath, JSON.stringify({ habits: app.habits, nextId: app.nextId })) }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: app.tick++ }
    Component.onCompleted: load()

    function doneOn(h, k) { return h.days.indexOf(k) >= 0 }
    function toggleDay(id, k) {
        habits = habits.map(h => h.id !== id ? h : Object.assign({}, h, { days: doneOn(h, k) ? h.days.filter(d => d !== k) : h.days.concat([k]) }))
        save()
    }
    // Days in a row up to today (yesterday counts while today is still open).
    function streak(h) {
        tick
        let n = 0
        let i = doneOn(h, key(dayAgo(0))) ? 0 : 1
        while (doneOn(h, key(dayAgo(i)))) { n++; i++ }
        return n
    }
    function best(h) {
        const days = h.days.slice().sort()
        let b = 0, run = 0, prev = 0
        for (const d of days) {
            const t = new Date(d + "T12:00:00").getTime()
            run = prev && Math.round((t - prev) / 86400000) === 1 ? run + 1 : 1
            b = Math.max(b, run)
            prev = t
        }
        return b
    }
    function openEditor(h) {
        editing = h ? h.id : 0
        nameField.text = h ? h.name : ""
        sheet.open()
    }
    function commit() {
        const name = nameField.text.trim()
        if (!name) return
        if (editing)
            habits = habits.map(h => h.id === editing ? Object.assign({}, h, { name: name }) : h)
        else
            habits = habits.concat([{ id: nextId++, name: name, days: [] }])
        save()
        sheet.close()
    }
    readonly property int doneToday: { tick; return habits.filter(h => doneOn(h, key())).length }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(mainPage) }

    Component {
        id: mainPage
        Page {
            title: qsTr("Habits")
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: app.openEditor(null) }

            Card {
                visible: app.habits.length > 0
                accented: true
                Column {
                    width: parent.width
                    spacing: 4
                    Text { text: qsTr("%1 of %2 done today").arg(app.doneToday).arg(app.habits.length); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.accentText }
                    ProgressBar { width: parent.width; height: 8; value: app.habits.length ? app.doneToday / app.habits.length : 0; color: Theme.accentText; trackColor: Theme.glass }
                }
            }
            EmptyState {
                visible: app.habits.length === 0
                width: parent.width
                iconName: "check-circle"
                title: qsTr("No habits yet")
                message: qsTr("Add something you want to do every day: read, walk, drink water.")
            }
            Repeater {
                model: app.habits
                delegate: Card {
                    id: card
                    required property var modelData
                    readonly property bool today: { app.tick; return app.doneOn(modelData, app.key()) }
                    padding: 16
                    Column {
                        width: parent.width
                        spacing: 12
                        Row {
                            width: parent.width
                            spacing: 12
                            Column {
                                width: parent.width - 54 - 12
                                anchors.verticalCenter: parent.verticalCenter
                                Text { width: parent.width; text: card.modelData.name; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                                Text {
                                    text: qsTr("%n days in a row", "", app.streak(card.modelData)) + "  ·  " + qsTr("best %1").arg(app.best(card.modelData))
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary
                                }
                            }
                            Rectangle {
                                width: 54; height: 54; radius: 27
                                color: card.today ? Theme.accent : Theme.surfaceRaised
                                Icon { anchors.centerIn: parent; name: "check"; size: 26; color: card.today ? Theme.accentText : Theme.textTertiary }
                                MouseArea { anchors.fill: parent; onClicked: app.toggleDay(card.modelData.id, app.key()) }
                            }
                        }
                        Row {
                            width: parent.width
                            Repeater {
                                model: 7
                                delegate: Column {
                                    required property int index
                                    readonly property var date: app.dayAgo(6 - index)
                                    readonly property bool on: app.doneOn(card.modelData, app.key(date))
                                    width: parent.width / 7
                                    spacing: 4
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.locale().toString(date, "ddd").slice(0, 2); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textTertiary }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 26; height: 26; radius: 13
                                        color: on ? Theme.accent : Theme.surfaceRaised
                                        Text { anchors.centerIn: parent; text: date.getDate(); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: on ? Theme.accentText : Theme.textSecondary }
                                        MouseArea { anchors.fill: parent; onClicked: app.toggleDay(card.modelData.id, app.key(date)) }
                                    }
                                }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; z: -1; onPressAndHold: app.openEditor(card.modelData) }
                }
            }
            Text {
                visible: app.habits.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Tap a day to mark it. Press and hold a habit to edit it.")
                font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textTertiary
            }
        }
    }

    Sheet {
        id: sheet
        title: app.editing ? qsTr("Edit Habit") : qsTr("New Habit")
        Column {
            width: parent.width
            spacing: 12
            leftPadding: 18
            TextField { id: nameField; width: parent.width - 36; placeholder: qsTr("Name of the habit"); maximumLength: 60; onAccepted: app.commit() }
            Button { width: parent.width - 36; text: app.editing ? qsTr("Save") : qsTr("Add"); enabled: nameField.text.trim() !== ""; onClicked: app.commit() }
            Button {
                visible: app.editing !== 0
                width: parent.width - 36
                destructive: true
                text: qsTr("Delete Habit")
                onClicked: { app.habits = app.habits.filter(h => h.id !== app.editing); app.save(); sheet.close() }
            }
        }
    }
}
