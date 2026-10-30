import QtQuick
import Astra.Core
import Astra.Controls

// {{name}}: a list of items saved in the app's own data folder, with a
// detail page and a sheet to add one.
Item {
    id: app

    readonly property string file: Files.appData + "/items.json"
    property var items: []

    function load() {
        try { items = JSON.parse(Files.readText(file, 1024 * 1024) || "[]") } catch (e) { items = [] }
    }
    function save() { Files.writeText(file, JSON.stringify(items)) }
    function add(title, notes) {
        items = [{ id: Date.now(), title: title, notes: notes, created: Date.now() }].concat(items)
        save()
    }
    function remove(id) {
        items = items.filter(i => i.id !== id)
        save()
    }
    Component.onCompleted: load()

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(listPage)
    }

    Component {
        id: listPage
        Page {
            title: qsTr("{{name}}")
            actions: IconButton { iconName: "plus"; onClicked: addSheet.open() }
            EmptyState {
                visible: app.items.length === 0
                iconName: "checklist"
                title: qsTr("Nothing here yet")
                message: qsTr("Tap + to add the first item.")
            }
            ListGroup {
                visible: app.items.length > 0
                Repeater {
                    model: app.items
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.title
                        subtitle: Qt.formatDate(new Date(modelData.created), Locale.ShortFormat)
                        chevron: true
                        separator: index < app.items.length - 1
                        onClicked: stack.open(detailPage, { item: modelData })
                    }
                }
            }
        }
    }

    Component {
        id: detailPage
        Page {
            property var item
            title: item ? item.title : ""
            ListGroup {
                ListItem { text: qsTr("Notes"); subtitle: item && item.notes ? item.notes : qsTr("None") }
                ListItem {
                    text: qsTr("Delete")
                    destructive: true
                    separator: false
                    onClicked: { app.remove(item.id); stack.pop() }
                }
            }
        }
    }

    Sheet {
        id: addSheet
        title: qsTr("New Item")
        Column {
            width: parent.width
            spacing: 14
            TextField { id: titleField; width: parent.width; placeholder: qsTr("Title") }
            TextField { id: notesField; width: parent.width; placeholder: qsTr("Notes") }
            Button {
                width: parent.width
                text: qsTr("Add")
                enabled: titleField.text.trim().length > 0
                onClicked: {
                    app.add(titleField.text.trim(), notesField.text.trim())
                    titleField.text = ""
                    notesField.text = ""
                    addSheet.close()
                }
            }
        }
    }
}
