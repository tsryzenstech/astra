// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Notes for astraOS Desktop: the list of notes on the left (search, New Note, pinned ones first) and the note being written
// on the right, saved as you type. It reads and writes the same notes.json as the phone's Notes, so the two agree.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/notes.json"
    property var notes: []
    property var folders: []
    property int nextId: 1
    property int currentId: -1
    property string query: ""
    readonly property var visibleNotes: notes.filter(n => !n.deleted && (query === "" || (n.text || "").toLowerCase().indexOf(query.toLowerCase()) >= 0))
        .sort((a, b) => (b.pinned - a.pinned) || (b.modified - a.modified))
    readonly property var current: notes.find(n => n.id === currentId) || null

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) {}
        notes = s.notes || []
        folders = s.folders || []
        nextId = s.nextId || 1
        if (currentId < 0 && visibleNotes.length) currentId = visibleNotes[0].id
    }
    Component.onCompleted: load()
    Timer { id: saveTimer; interval: 400; onTriggered: Files.writeText(app.storePath, JSON.stringify({ notes: app.notes, folders: app.folders, nextId: app.nextId })) }
    function update(id, changes) {
        notes = notes.map(n => n.id === id ? Object.assign({}, n, changes, { modified: Date.now() }) : n)
        saveTimer.restart()
    }
    function create() {
        const n = { id: nextId++, folder: "", text: "", pinned: false, created: Date.now(), modified: Date.now(), deleted: 0 }
        notes = [n].concat(notes)
        currentId = n.id
        saveTimer.restart()
        editor.forceActiveFocus()
    }
    function trash() {
        if (!current) return
        notes = notes.map(x => x.id === currentId ? Object.assign({}, x, { deleted: Date.now(), pinned: false }) : x)
        saveTimer.restart()
        currentId = visibleNotes.length ? visibleNotes[0].id : -1
    }
    function titleOf(n) {
        const first = (n.text || "").split("\n").find(l => l.trim() !== "") || ""
        return first.trim() || qsTr("New Note")
    }
    function previewOf(n) {
        const lines = (n.text || "").split("\n").filter(l => l.trim() !== "")
        return lines[1] || qsTr("No additional text")
    }
    function when(t) {
        const d = new Date(t)
        return d.toDateString() === new Date().toDateString() ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM yyyy")
    }

    // ---- the list ----
    Rectangle {
        id: side
        width: 280
        height: parent.height
        color: Theme.surface
        Rectangle {
            x: 14; y: 40
            width: parent.width - 28 - 44; height: 34; radius: 17
            color: Theme.surfaceRaised
            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 16; color: Theme.textTertiary }
            TextInput {
                anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text; clip: true
                onTextChanged: app.query = text.trim()
                Text { visible: !parent.text; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: qsTr("Search"); font: parent.font; color: Theme.textTertiary }
            }
        }
        ToolButton { x: parent.width - 14 - 34; y: 40; iconName: "add-circle"; onClicked: app.create() }
        ListView {
            x: 8; y: 90
            width: parent.width - 16
            height: parent.height - 98
            clip: true
            spacing: 2
            model: app.visibleNotes
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool on: modelData.id === app.currentId
                width: ListView.view.width
                height: 64
                radius: Theme.radiusSmall
                color: on ? Theme.accent : hover.hovered ? Theme.surfaceRaised : "transparent"
                Column {
                    x: 12; y: 9
                    width: parent.width - 24
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: (row.modelData.pinned ? "● " : "") + app.titleOf(row.modelData)
                           font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: row.on ? Theme.accentText : Theme.text }
                    Text { width: parent.width; elide: Text.ElideRight; text: app.when(row.modelData.modified) + "  " + app.previewOf(row.modelData)
                           font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: row.on ? Theme.accentText : Theme.textSecondary }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: app.currentId = row.modelData.id }
            }
        }
    }
    Rectangle { x: side.width; width: 1; height: parent.height; color: Theme.separator }

    // ---- the note ----
    Item {
        x: side.width + 1
        width: parent.width - x
        height: parent.height
        visible: app.current !== null
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 40
            spacing: 4
            ToolButton { iconName: "bookmark"; checked: !!app.current && app.current.pinned; onClicked: app.update(app.currentId, { pinned: !app.current.pinned }) }
            ToolButton { iconName: "share"; onClicked: { Files.writeText(Files.appData + "/share.txt", app.current.text); share.open([Files.appData + "/share.txt"], "text/plain") } }
            ToolButton { iconName: "trash"; onClicked: app.trash() }
        }
        Text {
            x: 28; y: 46
            text: app.current ? qsTr("Edited %1").arg(app.when(app.current.modified)) : ""
            font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary
        }
        Flickable {
            x: 28; y: 90
            width: parent.width - 56
            height: parent.height - 110
            contentHeight: editor.implicitHeight + 40
            clip: true
            TextEdit {
                id: editor
                width: parent.width
                wrapMode: TextEdit.Wrap
                text: app.current ? app.current.text : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize + 2
                color: Theme.text
                selectionColor: Theme.accent
                onTextChanged: if (app.current && text !== app.current.text) app.update(app.currentId, { text: text })
            }
        }
    }
    EmptyState {
        visible: app.current === null
        x: side.width + (parent.width - side.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        iconName: "bookmark"
        title: qsTr("No Note Selected")
    }
    ShareSheet { id: share }
}
