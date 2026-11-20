// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Gallery for astraOS Desktop: a sidebar (Library, Favorites, Screenshots), a grid of thumbnails that follows the size of
// the window, and a viewer over it (arrows and keys to move, Space or Esc to close, Share with PetalDrop, Delete).
Rectangle {
    id: app
    color: Theme.background
    focus: true

    readonly property var filters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp"]
    property var items: []
    property bool granted: false
    property string tab: "library"
    property int viewing: -1
    readonly property string favKey: "app.com.astra.gallery.favorites"
    readonly property var favorites: Settings.values[favKey] || []
    function isFavorite(p) { return favorites.indexOf(p) >= 0 }
    function toggleFavorite(p) { Settings.setValue(favKey, isFavorite(p) ? favorites.filter(x => x !== p) : favorites.concat([p])) }

    readonly property var shown: items.filter(i => tab === "library" || (tab === "favorites" && isFavorite(i.path)) || (tab === "screenshots" && i.path.indexOf("/Screenshots/") >= 0))
    readonly property var current: viewing >= 0 && viewing < shown.length ? shown[viewing] : null

    function reload() {
        if (!granted) return
        Application.mediaAsync(filters, function(list) { app.items = list })
    }
    Component.onCompleted: Permissions.check("astra.permission.MEDIA", function(ok) {
        app.granted = !!ok
        if (ok) app.reload()
        else Permissions.request("astra.permission.MEDIA", function(g) { app.granted = !!g; app.reload() })
    })
    Connections { target: Application; function onMediaChanged() { app.reload() } }

    function step(d) { if (shown.length) viewing = (viewing + d + shown.length) % shown.length }
    function remove() {
        const item = current
        if (!item) return
        Dialogs.show({ title: qsTr("Delete this photo?"), message: qsTr("It is removed from this computer."), icon: "trash",
                       buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "d", label: qsTr("Delete"), style: "destructive" } ] },
                     function(b) {
                         if (b !== "d" || !Application.removeMedia(item.path)) return
                         app.viewing = Math.min(app.viewing, app.shown.length - 2)
                         app.reload()
                     })
    }
    Keys.onPressed: (ev) => {
        if (viewing < 0) return
        if (ev.key === Qt.Key_Left) { step(-1); ev.accepted = true }
        else if (ev.key === Qt.Key_Right) { step(1); ev.accepted = true }
        else if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Space) { viewing = -1; ev.accepted = true }
        else if (ev.key === Qt.Key_Delete) { remove(); ev.accepted = true }
    }

    // ---- sidebar ----
    Rectangle {
        id: sidebar
        width: 200
        height: parent.height
        color: Theme.surface
        Column {
            x: 10; y: 44
            width: parent.width - 20
            spacing: 2
            Text { text: qsTr("Photos"); leftPadding: 10; bottomPadding: 4; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                   font.weight: Font.DemiBold; color: Theme.textTertiary }
            SidebarItem { width: parent.width; text: qsTr("Library"); iconName: "image"; selected: app.tab === "library"; onClicked: { app.tab = "library"; app.viewing = -1 } }
            SidebarItem { width: parent.width; text: qsTr("Favorites"); iconName: "heart"; selected: app.tab === "favorites"; onClicked: { app.tab = "favorites"; app.viewing = -1 } }
            SidebarItem { width: parent.width; text: qsTr("Screenshots"); iconName: "image"; selected: app.tab === "screenshots"; onClicked: { app.tab = "screenshots"; app.viewing = -1 } }
        }
    }
    Rectangle { x: sidebar.width; width: 1; height: parent.height; color: Theme.separator }

    // ---- the grid ----
    GridView {
        id: grid
        x: sidebar.width + 1
        y: 36
        width: parent.width - x
        height: parent.height - y
        readonly property int columns: Math.max(2, Math.floor(width / 180))
        cellWidth: width / columns
        cellHeight: cellWidth
        clip: true
        model: app.shown
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Theme.radiusSmall
                color: Theme.surfaceRaised
                clip: true
                Image {
                    anchors.fill: parent
                    source: cell.modelData.url
                    sourceSize: Qt.size(360, 360)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Icon { visible: app.isFavorite(cell.modelData.path); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
                       name: "heart"; size: 16; color: Theme.danger }
                Rectangle { anchors.fill: parent; radius: Theme.radiusSmall; color: "transparent"; border.width: hover.hovered ? 2 : 0; border.color: Theme.accent }
            }
            HoverHandler { id: hover }
            TapHandler { onTapped: { app.viewing = cell.index; app.forceActiveFocus() } }
        }
    }
    EmptyState {
        visible: app.granted && app.shown.length === 0
        x: sidebar.width + (parent.width - sidebar.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        iconName: "image"
        title: qsTr("No Photos")
    }

    // ---- the viewer ----
    Rectangle {
        anchors.fill: parent
        visible: app.current !== null
        color: "black"
        Image {
            anchors.fill: parent
            anchors.margins: 56
            source: app.current ? app.current.url : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        MouseArea { anchors.fill: parent; onClicked: app.viewing = -1 }
        // The bar: back, name, favourite, share, delete.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 36
            width: bar.width + 24; height: 46; radius: 23
            color: Theme.sheet
            Row {
                id: bar
                anchors.centerIn: parent
                spacing: 6
                ToolButton { iconName: "chevron-left"; onClicked: app.step(-1) }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 240; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                       text: app.current ? app.current.name : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
                ToolButton { iconName: "chevron-right"; onClicked: app.step(1) }
                ToolButton { iconName: "heart"; checked: !!app.current && app.isFavorite(app.current.path); onClicked: app.toggleFavorite(app.current.path) }
                ToolButton { iconName: "share"; onClicked: share.open([app.current.path], "image/*") }
                ToolButton { iconName: "trash"; onClicked: app.remove() }
                ToolButton { iconName: "close"; onClicked: app.viewing = -1 }
            }
        }
    }
    ShareSheet { id: share }
}
