// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Files: browse the phone's shared storage, organise files and share them
// with other apps. Other apps can share files here ("Save to Files").
Rectangle {
    id: app
    color: Theme.background

    property bool granted: false
    property var clipboard: []          // paths
    property string clipboardMode: ""   // "copy" | "move"
    property var incoming: Application.args.action === "share" ? (Application.args.files || []) : []

    Connections {
        target: Application
        function onIntent(args) {
            if (args.action === "share")
                app.incoming = args.files || []
        }
    }
    Component.onCompleted: Permissions.check("astra.permission.MEDIA", function(ok) { app.granted = !!ok })

    function iconFor(e) {
        if (e.dir) return "folder"
        if (e.mime.startsWith("image/")) return "image"
        if (e.mime.startsWith("video/")) return "video"
        if (e.mime.startsWith("audio/")) return "music"
        if (e.mime === "application/x-astra-apkg") return "download"
        return "file"
    }
    function size(bytes) {
        if (bytes >= 1e9) return (bytes / 1e9).toFixed(1) + " GB"
        if (bytes >= 1e6) return (bytes / 1e6).toFixed(1) + " MB"
        if (bytes >= 1e3) return Math.round(bytes / 1e3) + " KB"
        return bytes + " B"
    }
    function openFile(e) {
        if (e.dir)
            app.push(folderPage, { path: e.path, title: e.name })
        else if (e.mime.startsWith("image/"))
            viewer.show(e)
        else if (e.mime.startsWith("text/") || /\.(json|md|log|conf|ini|qml|js|sh|csv|xml)$/i.test(e.name))
            app.push(textPage, { entry: e })
        else
            share.open([e.path], e.mime, "open")
    }
    function push(page, props) { pageStack.open(page, props || {}) }
    function paste(dir) {
        const n = app.clipboardMode === "move" ? Files.move(app.clipboard, dir) : Files.copy(app.clipboard, dir)
        app.clipboard = []
        app.clipboardMode = ""
        return n
    }

    PageStack {
        id: pageStack
        anchors.fill: parent
        initialItem: browsePage
    }

    // ---- Browse ------------------------------------------------------------------
    Component {
        id: browsePage
        Page {
            title: qsTr("Browse")
            readonly property var usage: Files.usage()

            Column {
                visible: !app.granted
                width: parent.width
                spacing: 16
                EmptyState { iconName: "folder"; title: qsTr("Your files"); message: qsTr("Allow Files to see the files on this phone.") }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Allow access")
                    onClicked: Permissions.request("astra.permission.MEDIA", function(ok) { app.granted = !!ok })
                }
            }

            ListGroup {
                visible: app.granted
                title: qsTr("Locations")
                ListItem {
                    text: qsTr("On My Phone")
                    subtitle: qsTr("%1 free of %2").arg(app.size(usage.free)).arg(app.size(usage.total))
                    iconName: "storage"
                    iconTile: 32
                    tileColor: "#2F80FF"
                    chevron: true
                    onClicked: app.push(folderPage, { path: Files.home, title: qsTr("On My Phone") })
                }
                ListItem {
                    text: qsTr("Recents")
                    iconName: "clock"
                    iconTile: 32
                    tileColor: "#8B5CFF"
                    chevron: true
                    separator: false
                    onClicked: app.push(recentsPage)
                }
            }
            ListGroup {
                visible: app.granted
                title: qsTr("Favorites")
                Repeater {
                    model: [ { dir: "Download", label: qsTr("Downloads"), icon: "download", color: "#34D058" },
                             { dir: "Documents", label: qsTr("Documents"), icon: "file", color: "#FF9F0A" },
                             { dir: "Pictures", label: qsTr("Pictures"), icon: "image", color: "#FF2D8E" },
                             { dir: "DCIM", label: qsTr("Camera"), icon: "camera", color: "#8E8E93" },
                             { dir: "Music", label: qsTr("Music"), icon: "music", color: "#FF453A" },
                             { dir: "Movies", label: qsTr("Movies"), icon: "video", color: "#00C9B1" } ]
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        iconName: modelData.icon
                        iconTile: 32
                        tileColor: modelData.color
                        chevron: true
                        separator: index < 5
                        onClicked: app.push(folderPage, { path: Files.home + "/" + modelData.dir, title: modelData.label })
                    }
                }
            }
            ProgressBar {
                visible: app.granted && usage.total > 0
                width: parent.width
                value: usage.total > 0 ? 1 - usage.free / usage.total : 0
            }
        }
    }

    // ---- Recents -------------------------------------------------------------------
    Component {
        id: recentsPage
        Page {
            title: qsTr("Recents")
            property var items: Files.recent(60)
            EmptyState { visible: parent.items.length === 0; iconName: "clock"; title: qsTr("No recent files") }
            ListGroup {
                visible: parent.items.length > 0
                Repeater {
                    model: parent.parent.items
                    delegate: FileRow { required property var modelData; entry: modelData }
                }
            }
        }
    }

    // ---- Folder ----------------------------------------------------------------------
    Component {
        id: folderPage
        Page {
            id: fp
            property string path
            property string sort: "name"      // name, date, size
            property string query: ""
            property bool selecting: false
            property var selected: ({})
            property int revision: 0
            readonly property var items: {
                revision
                const list = query ? Files.search(path, query) : Files.list(path)
                if (sort === "date")
                    return list.sort((a, b) => (b.dir - a.dir) || (b.modified - a.modified))
                if (sort === "size")
                    return list.sort((a, b) => (b.dir - a.dir) || (b.size - a.size))
                return list
            }
            Connections {
                target: Files
                function onChanged(dir) { fp.revision++ }
            }
            actions: Row {
                spacing: 8
                IconButton { iconName: "add-circle"; size: 36; onClicked: newFolder.visible = true }
                IconButton {
                    iconName: "sort"
                    size: 36
                    onClicked: fp.sort = fp.sort === "name" ? "date" : fp.sort === "date" ? "size" : "name"
                }
                IconButton { iconName: fp.selecting ? "close" : "check-circle"; size: 36; onClicked: { fp.selecting = !fp.selecting; fp.selected = {} } }
            }

            TextField {
                width: parent.width
                placeholder: qsTr("Search in this folder")
                onTextChanged: fp.query = text
            }
            Text {
                text: fp.sort === "name" ? qsTr("Sorted by name") : fp.sort === "date" ? qsTr("Sorted by date") : qsTr("Sorted by size")
                font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textTertiary
            }

            // New folder
            Card {
                id: newFolder
                visible: false
                Column {
                    width: parent.width
                    spacing: 10
                    TextField { id: folderName; width: parent.width; placeholder: qsTr("Folder name") }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Button { primary: false; text: qsTr("Cancel"); onClicked: newFolder.visible = false }
                        Button {
                            text: qsTr("Create")
                            enabled: folderName.text.trim() !== ""
                            onClicked: {
                                Files.mkdir(fp.path, folderName.text)
                                folderName.text = ""
                                newFolder.visible = false
                            }
                        }
                    }
                }
            }

            EmptyState { visible: fp.items.length === 0; iconName: "folder"; title: fp.query ? qsTr("No results") : qsTr("This folder is empty") }
            ListGroup {
                visible: fp.items.length > 0
                Repeater {
                    model: fp.items
                    delegate: FileRow {
                        required property var modelData
                        required property int index
                        entry: modelData
                        separator: index < fp.items.length - 1
                        selecting: fp.selecting
                        isSelected: !!fp.selected[modelData.path]
                        onToggleSelected: {
                            const s = Object.assign({}, fp.selected)
                            if (s[modelData.path]) delete s[modelData.path]; else s[modelData.path] = true
                            fp.selected = s
                        }
                    }
                }
            }

            // Paste / save here
            Button {
                visible: app.clipboard.length > 0 || app.incoming.length > 0
                width: parent.width
                text: app.incoming.length > 0 ? qsTr("Save %n items here", "", app.incoming.length)
                                              : (app.clipboardMode === "move" ? qsTr("Move %n items here", "", app.clipboard.length)
                                                                               : qsTr("Paste %n items here", "", app.clipboard.length))
                onClicked: {
                    if (app.incoming.length > 0) {
                        Files.copy(app.incoming, fp.path)
                        app.incoming = []
                    } else {
                        app.paste(fp.path)
                    }
                }
            }

            // Selection actions
            Row {
                visible: fp.selecting && Object.keys(fp.selected).length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Button { implicitWidth: 100; primary: false; text: qsTr("Copy"); onClicked: { app.clipboard = Object.keys(fp.selected); app.clipboardMode = "copy"; fp.selecting = false } }
                Button { implicitWidth: 100; primary: false; text: qsTr("Move"); onClicked: { app.clipboard = Object.keys(fp.selected); app.clipboardMode = "move"; fp.selecting = false } }
                Button { implicitWidth: 100; primary: false; text: qsTr("Share"); onClicked: share.open(Object.keys(fp.selected), "*/*") }
                Button {
                    implicitWidth: 100
                    destructive: true
                    text: qsTr("Delete")
                    onClicked: {
                        const list = Object.keys(fp.selected)
                        Dialogs.show({ title: qsTr("Delete %n items?", "", list.length), message: qsTr("They are removed from this phone."), icon: "trash",
                                       buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "d", label: qsTr("Delete"), style: "destructive" } ] },
                                     function(b) { if (b === "d") { Files.remove(list); fp.selected = {}; fp.selecting = false } })
                    }
                }
            }
        }
    }

    // ---- Text viewer/editor ------------------------------------------------------------
    Component {
        id: textPage
        Page {
            id: tp
            property var entry: ({})
            title: entry.name || ""
            property bool dirty: false
            actions: Button {
                implicitWidth: 80; implicitHeight: 34
                enabled: tp.dirty
                text: qsTr("Save")
                onClicked: { Files.writeText(tp.entry.path, editor.text); tp.dirty = false }
            }
            Rectangle {
                width: parent.width
                height: Math.max(400, editor.contentHeight + 32)
                radius: Theme.cardRadius
                color: Theme.surface
                TextEdit {
                    id: editor
                    x: 16; y: 16
                    width: parent.width - 32
                    text: Files.readText(tp.entry.path)
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    font.pixelSize: Theme.captionSize + 1
                    color: Theme.text
                    selectionColor: Theme.accent
                    onTextChanged: if (activeFocus) tp.dirty = true
                }
            }
        }
    }

    // ---- one row with its actions -------------------------------------------------------
    component FileRow: ListItem {
        id: row
        property var entry: ({})
        property bool selecting: false
        property bool isSelected: false
        signal toggleSelected()
        text: entry.name
        subtitle: entry.dir ? qsTr("%n items", "", entry.count) : app.size(entry.size) + " • " + Qt.locale().toString(entry.modified, "d MMM yyyy")
        iconName: app.iconFor(entry)
        iconTile: 34
        tileColor: entry.dir ? "#2F80FF" : Theme.surfaceRaised
        selected: selecting && isSelected
        chevron: entry.dir && !selecting
        onClicked: selecting ? toggleSelected() : app.openFile(entry)
        IconButton {
            visible: !row.selecting
            anchors.verticalCenter: parent.verticalCenter
            size: 30
            iconName: "more"
            color: Theme.surfaceRaised
            onClicked: actionsSheet.show(row.entry)
        }
    }

    // ---- item actions sheet -----------------------------------------------------------
    Item {
        id: actionsSheet
        anchors.fill: parent
        z: 900
        property var entry: ({})
        property bool renaming: false
        visible: sheetReveal.value > 0.005
        Spring { id: sheetReveal; to: 0; response: 0.4; dampingFraction: 0.82 }
        function show(e) { entry = e; renaming = false; sheetReveal.animateTo(1, 0) }
        function hide() { sheetReveal.animateTo(0, 0) }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.4 * Math.min(1, sheetReveal.value); MouseArea { anchors.fill: parent; onClicked: actionsSheet.hide() } }
        Rectangle {
            x: 10
            width: parent.width - 20
            height: sheetCol.implicitHeight + 32
            y: parent.height - 12 - height + (1 - sheetReveal.value) * (height + 40)
            radius: Theme.sheetRadius
            color: Theme.sheet
            MouseArea { anchors.fill: parent }
            Column {
                id: sheetCol
                x: 12; y: 16
                width: parent.width - 24
                spacing: 8
                Text { x: 8; width: parent.width - 16; elide: Text.ElideMiddle; text: actionsSheet.entry.name || ""
                       font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                Row {
                    visible: actionsSheet.renaming
                    spacing: 8
                    TextField { id: renameField; width: sheetCol.width - 100; text: actionsSheet.entry.name || "" }
                    Button {
                        implicitWidth: 90
                        text: qsTr("Rename")
                        onClicked: { Files.rename(actionsSheet.entry.path, renameField.text); actionsSheet.hide() }
                    }
                }
                ListGroup {
                    visible: !actionsSheet.renaming
                    Repeater {
                        model: [ { id: "open", label: qsTr("Open with"), icon: "arrow-up" }, { id: "share", label: qsTr("Share"), icon: "share" },
                                 { id: "rename", label: qsTr("Rename"), icon: "edit" }, { id: "duplicate", label: qsTr("Duplicate"), icon: "add-circle" },
                                 { id: "copy", label: qsTr("Copy"), icon: "file" }, { id: "move", label: qsTr("Move"), icon: "folder" },
                                 { id: "info", label: qsTr("Info"), icon: "info" }, { id: "delete", label: qsTr("Delete"), icon: "trash" } ]
                        delegate: ListItem {
                            required property var modelData
                            required property int index
                            visible: !(actionsSheet.entry.dir && (modelData.id === "open" || modelData.id === "share"))
                            height: visible ? implicitHeight : 0
                            text: modelData.label
                            iconName: modelData.icon
                            destructive: modelData.id === "delete"
                            iconColor: modelData.id === "delete" ? Theme.danger : Theme.text
                            separator: index < 7
                            onClicked: {
                                const e = actionsSheet.entry
                                switch (modelData.id) {
                                case "open": actionsSheet.hide(); share.open([e.path], e.mime, "open"); break
                                case "share": actionsSheet.hide(); share.open([e.path], e.mime, "share"); break
                                case "rename": actionsSheet.renaming = true; break
                                case "duplicate": Files.copy([e.path], e.path.substring(0, e.path.lastIndexOf("/"))); actionsSheet.hide(); break
                                case "copy": app.clipboard = [e.path]; app.clipboardMode = "copy"; actionsSheet.hide(); break
                                case "move": app.clipboard = [e.path]; app.clipboardMode = "move"; actionsSheet.hide(); break
                                case "info": {
                                    const i = Files.info(e.path)
                                    actionsSheet.hide()
                                    Dialogs.show({ title: e.name, icon: app.iconFor(e),
                                                   message: qsTr("Size: %1\nModified: %2\nType: %3\nWhere: %4").arg(app.size(i.size))
                                                            .arg(Qt.locale().toString(i.modified, "d MMMM yyyy HH:mm")).arg(i.mime)
                                                            .arg(e.path.replace(Files.home, qsTr("On My Phone"))),
                                                   buttons: [ { id: "ok", label: qsTr("OK") } ] })
                                    break
                                }
                                case "delete":
                                    actionsSheet.hide()
                                    Dialogs.show({ title: qsTr("Delete “%1”?").arg(e.name), message: qsTr("It is removed from this phone."), icon: "trash",
                                                   buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "d", label: qsTr("Delete"), style: "destructive" } ] },
                                                 function(b) { if (b === "d") Files.remove([e.path]) })
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- image quick look -----------------------------------------------------------------
    Rectangle {
        id: viewer
        anchors.fill: parent
        z: 800
        color: "black"
        visible: opacity > 0
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        property var entry: ({})
        function show(e) { entry = e; opacity = 1 }
        Image { anchors.fill: parent; source: viewer.entry.url || ""; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 2048 }
        MouseArea { anchors.fill: parent; onClicked: viewer.opacity = 0 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            spacing: 14
            IconButton { iconName: "share"; color: Qt.rgba(1, 1, 1, 0.16); iconColor: "white"; onClicked: share.open([viewer.entry.path], viewer.entry.mime) }
            IconButton { iconName: "close"; color: Qt.rgba(1, 1, 1, 0.16); iconColor: "white"; onClicked: viewer.opacity = 0 }
        }
    }

    // Shared incoming files: tell the user what to do.
    Rectangle {
        visible: app.incoming.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        width: parent.width - 32
        height: 52
        radius: 26
        color: Theme.accent
        Text { anchors.centerIn: parent; text: qsTr("Open a folder and tap “Save here”"); font.family: Theme.fontFamily
               font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.accentText }
    }

    ShareSheet { id: share }
}
