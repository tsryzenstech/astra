// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Tasks: what to do, with a day when it is due. Open tasks are grouped by
// when they are due (late, today, later, no day); finished ones keep a list
// of their own. Everything stays in the app's private data.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/tasks.json"
    property var tasks: []          // [{ id, title, note, due (ms of that day's midnight, 0: none), flag, done, finished }]
    property int nextId: 1
    property int view: 0            // 0 open, 1 done
    property int editing: 0         // id of the task being edited, 0: a new one
    property int dueChoice: 0       // 0 none, 1 today, 2 tomorrow, 3 next week, -1 a day set before
    property real keptDue: 0

    function midnight(offset) {
        const d = new Date()
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (offset || 0)).getTime()
    }
    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        tasks = s.tasks || []
        nextId = s.nextId || 1
    }
    function save() { saveTimer.restart() }
    Timer { id: saveTimer; interval: 300; onTriggered: Files.writeText(app.storePath, JSON.stringify({ tasks: app.tasks, nextId: app.nextId })) }
    Component.onCompleted: load()

    function openEditor(task) {
        editing = task ? task.id : 0
        titleField.text = task ? task.title : ""
        noteField.text = task ? task.note : ""
        flagSwitch.checked = task ? task.flag : false
        const due = task ? task.due : 0
        keptDue = due
        dueChoice = !due ? 0 : due === midnight(0) ? 1 : due === midnight(1) ? 2 : due === midnight(7) ? 3 : -1
        sheet.open()
    }
    function commit() {
        const title = titleField.text.trim()
        if (!title)
            return
        const due = dueChoice < 0 ? keptDue : [0, midnight(0), midnight(1), midnight(7)][dueChoice]
        if (editing) {
            tasks = tasks.map(t => t.id === editing ? Object.assign({}, t, { title: title, note: noteField.text.trim(), due: due, flag: flagSwitch.checked }) : t)
        } else {
            tasks = tasks.concat([{ id: nextId++, title: title, note: noteField.text.trim(), due: due, flag: flagSwitch.checked, done: false, finished: 0 }])
        }
        save()
        sheet.close()
    }
    function toggle(id) {
        tasks = tasks.map(t => t.id === id ? Object.assign({}, t, { done: !t.done, finished: t.done ? 0 : Date.now() }) : t)
        save()
    }
    function remove(id) { tasks = tasks.filter(t => t.id !== id); save() }
    function clearDone() { tasks = tasks.filter(t => !t.done); save() }

    readonly property var open: tasks.filter(t => !t.done)
    readonly property var done: tasks.filter(t => t.done).sort((a, b) => b.finished - a.finished)
    readonly property var groups: {
        const today = midnight(0)
        const byDue = (a, b) => (a.due || 1e15) - (b.due || 1e15) || (b.flag - a.flag)
        const g = [
            { name: qsTr("Late"), danger: true, items: open.filter(t => t.due && t.due < today).sort(byDue) },
            { name: qsTr("Today"), items: open.filter(t => t.due === today).sort(byDue) },
            { name: qsTr("Later"), items: open.filter(t => t.due > today).sort(byDue) },
            { name: qsTr("Any day"), items: open.filter(t => !t.due).sort(byDue) }
        ]
        return g.filter(x => x.items.length > 0)
    }
    function dueText(t) {
        if (!t.due) return ""
        const d = Math.round((t.due - midnight(0)) / 86400000)
        if (d === 0) return qsTr("Today")
        if (d === 1) return qsTr("Tomorrow")
        if (d === -1) return qsTr("Yesterday")
        return Qt.locale().toString(new Date(t.due), "ddd d MMM")
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(listPage)
    }

    Component {
        id: listPage
        Page {
            title: qsTr("Tasks")
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: app.openEditor(null) }

            SegmentedControl {
                width: parent.width
                model: [qsTr("To do (%1)").arg(app.open.length), qsTr("Done (%1)").arg(app.done.length)]
                currentIndex: app.view
                onActivated: (i) => app.view = i
            }
            EmptyState {
                visible: app.view === 0 && app.open.length === 0
                width: parent.width
                iconName: "checklist"
                title: qsTr("Nothing to do")
                message: qsTr("Tap + to add a task.")
            }
            EmptyState {
                visible: app.view === 1 && app.done.length === 0
                width: parent.width
                iconName: "check-circle"
                title: qsTr("No finished tasks")
                message: qsTr("Tasks you tick off are kept here.")
            }
            Repeater {
                model: app.view === 0 ? app.groups : []
                delegate: ListGroup {
                    required property var modelData
                    title: modelData.name
                    Repeater {
                        model: modelData.items
                        delegate: TaskRow {
                            required property var modelData
                            required property int index
                            task: modelData
                            late: parent.parent.modelData.danger === true
                        }
                    }
                }
            }
            ListGroup {
                visible: app.view === 1 && app.done.length > 0
                Repeater {
                    model: app.view === 1 ? app.done : []
                    delegate: TaskRow { required property var modelData; task: modelData }
                }
            }
            Button {
                visible: app.view === 1 && app.done.length > 0
                width: parent.width
                primary: false
                text: qsTr("Clear Finished Tasks")
                onClicked: app.clearDone()
            }
        }
    }

    component TaskRow: Item {
        id: row
        property var task
        property bool late: false
        width: parent ? parent.width : 300
        height: Math.max(Theme.rowHeight, info.implicitHeight + 24)
        Item {
            id: tick
            x: 6; width: 52; height: parent.height
            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 13
                color: row.task.done ? Theme.accent : "transparent"
                border.width: 2
                border.color: row.task.done ? Theme.accent : row.task.flag ? Theme.warning : Theme.textTertiary
                Icon { anchors.centerIn: parent; visible: row.task.done; name: "check"; size: 16; color: Theme.accentText }
            }
            MouseArea { anchors.fill: parent; onClicked: app.toggle(row.task.id) }
        }
        Column {
            id: info
            x: 58
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 58 - 16
            Text {
                width: parent.width
                text: row.task.title
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.strikeout: row.task.done
                color: row.task.done ? Theme.textTertiary : Theme.text
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: [row.task.flag ? qsTr("Flagged") : "", app.dueText(row.task), row.task.note].filter(s => s).join("  ·  ")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize + 1
                color: row.late ? Theme.danger : Theme.textSecondary
            }
        }
        Rectangle { anchors.bottom: parent.bottom; x: 58; width: parent.width - 58; height: 1; color: Theme.separator }
        MouseArea { x: 58; width: parent.width - 58; height: parent.height; onClicked: app.openEditor(row.task) }
    }

    Sheet {
        id: sheet
        title: app.editing ? qsTr("Edit Task") : qsTr("New Task")
        Column {
            width: parent.width
            spacing: 12
            leftPadding: 18
            rightPadding: 18
            TextField { id: titleField; width: parent.width - 36; placeholder: qsTr("What needs doing?"); maximumLength: 120; onAccepted: app.commit() }
            TextField { id: noteField; width: parent.width - 36; placeholder: qsTr("Note (optional)"); maximumLength: 200 }
            Text { text: qsTr("Due"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
            Text {
                visible: app.dueChoice < 0
                text: qsTr("Due %1: choose a day to change it").arg(Qt.locale().toString(new Date(app.keptDue), "ddd d MMM"))
                font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary
            }
            SegmentedControl {
                width: parent.width - 36
                model: [qsTr("None"), qsTr("Today"), qsTr("Tomorrow"), qsTr("Next week")]
                currentIndex: Math.max(0, app.dueChoice)
                onActivated: (i) => app.dueChoice = i
            }
            Row {
                width: parent.width - 36
                Text { width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Flag as important"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
                Switch { id: flagSwitch; anchors.verticalCenter: parent.verticalCenter }
            }
            Button { width: parent.width - 36; text: app.editing ? qsTr("Save") : qsTr("Add"); enabled: titleField.text.trim() !== ""; onClicked: app.commit() }
            Button { visible: app.editing !== 0; width: parent.width - 36; destructive: true; text: qsTr("Delete Task"); onClicked: { app.remove(app.editing); sheet.close() } }
        }
    }
}
