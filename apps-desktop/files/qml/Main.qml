// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Files for astraOS Desktop: written for a pointer and a keyboard, not a bigger phone screen. A sidebar of
// places, a toolbar with the way back, forward and up, the path, search and the view (list or icons), the
// folder with selection (click, Ctrl-click, Shift-click, Ctrl+A), double click to open, a context menu, the
// keyboard (Enter, F2, Delete, Ctrl+C / X / V, Backspace, Alt+arrows) and Share, which lists the apps and, with
// PetalDrop, the devices nearby.
Rectangle {
    id: app
    color: Theme.background
    focus: true

    property bool granted: false
    property string path: Files.home
    property var history: [Files.home]
    property int historyIndex: 0
    property bool gridView: Settings.values["files.grid"] === true
    property string query: ""
    property var entries: []
    property var selected: ({})          // path -> true
    property string anchorPath: ""
    property var clipboard: []
    property string clipboardMode: ""     // "copy" | "move"
    property string renaming: ""          // path of the entry being renamed
    readonly property var selectedPaths: Object.keys(selected)
    readonly property bool inRecent: path === "recent:"

    readonly property var places: [
        { label: qsTr("Home"), icon: "home", path: Files.home },
        { label: qsTr("Documents"), icon: "file", path: Files.home + "/Documents" },
        { label: qsTr("Downloads"), icon: "download", path: Files.home + "/Download" },
        { label: qsTr("Pictures"), icon: "image", path: Files.home + "/Pictures" },
        { label: qsTr("Music"), icon: "music", path: Files.home + "/Music" },
        { label: qsTr("Movies"), icon: "video", path: Files.home + "/Movies" },
        { label: qsTr("Recordings"), icon: "mic", path: Files.home + "/Recordings" }
    ]

    function reload() {
        if (!granted)
            return
        let list = inRecent ? Files.recent(80) : query ? Files.search(path, query) : Files.list(path, false)
        // Folders first, then by name.
        list = list.slice().sort((a, b) => (b.dir - a.dir) || a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" }))
        entries = list
        const keep = {}
        for (const e of list)
            if (selected[e.path]) keep[e.path] = true
        selected = keep
    }
    function go(dir, remember) {
        if (remember !== false) {
            history = history.slice(0, historyIndex + 1).concat([dir])
            historyIndex = history.length - 1
        }
        path = dir
        query = ""
        search.text = ""
        selected = ({})
        anchorPath = ""
        renaming = ""
        reload()
    }
    function back() { if (historyIndex > 0) { historyIndex--; go(history[historyIndex], false) } }
    function forward() { if (historyIndex < history.length - 1) { historyIndex++; go(history[historyIndex], false) } }
    function up() {
        if (inRecent || path === Files.home) return
        go(path.slice(0, path.lastIndexOf("/")) || Files.home)
    }
    function iconFor(e) {
        if (e.dir) return "folder"
        if (e.mime.startsWith("image/")) return "image"
        if (e.mime.startsWith("video/")) return "video"
        if (e.mime.startsWith("audio/")) return "music"
        if (e.mime === "application/x-astra-apkg") return "download"
        return "file"
    }
    function sizeText(bytes) {
        if (bytes >= 1e9) return (bytes / 1e9).toFixed(1) + " GB"
        if (bytes >= 1e6) return (bytes / 1e6).toFixed(1) + " MB"
        if (bytes >= 1e3) return Math.round(bytes / 1e3) + " KB"
        return bytes + " B"
    }
    function kindText(e) {
        if (e.dir) return qsTr("Folder")
        const m = e.mime || ""
        if (m.startsWith("image/")) return qsTr("Image")
        if (m.startsWith("video/")) return qsTr("Video")
        if (m.startsWith("audio/")) return qsTr("Audio")
        if (m.startsWith("text/")) return qsTr("Text")
        return qsTr("Document")
    }
    function dateText(d) { return d ? Qt.formatDateTime(d, "d MMM yyyy, HH:mm") : "" }

    // Opening: a folder goes into, a file goes to the first app that opens its type.
    function open(e) {
        if (e.dir) {
            go(e.path)
            return
        }
        const targets = Packages.targets(e.mime, "open")
        if (targets.length > 0)
            Packages.launch(targets[0].package, { action: "open", files: [e.path] })
        else
            share.open([e.path], e.mime, "open")
    }
    function entryAt(p) { return entries.find(e => e.path === p) }

    function select(e, mods) {
        if (mods & Qt.ShiftModifier && anchorPath) {
            const a = entries.findIndex(x => x.path === anchorPath), b = entries.findIndex(x => x.path === e.path)
            const s = {}
            for (let i = Math.min(a, b); i <= Math.max(a, b); ++i) s[entries[i].path] = true
            selected = s
            return
        }
        if (mods & Qt.ControlModifier) {
            const s = Object.assign({}, selected)
            if (s[e.path]) delete s[e.path]; else s[e.path] = true
            selected = s
        } else {
            const s = {}
            s[e.path] = true
            selected = s
        }
        anchorPath = e.path
    }
    function selectAll() {
        const s = {}
        for (const e of entries) s[e.path] = true
        selected = s
    }
    function copySelection(mode) {
        clipboard = selectedPaths.slice()
        clipboardMode = mode
    }
    function paste() {
        if (!clipboard.length || inRecent) return
        if (clipboardMode === "move") Files.move(clipboard, path); else Files.copy(clipboard, path)
        if (clipboardMode === "move") clipboard = []
        reload()
    }
    function trash() {
        const list = selectedPaths.slice()
        if (!list.length) return
        Dialogs.show({
            title: list.length === 1 ? qsTr("Delete “%1”?").arg(entryAt(list[0]) ? entryAt(list[0]).name : "") : qsTr("Delete %n items?", "", list.length),
            message: qsTr("They are removed from this computer."), icon: "trash",
            buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "d", label: qsTr("Delete"), style: "destructive" } ]
        }, function(b) { if (b === "d") { Files.remove(list); selected = ({}); app.reload() } })
    }
    function newFolder() {
        const base = qsTr("New Folder")
        let name = base, n = 2
        while (entries.some(e => e.name === name)) name = base + " " + n++
        const made = Files.mkdir(path, name)
        reload()
        if (made) { renaming = made; selected = ({}) ; const s = {}; s[made] = true; selected = s }
    }
    function startRename() {
        if (selectedPaths.length === 1) renaming = selectedPaths[0]
    }
    function commitRename(e, name) {
        renaming = ""
        if (name && name !== e.name) Files.rename(e.path, name)
        reload()
    }
    function info(e) {
        const i = Files.info(e.path)
        Dialogs.show({ title: e.name, icon: iconFor(e),
                       message: qsTr("%1\n%2\nModified %3").arg(kindText(e)).arg(e.dir ? qsTr("%n items", "", i.count || 0) : sizeText(i.size || e.size)).arg(dateText(e.modified)),
                       buttons: [ { id: "ok", label: qsTr("OK"), style: "primary" } ] })
    }

    function menuFor(e) {
        if (!e)
            return [ { id: "newfolder", label: qsTr("New Folder"), icon: "add-circle" },
                     { id: "paste", label: qsTr("Paste"), icon: "file", shortcut: "Ctrl+V", disabled: clipboard.length === 0 },
                     { separator: true },
                     { id: "selectall", label: qsTr("Select All"), shortcut: "Ctrl+A" } ]
        return [ { id: "open", label: qsTr("Open"), icon: "folder", shortcut: "Enter" },
                 { id: "share", label: qsTr("Share"), icon: "share", disabled: e.dir },
                 { separator: true },
                 { id: "copy", label: qsTr("Copy"), shortcut: "Ctrl+C" },
                 { id: "cut", label: qsTr("Cut"), shortcut: "Ctrl+X" },
                 { id: "duplicate", label: qsTr("Duplicate") },
                 { id: "rename", label: qsTr("Rename"), shortcut: "F2" },
                 { id: "info", label: qsTr("Get Info"), icon: "info" },
                 { separator: true },
                 { id: "delete", label: qsTr("Delete"), icon: "trash", danger: true, shortcut: "Del" } ]
    }
    function run(id, e) {
        switch (id) {
        case "open": open(e); break
        case "share": share.open(selectedPaths.length > 1 ? selectedPaths : [e.path], e.mime, "share"); break
        case "copy": copySelection("copy"); break
        case "cut": copySelection("move"); break
        case "duplicate": Files.copy(selectedPaths, path); reload(); break
        case "rename": startRename(); break
        case "info": info(e); break
        case "delete": trash(); break
        case "newfolder": newFolder(); break
        case "paste": paste(); break
        case "selectall": selectAll(); break
        }
    }

    Component.onCompleted: Permissions.check("astra.permission.MEDIA", function(ok) {
        app.granted = !!ok
        if (ok) app.reload()
        else Permissions.request("astra.permission.MEDIA", function(g) { app.granted = !!g; app.reload() })
        if (Application.args.action === "open" && (Application.args.files || []).length) app.reveal(Application.args.files)
    })
    Connections {
        target: Application
        function onIntent(args) { if (args.action === "open") app.reveal(args.files || []) }
    }
    // Another app opens a file or folder here (a download, a PetalDrop receipt): show it.
    function reveal(paths) {
        if (!paths.length || !granted || !Files.allowed(paths[0])) return
        const e = Files.info(paths[0])
        if (!e.name) return
        go(e.dir ? e.path : e.path.slice(0, e.path.lastIndexOf("/")))
        if (!e.dir) { const s = {}; s[e.path] = true; selected = s }
    }
    Connections {
        target: PetalDrop
        function onEvent(name) { if (name === "received") app.reload() }
    }

    Keys.onPressed: (ev) => {
        const ctrl = ev.modifiers & Qt.ControlModifier
        if (ctrl && ev.key === Qt.Key_A) { selectAll(); ev.accepted = true }
        else if (ctrl && ev.key === Qt.Key_C) { copySelection("copy"); ev.accepted = true }
        else if (ctrl && ev.key === Qt.Key_X) { copySelection("move"); ev.accepted = true }
        else if (ctrl && ev.key === Qt.Key_V) { paste(); ev.accepted = true }
        else if (ctrl && ev.key === Qt.Key_F) { search.forceActiveFocus(); ev.accepted = true }
        else if (ctrl && ev.key === Qt.Key_N && ev.modifiers & Qt.ShiftModifier) { newFolder(); ev.accepted = true }
        else if (ev.key === Qt.Key_F2) { startRename(); ev.accepted = true }
        else if (ev.key === Qt.Key_Delete) { trash(); ev.accepted = true }
        else if (ev.key === Qt.Key_Backspace || (ev.modifiers & Qt.AltModifier && ev.key === Qt.Key_Up)) { up(); ev.accepted = true }
        else if (ev.modifiers & Qt.AltModifier && ev.key === Qt.Key_Left) { back(); ev.accepted = true }
        else if (ev.modifiers & Qt.AltModifier && ev.key === Qt.Key_Right) { forward(); ev.accepted = true }
        else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && selectedPaths.length === 1) { const e = entryAt(selectedPaths[0]); if (e) open(e); ev.accepted = true }
        else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Up) {
            if (!entries.length) return
            let i = entries.findIndex(x => x.path === anchorPath)
            i = ev.key === Qt.Key_Down ? Math.min(entries.length - 1, i + 1) : Math.max(0, i < 0 ? 0 : i - 1)
            select(entries[i], ev.modifiers)
            ev.accepted = true
        }
        else if (ev.key === Qt.Key_Escape) { selected = ({}); renaming = ""; search.text = ""; ev.accepted = true }
    }

    // ---- sidebar ---------------------------------------------------------------------------------
    Rectangle {
        id: sidebar
        width: 200
        height: parent.height
        color: Theme.surface

        Column {
            x: 10
            y: 44
            width: parent.width - 20
            spacing: 2
            Text {
                text: qsTr("Places")
                leftPadding: 10
                bottomPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
                color: Theme.textTertiary
            }
            SidebarItem { width: parent.width; text: qsTr("Recent"); iconName: "clock"; selected: app.inRecent; onClicked: app.go("recent:") }
            Repeater {
                model: app.places
                delegate: SidebarItem {
                    required property var modelData
                    width: parent.width
                    text: modelData.label
                    iconName: modelData.icon
                    selected: app.path === modelData.path
                    onClicked: app.go(modelData.path)
                }
            }
        }

        // The storage: how much is used.
        Column {
            x: 18
            width: parent.width - 36
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 6
            readonly property var usage: Files.usage()
            ProgressBar { width: parent.width; value: parent.usage.total > 0 ? 1 - parent.usage.free / parent.usage.total : 0 }
            Text {
                text: qsTr("%1 free of %2").arg(app.sizeText(parent.usage.free)).arg(app.sizeText(parent.usage.total))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
        }
    }
    Rectangle { x: sidebar.width; width: 1; height: parent.height; color: Theme.separator }

    // ---- toolbar ---------------------------------------------------------------------------------
    Item {
        id: toolbar
        x: sidebar.width + 1
        width: parent.width - x
        height: 50

        // The strip on top is the window's grip: nothing of ours is there.
        Row {
            x: 14
            y: 10
            spacing: 4
            ToolButton { iconName: "chevron-left"; enabled: app.historyIndex > 0; onClicked: app.back() }
            ToolButton { iconName: "chevron-right"; enabled: app.historyIndex < app.history.length - 1; onClicked: app.forward() }
            ToolButton { iconName: "arrow-up"; enabled: !app.inRecent && app.path !== Files.home; onClicked: app.up() }
        }
        Text {
            x: 130
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(80, parent.width - 130 - 350)
            elide: Text.ElideLeft
            text: app.inRecent ? qsTr("Recent") : app.path === Files.home ? qsTr("Home") : app.path.slice(app.path.lastIndexOf("/") + 1)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 8
            spacing: 6
            ToolButton { iconName: "add-circle"; onClicked: app.newFolder() }
            ToolButton { iconName: "grid"; checked: app.gridView; onClicked: Settings.setValue("files.grid", !app.gridView) }
            Rectangle {
                width: 190; height: 34; radius: 17
                color: Theme.surfaceRaised
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 16; color: Theme.textTertiary }
                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 34
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.text
                    clip: true
                    onTextChanged: { app.query = text.trim(); app.reload() }
                    Keys.onEscapePressed: { text = ""; app.forceActiveFocus() }
                    Text { visible: !parent.text; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: qsTr("Search"); font: parent.font; color: Theme.textTertiary }
                }
            }
        }
    }
    Rectangle { x: sidebar.width + 1; y: toolbar.height; width: parent.width - x; height: 1; color: Theme.separator }

    // ---- the folder ----------------------------------------------------------------------------------
    Item {
        id: content
        x: sidebar.width + 1
        y: toolbar.height + 1
        width: parent.width - x
        height: parent.height - y - 28
        clip: true

        // Empty area: clears the selection; right click: the folder's menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (m) => { app.forceActiveFocus(); app.renaming = ""; if (m.button === Qt.LeftButton) app.selected = ({}) }
            onClicked: (m) => { if (m.button === Qt.RightButton) { app.selected = ({}); menu.target = null; menu.popup(m.x + content.x, m.y + content.y, app.menuFor(null)) } }
        }

        EmptyState {
            visible: app.granted && app.entries.length === 0
            anchors.centerIn: parent
            iconName: "folder"
            title: app.query ? qsTr("No results") : qsTr("This folder is empty")
        }
        EmptyState {
            visible: !app.granted
            anchors.centerIn: parent
            iconName: "lock"
            title: qsTr("Files needs access to your files")
        }

        // List: name, modified, size, kind.
        ListView {
            id: list
            visible: !app.gridView
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            model: app.entries
            clip: true
            header: Item {
                width: list.width
                height: 30
                Row {
                    anchors.fill: parent
                    leftPadding: 44
                    Text { width: parent.width - 44 - 160 - 90 - 90; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
                    Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Modified"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
                    Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Size"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
                    Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Kind"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
                }
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: !!app.selected[modelData.path]
                width: ListView.view.width
                height: 36
                radius: Theme.radiusSmall
                color: isSelected ? Theme.accent : hover.hovered ? Theme.surfaceRaised : "transparent"
                Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: app.iconFor(row.modelData); size: 20
                       color: row.isSelected ? Theme.accentText : Theme.accent }
                Loader {
                    x: 44
                    width: parent.width - 44 - 160 - 90 - 90
                    height: parent.height
                    sourceComponent: app.renaming === row.modelData.path ? renameField : nameText
                    property var entry: row.modelData
                    property bool lit: row.isSelected
                }
                Text { x: parent.width - 340; width: 160; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                       text: app.dateText(row.modelData.modified); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                       color: row.isSelected ? Theme.accentText : Theme.textSecondary }
                Text { x: parent.width - 180; width: 90; anchors.verticalCenter: parent.verticalCenter
                       text: row.modelData.dir ? "" : app.sizeText(row.modelData.size); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                       color: row.isSelected ? Theme.accentText : Theme.textSecondary }
                Text { x: parent.width - 90; width: 90; anchors.verticalCenter: parent.verticalCenter
                       text: app.kindText(row.modelData); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                       color: row.isSelected ? Theme.accentText : Theme.textSecondary }
                HoverHandler { id: hover }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (m) => { app.forceActiveFocus(); if (m.button === Qt.RightButton && row.isSelected) return; app.select(row.modelData, m.modifiers) }
                    onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) app.open(row.modelData) }
                    onClicked: (m) => { if (m.button === Qt.RightButton) { menu.target = row.modelData; menu.popup(m.x + row.x + content.x + list.anchors.leftMargin, row.y - list.contentY + m.y + content.y + 30, app.menuFor(row.modelData)) } }
                }
            }
        }

        // Icons.
        GridView {
            id: grid
            visible: app.gridView
            anchors.fill: parent
            anchors.margins: 12
            cellWidth: 118
            cellHeight: 112
            model: app.entries
            clip: true
            delegate: Item {
                id: cell
                required property var modelData
                readonly property bool isSelected: !!app.selected[modelData.path]
                width: grid.cellWidth
                height: grid.cellHeight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Theme.radius
                    color: cell.isSelected ? Theme.accent : cellHover.hovered ? Theme.surfaceRaised : "transparent"
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 8
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: app.iconFor(cell.modelData); size: 44
                               color: cell.isSelected ? Theme.accentText : Theme.accent }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; maximumLineCount: 1
                               text: cell.modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                               color: cell.isSelected ? Theme.accentText : Theme.text }
                    }
                }
                HoverHandler { id: cellHover }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (m) => { app.forceActiveFocus(); if (m.button === Qt.RightButton && cell.isSelected) return; app.select(cell.modelData, m.modifiers) }
                    onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) app.open(cell.modelData) }
                    onClicked: (m) => { if (m.button === Qt.RightButton) { menu.target = cell.modelData; menu.popup(m.x + cell.x + grid.anchors.margins + content.x, m.y + cell.y - grid.contentY + grid.anchors.margins + content.y, app.menuFor(cell.modelData)) } }
                }
            }
        }
    }

    // ---- status ------------------------------------------------------------------------------------
    Rectangle { x: sidebar.width + 1; y: parent.height - 28; width: parent.width - x; height: 28; color: Theme.surface
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            text: app.selectedPaths.length > 0 ? qsTr("%1 of %n items selected", "", app.entries.length).arg(app.selectedPaths.length) : qsTr("%n items", "", app.entries.length)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.footnoteSize
            color: Theme.textSecondary
        }
    }

    Component { id: nameText
        Text {
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            text: entry.name
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: lit ? Theme.accentText : Theme.text
        }
    }
    Component { id: renameField
        Rectangle {
            color: Theme.surface
            radius: 8
            border.width: 2
            border.color: Theme.accent
            TextInput {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: entry.name
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
                Component.onCompleted: { forceActiveFocus(); selectAll() }
                onAccepted: app.commitRename(entry, text.trim())
                onActiveFocusChanged: if (!activeFocus && app.renaming === entry.path) app.commitRename(entry, text.trim())
                Keys.onEscapePressed: { app.renaming = ""; app.forceActiveFocus() }
            }
        }
    }

    ContextMenu {
        id: menu
        anchors.fill: parent
        property var target: null
        onTriggered: (id) => app.run(id, target)
    }

    ShareSheet { id: share }
}
