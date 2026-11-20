// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Disk Utility (the recovery environment of the live ISO): the disks and their volumes in a sidebar, what is selected on
// the right with its size, format and what it is used for, and the things to do: erase (format), add a partition in the
// free space, delete a partition, mount and unmount. Every change asks first and says what it destroys. The disk the system
// is running from can not be touched. The work is astrad's installer service (astra.permission.MANAGE_DISKS).
Rectangle {
    id: app
    color: Theme.background

    property var disks: []
    property string selectedPath: ""
    property bool busy: false
    property string message: ""
    readonly property var formats: [
        { id: "ext4", label: qsTr("Linux (ext4)") },
        { id: "fat32", label: qsTr("FAT32 (compatible with everything)") },
        { id: "exfat", label: qsTr("exFAT") },
        { id: "ntfs", label: qsTr("NTFS (Windows)") },
        { id: "swap", label: qsTr("Swap") }
    ]
    property string format: "ext4"
    property string newName: ""

    function size(bytes) {
        if (bytes >= 1e12) return (bytes / 1e12).toFixed(2) + " TB"
        if (bytes >= 1e9) return (bytes / 1e9).toFixed(1) + " GB"
        return Math.round(bytes / 1e6) + " MB"
    }
    function refresh() {
        Installer.call("disks", {}, function(result, err) {
            if (err) { app.message = err; return }
            app.disks = result || []
            if (!find(app.selectedPath) && app.disks.length) app.selectedPath = app.disks[0].path
        })
    }
    Component.onCompleted: refresh()
    // A disk or a partition by path: { kind, item, disk }.
    function find(path) {
        for (const d of disks) {
            if (d.path === path) return { kind: "disk", item: d, disk: d }
            for (const p of d.partitions) if (p.path === path) return { kind: "partition", item: p, disk: d }
        }
        return null
    }
    readonly property var current: find(selectedPath)

    function run(call, params, then) {
        busy = true
        message = ""
        Installer.call(call, params, function(result, err) {
            app.busy = false
            if (err) app.message = err
            else if (then) then(result)
            app.refresh()
        })
    }
    function confirm(title, text, button, action) {
        Dialogs.show({ title: title, message: text, icon: "warning",
                       buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "go", label: button, style: "destructive" } ] },
                     function(b) { if (b === "go") action() })
    }
    function erase() {
        const c = current
        if (!c) return
        confirm(qsTr("Erase “%1”?").arg(c.item.name), qsTr("Everything on it (%1) is erased and cannot be recovered.").arg(size(c.item.size)), qsTr("Erase"),
                () => app.run("erase", { path: c.item.path, format: app.format, label: app.newName }))
    }
    function addPartition() {
        const c = current
        if (!c || c.kind !== "disk") return
        run("createPartition", { disk: c.item.path, size: 0, format: format, label: newName })
    }
    function remove() {
        const c = current
        if (!c || c.kind !== "partition") return
        confirm(qsTr("Delete “%1”?").arg(c.item.name), qsTr("The partition and what is in it are deleted."), qsTr("Delete"),
                () => app.run("deletePartition", { path: c.item.path }))
    }

    // ---- sidebar ----
    Rectangle {
        id: sidebar
        width: 250
        height: parent.height
        color: Theme.surface
        Flickable {
            anchors.fill: parent
            anchors.topMargin: 40
            contentHeight: col.implicitHeight + 20
            clip: true
            Column {
                id: col
                x: 10
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: app.disks
                    delegate: Column {
                        id: dgroup
                        required property var modelData
                        width: col.width
                        SidebarItem { width: parent.width; text: (dgroup.modelData.model || dgroup.modelData.name) + "  " + app.size(dgroup.modelData.size)
                                      iconName: "storage"; selected: app.selectedPath === dgroup.modelData.path; onClicked: app.selectedPath = dgroup.modelData.path }
                        Repeater {
                            model: dgroup.modelData.partitions
                            delegate: SidebarItem {
                                required property var modelData
                                x: 18
                                width: dgroup.width - 18
                                text: (modelData.label || modelData.name) + "  " + app.size(modelData.size)
                                iconName: "folder"
                                selected: app.selectedPath === modelData.path
                                onClicked: app.selectedPath = modelData.path
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle { x: sidebar.width; width: 1; height: parent.height; color: Theme.separator }

    // ---- the selected disk or volume ----
    Item {
        id: detail
        x: sidebar.width + 1
        width: parent.width - x
        height: parent.height
        visible: !!app.current
        readonly property var c: app.current

        Text { x: 28; y: 40; text: detail.c ? (detail.c.item.model || detail.c.item.label || detail.c.item.name) : ""
               font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { x: 28; y: 76; text: detail.c ? (detail.c.kind === "disk" ? qsTr("Disk") : qsTr("Volume")) + " · " + app.size(detail.c.item.size) + " · " + detail.c.item.path : ""
               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }

        // Facts.
        ListGroup {
            x: 28; y: 112
            width: parent.width - 56
            ListItem { text: qsTr("Format"); value: detail.c ? (detail.c.kind === "disk" ? (detail.c.item.partitionTable || qsTr("none")).toUpperCase() : (detail.c.item.fstype || qsTr("unknown"))) : "" }
            ListItem { text: qsTr("Mounted"); value: detail.c && detail.c.kind === "partition" ? (detail.c.item.mountpoint || qsTr("no")) : "" ; visible: !!detail.c && detail.c.kind === "partition"; height: visible ? implicitHeight : 0 }
            ListItem { text: qsTr("Free space"); value: detail.c && detail.c.kind === "disk" ? app.size(detail.c.item.free) : ""; visible: !!detail.c && detail.c.kind === "disk"; height: visible ? implicitHeight : 0 }
            ListItem { text: qsTr("In use by the system"); value: detail.c && detail.c.disk.live ? qsTr("Yes") : qsTr("No"); separator: false }
        }

        // The things to do.
        Column {
            x: 28; y: 300
            width: parent.width - 56
            spacing: 12
            enabled: !app.busy && !(detail.c && detail.c.disk.live)
            opacity: enabled ? 1 : 0.5
            Text { text: qsTr("Format"); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; font.weight: Font.DemiBold; color: Theme.textSecondary }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: app.formats
                    delegate: Rectangle {
                        required property var modelData
                        height: 34; width: fmt.implicitWidth + 28; radius: 17
                        color: app.format === modelData.id ? Theme.accent : Theme.surfaceRaised
                        Text { id: fmt; anchors.centerIn: parent; text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                               color: app.format === modelData.id ? Theme.accentText : Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: app.format = modelData.id }
                    }
                }
            }
            TextField { width: Math.min(320, parent.width); placeholder: qsTr("Name"); text: app.newName; onTextChanged: app.newName = text }
            Row {
                spacing: 10
                Button { text: qsTr("Erase..."); onClicked: app.erase() }
                Button { text: qsTr("Add Partition"); primary: false; visible: !!app.current && app.current.kind === "disk"; onClicked: app.addPartition() }
                Button { text: qsTr("Delete"); primary: false; visible: !!app.current && app.current.kind === "partition"; onClicked: app.remove() }
                Button { text: !!app.current && app.current.kind === "partition" && app.current.item.mountpoint ? qsTr("Unmount") : qsTr("Mount"); primary: false
                         visible: !!app.current && app.current.kind === "partition"
                         onClicked: app.run(app.current.item.mountpoint ? "unmount" : "mount", { path: app.current.item.path }) }
            }
            Text { visible: app.message !== ""; width: parent.width; wrapMode: Text.Wrap; text: app.message; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize }
        }
        Spinner { visible: app.busy; anchors.right: parent.right; anchors.rightMargin: 28; y: 44 }
    }
    EmptyState { visible: app.disks.length === 0; x: sidebar.width + (parent.width - sidebar.width - width) / 2; anchors.verticalCenter: parent.verticalCenter
                 iconName: "storage"; title: qsTr("No disks"); message: qsTr("Disk Utility works from the recovery environment.") }
}
