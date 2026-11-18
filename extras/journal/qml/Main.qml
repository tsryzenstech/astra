// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Journal: one place for what happened today, with a mood. Entries are grouped
// by month, searchable, and stay in the app's private data.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/journal.json"
    readonly property var moods: [
        { id: 1, name: qsTr("Awful"), icon: "weather-stormy" }, { id: 2, name: qsTr("Bad"), icon: "weather-rainy" },
        { id: 3, name: qsTr("Okay"), icon: "weather-cloudy" }, { id: 4, name: qsTr("Good"), icon: "weather-partly-cloudy" },
        { id: 5, name: qsTr("Great"), icon: "weather-sunny" }
    ]
    property var entries: []      // [{ id, text, mood, time }]
    property int nextId: 1
    property string query: ""

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        entries = s.entries || []
        nextId = s.nextId || 1
    }
    function save() { saveTimer.restart() }
    Timer { id: saveTimer; interval: 400; onTriggered: Files.writeText(app.storePath, JSON.stringify({ entries: app.entries, nextId: app.nextId })) }
    Component.onCompleted: load()

    function moodOf(id) { return moods.find(m => m.id === id) || moods[2] }
    function update(id, changes) { entries = entries.map(e => e.id === id ? Object.assign({}, e, changes) : e); save() }
    function create() {
        const e = { id: nextId++, text: "", mood: 3, time: Date.now() }
        entries = [e].concat(entries)
        save()
        return e
    }
    function removeEmpty(id) { entries = entries.filter(e => e.id !== id || e.text.trim() !== ""); save() }
    readonly property var shown: entries.filter(e => !query || e.text.toLowerCase().indexOf(query.toLowerCase()) >= 0).sort((a, b) => b.time - a.time)
    readonly property var months: {
        const by = {}
        for (const e of shown) {
            const k = Qt.locale().toString(new Date(e.time), "MMMM yyyy")
            ;(by[k] = by[k] || []).push(e)
        }
        return Object.keys(by).map(k => ({ name: k, items: by[k] }))
    }
    readonly property int streak: {
        const days = new Set(entries.map(e => new Date(e.time).toDateString()))
        let n = 0
        const d = new Date()
        if (!days.has(d.toDateString())) d.setDate(d.getDate() - 1)
        while (days.has(d.toDateString())) { n++; d.setDate(d.getDate() - 1) }
        return n
    }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(listPage) }

    Component {
        id: listPage
        Page {
            title: qsTr("Journal")
            actions: IconButton { iconName: "edit"; size: 38; color: Theme.accent; onClicked: { const e = app.create(); stack.open(editPage, { entryId: e.id }) } }
            TextField { width: parent.width; placeholder: qsTr("Search"); onTextChanged: app.query = text }
            Card {
                visible: app.entries.length > 0 && app.query === ""
                Row {
                    width: parent.width
                    Column {
                        width: parent.width / 2
                        Text { text: app.entries.length; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text { text: qsTr("entries"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
                    }
                    Column {
                        width: parent.width / 2
                        Text { text: app.streak; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text { text: qsTr("days in a row"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
                    }
                }
            }
            EmptyState {
                visible: app.shown.length === 0
                width: parent.width
                iconName: "book"
                title: app.query ? qsTr("No Results") : qsTr("Nothing written yet")
                message: app.query ? "" : qsTr("Tap the pencil to write about your day.")
            }
            Repeater {
                model: app.months
                delegate: ListGroup {
                    required property var modelData
                    title: modelData.name
                    Repeater {
                        model: modelData.items
                        delegate: ListItem {
                            required property var modelData
                            required property int index
                            text: modelData.text.split("\n")[0] || qsTr("New entry")
                            subtitle: Qt.locale().toString(new Date(modelData.time), "dddd d, HH:mm")
                            iconName: app.moodOf(modelData.mood).icon
                            separator: index < parent.parent.modelData.items.length - 1
                            onClicked: stack.open(editPage, { entryId: modelData.id })
                        }
                    }
                }
            }
        }
    }

    Component {
        id: editPage
        Page {
            id: ep
            property int entryId
            readonly property var entry: app.entries.find(e => e.id === entryId) || { text: "", mood: 3, time: Date.now() }
            title: Qt.locale().toString(new Date(entry.time), "d MMMM")
            Component.onDestruction: app.removeEmpty(entryId)
            actions: IconButton {
                iconName: "trash"; size: 38
                onClicked: Dialogs.show({ title: qsTr("Delete this entry?"), message: qsTr("This can't be undone."),
                                          buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" }] },
                                        function(a) { if (a === "delete") { app.entries = app.entries.filter(e => e.id !== ep.entryId); app.save(); stack.pop() } })
            }
            Text { text: qsTr("How was your day?"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
            Row {
                width: parent.width
                Repeater {
                    model: app.moods
                    delegate: Column {
                        required property var modelData
                        width: parent.width / 5
                        spacing: 4
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52; height: 52; radius: 26
                            color: ep.entry.mood === modelData.id ? Theme.accent : Theme.surfaceRaised
                            Icon { anchors.centerIn: parent; name: modelData.icon; size: 26; color: ep.entry.mood === modelData.id ? Theme.accentText : Theme.textSecondary }
                            MouseArea { anchors.fill: parent; onClicked: app.update(ep.entryId, { mood: modelData.id }) }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: Math.max(260, input.contentHeight + 32)
                radius: Theme.radius
                color: Theme.surface
                TextEdit {
                    id: input
                    x: 16; y: 16
                    width: parent.width - 32
                    text: ep.entry.text
                    wrapMode: TextEdit.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.text
                    selectionColor: Theme.accent
                    onTextChanged: if (text !== ep.entry.text) app.update(ep.entryId, { text: text })
                    Component.onCompleted: if (ep.entry.text === "") forceActiveFocus()
                }
                Text { visible: input.text === ""; x: 16; y: 16; text: qsTr("Write about your day…"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textTertiary }
            }
        }
    }
}
