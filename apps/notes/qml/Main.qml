// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Notes: folders, pinned notes, search, checklists, sharing and Recently
// Deleted (kept for 30 days). Notes live in the app's private data.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/notes.json"
    property var notes: []        // [{ id, folder, text, pinned, created, modified, deleted }]
    property var folders: []      // [names]
    property int nextId: 1

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) {}
        const month = 30 * 24 * 3600 * 1000
        notes = (s.notes || []).filter(n => !n.deleted || Date.now() - n.deleted < month)
        folders = s.folders || []
        nextId = s.nextId || 1
    }
    function save() { saveTimer.restart() }
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: Files.writeText(app.storePath, JSON.stringify({ notes: app.notes, folders: app.folders, nextId: app.nextId }))
    }
    function update(id, changes) {
        notes = notes.map(n => n.id === id ? Object.assign({}, n, changes, { modified: Date.now() }) : n)
        save()
    }
    function create(folder) {
        const n = { id: nextId++, folder: folder || "", text: "", pinned: false, created: Date.now(), modified: Date.now(), deleted: 0 }
        notes = [n].concat(notes)
        save()
        return n
    }
    function remove(id) {
        const n = notes.find(x => x.id === id)
        if (n && n.deleted)
            notes = notes.filter(x => x.id !== id)
        else
            notes = notes.map(x => x.id === id ? Object.assign({}, x, { deleted: Date.now(), pinned: false }) : x)
        save()
    }
    function titleOf(n) {
        const first = (n.text || "").split("\n").find(l => l.trim() !== "") || ""
        return first.replace(/^[☐☑]\s*/, "").trim() || qsTr("New Note")
    }
    function previewOf(n) {
        const lines = (n.text || "").split("\n").filter(l => l.trim() !== "")
        return (lines[1] || "").replace(/^[☐☑]\s*/, "") || qsTr("No additional text")
    }
    function when(t) {
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.locale().toString(d, Qt.locale().timeFormat(Locale.ShortFormat))
        return Qt.locale().toString(d, Qt.locale().dateFormat(Locale.ShortFormat))
    }
    Component.onCompleted: {
        load()
        if (Application.args.action === "share" && Application.args.text)
            stack.open(editorPage, { noteId: create("").id, initialText: Application.args.text })
    }
    Connections {
        target: Application
        function onIntent(args) {
            if (args.action === "share" && args.text)
                stack.open(editorPage, { noteId: app.create("").id, initialText: args.text })
        }
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(foldersPage)
    }

    // ---- folders --------------------------------------------------------------
    Component {
        id: foldersPage
        Page {
            title: qsTr("Folders")
            actions: IconButton { iconName: "plus"; size: 38; onClicked: newFolder.open() }
            ListGroup {
                ListItem {
                    text: qsTr("All Notes")
                    iconName: "folder"
                    iconColor: Theme.accent
                    value: app.notes.filter(n => !n.deleted).length
                    chevron: true
                    onClicked: stack.open(listPage, { folder: null })
                }
                ListItem {
                    text: qsTr("Notes")
                    iconName: "folder"
                    iconColor: Theme.accent
                    value: app.notes.filter(n => !n.deleted && !n.folder).length
                    chevron: true
                    separator: app.folders.length > 0
                    onClicked: stack.open(listPage, { folder: "" })
                }
                Repeater {
                    model: app.folders
                    delegate: ListItem {
                        required property string modelData
                        required property int index
                        text: modelData
                        iconName: "folder"
                        iconColor: Theme.accent
                        value: app.notes.filter(n => !n.deleted && n.folder === modelData).length
                        chevron: true
                        separator: index < app.folders.length - 1
                        onClicked: stack.open(listPage, { folder: modelData })
                    }
                }
            }
            ListGroup {
                ListItem {
                    text: qsTr("Recently Deleted")
                    iconName: "trash"
                    value: app.notes.filter(n => n.deleted).length
                    chevron: true
                    separator: false
                    onClicked: stack.open(listPage, { folder: null, trash: true })
                }
            }
        }
    }

    // ---- note list --------------------------------------------------------------
    Component {
        id: listPage
        Page {
            id: lp
            property var folder: null      // null: all notes, "": Notes, otherwise a folder
            property bool trash: false
            title: trash ? qsTr("Recently Deleted") : folder === null ? qsTr("All Notes") : folder === "" ? qsTr("Notes") : folder
            readonly property var list: app.notes
                .filter(n => lp.trash ? !!n.deleted : !n.deleted && (lp.folder === null || n.folder === lp.folder))
                .filter(n => !search.text || n.text.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
                .sort((a, b) => (b.pinned - a.pinned) || (b.modified - a.modified))
            function askRestore(n) {
                Dialogs.show({ title: app.titleOf(n), message: qsTr("Recover this note or delete it for good?"),
                               buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" },
                                         { id: "recover", label: qsTr("Recover") }] },
                             function(a) {
                                 if (a === "recover") app.update(n.id, { deleted: 0 })
                                 else if (a === "delete") app.remove(n.id)
                             })
            }
            actions: IconButton {
                visible: !lp.trash
                iconName: "edit"
                size: 38
                color: Theme.accent
                onClicked: stack.open(editorPage, { noteId: app.create(lp.folder || "").id })
            }

            TextField { id: search; width: parent.width; placeholder: qsTr("Search") }
            Text {
                visible: lp.trash
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Notes are deleted for good after 30 days.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
            EmptyState {
                visible: lp.list.length === 0
                iconName: "note"
                title: search.text ? qsTr("No Results") : qsTr("No Notes")
            }
            ListGroup {
                visible: lp.list.length > 0
                Repeater {
                    model: lp.list
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: (modelData.pinned ? "📌 " : "") + app.titleOf(modelData)
                        subtitle: app.when(modelData.modified) + "  " + app.previewOf(modelData)
                        separator: index < lp.list.length - 1
                        onClicked: lp.trash ? lp.askRestore(modelData) : stack.open(editorPage, { noteId: modelData.id })
                    }
                }
            }
        }
    }

    // ---- editor -------------------------------------------------------------------
    Component {
        id: editorPage
        Page {
            id: ep
            property int noteId
            property string initialText: ""
            readonly property var note: app.notes.find(n => n.id === noteId) || ({ text: "" })
            title: ""
            actions: Row {
                spacing: 8
                IconButton { iconName: "checklist"; size: 38; onClicked: ep.toggleChecklist() }
                IconButton { iconName: "share"; size: 38; onClicked: share.open([], "text/plain", "share", body.text) }
                IconButton { iconName: "more"; size: 38; onClicked: menu.open() }
            }
            Component.onCompleted: {
                body.text = initialText || note.text
                if (initialText)
                    app.update(noteId, { text: initialText })
                if (!body.text)
                    body.forceActiveFocus()
            }
            // An empty note is not kept.
            Component.onDestruction: {
                if ((body.text || "").trim() === "") {
                    app.notes = app.notes.filter(n => n.id !== ep.noteId)
                    app.save()
                }
            }
            // ☐ at the start of the line under the cursor (or removes it).
            function toggleChecklist() {
                const t = body.text
                const start = t.lastIndexOf("\n", body.cursorPosition - 1) + 1
                const line = t.slice(start)
                if (/^[☐☑] /.test(line)) {
                    body.remove(start, start + 2)
                } else {
                    body.insert(start, "☐ ")
                }
                body.forceActiveFocus()
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: ep.note.modified ? Qt.locale().toString(new Date(ep.note.modified), "d MMMM yyyy, HH:mm") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textTertiary
            }
            TextEdit {
                id: body
                width: parent.width
                height: Math.max(implicitHeight, 400)
                wrapMode: TextEdit.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize + 1
                color: Theme.text
                selectionColor: Theme.accent
                selectByMouse: true
                textFormat: TextEdit.PlainText
                onTextChanged: if (text !== ep.note.text) app.update(ep.noteId, { text: text })
                Text {
                    visible: body.text === "" && !body.activeFocus
                    text: qsTr("Start typing…")
                    font: body.font
                    color: Theme.textTertiary
                }
                // Tapping a checkbox ticks it.
                TapHandler {
                    onTapped: (point) => {
                        const pos = body.positionAt(point.position.x, point.position.y)
                        const t = body.text
                        const start = t.lastIndexOf("\n", pos - 1) + 1
                        if (pos - start <= 2 && /^[☐☑]/.test(t.slice(start))) {
                            const ticked = t[start] === "☑"
                            body.remove(start, start + 1)
                            body.insert(start, ticked ? "☐" : "☑")
                        }
                    }
                }
            }

            ListSheet {
                id: menu
                items: [
                    { label: ep.note.pinned ? qsTr("Unpin Note") : qsTr("Pin Note"), icon: "pin", run: () => app.update(ep.noteId, { pinned: !ep.note.pinned }) },
                    { label: qsTr("Move to Folder"), icon: "folder", run: () => moveSheet.open() },
                    { label: qsTr("Delete"), icon: "trash", destructive: true, run: () => { app.remove(ep.noteId); stack.pop() } }
                ]
            }
            ListSheet {
                id: moveSheet
                items: [{ label: qsTr("Notes"), icon: "folder", run: () => app.update(ep.noteId, { folder: "" }) }]
                    .concat(app.folders.map(f => ({ label: f, icon: "folder", run: () => app.update(ep.noteId, { folder: f }) })))
            }
        }
    }

    // A small action sheet.
    component ListSheet: Item {
        id: sheet
        property var items: []
        parent: app
        anchors.fill: parent
        z: 50
        visible: rv.value > 0.01
        function open() { rv.animateTo(1, 0) }
        function close() { rv.animateTo(0, 0) }
        Spring { id: rv; to: 0; response: 0.36; dampingFraction: 0.86 }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.4 * rv.value; MouseArea { anchors.fill: parent; onClicked: sheet.close() } }
        ListGroup {
            x: 12
            width: parent.width - 24
            y: parent.height - (height + Theme.homeIndicatorHeight + 12) * rv.value
            Repeater {
                model: sheet.items
                delegate: ListItem {
                    required property var modelData
                    required property int index
                    text: modelData.label
                    iconName: modelData.icon
                    destructive: !!modelData.destructive
                    separator: index < sheet.items.length - 1
                    onClicked: { sheet.close(); modelData.run() }
                }
            }
        }
    }

    // New folder
    Item {
        id: newFolder
        anchors.fill: parent
        z: 60
        visible: false
        function open() { folderName.text = ""; visible = true; folderName.focusInput() }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: newFolder.visible = false } }
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -120
            width: parent.width - 60
            height: col.height + 36
            radius: Theme.cardRadius
            color: Theme.sheet
            Column {
                id: col
                x: 18; y: 18
                width: parent.width - 36
                spacing: 14
                Text { text: qsTr("New Folder"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                TextField { id: folderName; width: parent.width; placeholder: qsTr("Name"); onAccepted: create.clicked() }
                Row {
                    spacing: 10
                    Button { text: qsTr("Cancel"); primary: false; width: (col.width - 10) / 2; onClicked: newFolder.visible = false }
                    Button {
                        id: create
                        text: qsTr("Save")
                        width: (col.width - 10) / 2
                        enabled: folderName.text.trim() !== "" && app.folders.indexOf(folderName.text.trim()) < 0
                        onClicked: {
                            app.folders = app.folders.concat([folderName.text.trim()])
                            app.save()
                            newFolder.visible = false
                        }
                    }
                }
            }
        }
    }

    ShareSheet { id: share }
}
