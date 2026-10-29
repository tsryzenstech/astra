// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Gallery: every photo and video on the phone, in the style of iOS Photos.
//   Library  all items, oldest at the top, newest at the bottom
//   Albums   Recents, Favorites, Screenshots, Camera, Videos and each folder
// Tap a thumbnail and it grows into the viewer.
Rectangle {
    id: app
    color: "black"

    readonly property var filters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp", "*.mp4", "*.webm", "*.mkv"]
    property var items: []          // newest first (Application.media)
    property bool granted: false
    property bool checked: false
    property string tab: "library"

    readonly property string favKey: "app.com.astra.gallery.favorites"
    readonly property var favorites: Settings.values[favKey] || []
    function isFavorite(path) { return favorites.indexOf(path) >= 0 }
    function toggleFavorite(path) {
        Settings.setValue(favKey, isFavorite(path) ? favorites.filter(p => p !== path) : favorites.concat([path]))
    }

    function reload() {
        if (granted)
            items = Application.media(filters)
    }
    function checkAccess() {
        Permissions.check("astra.permission.MEDIA", function(ok) {
            app.granted = !!ok
            app.checked = true
            app.reload()
        })
    }
    Component.onCompleted: checkAccess()
    Connections {
        target: Application
        function onMediaChanged() { app.reload() }
    }

    // Albums: smart ones first, then one per folder.
    readonly property var albums: {
        const all = items
        const out = [
            { id: "recents", title: qsTr("Recents"), items: all },
            { id: "favorites", title: qsTr("Favorites"), items: all.filter(i => app.isFavorite(i.path)) },
            { id: "screenshots", title: qsTr("Screenshots"), items: all.filter(i => i.folder.indexOf("Screenshots") >= 0) },
            { id: "camera", title: qsTr("Camera"), items: all.filter(i => i.folder.indexOf("DCIM") === 0) },
            { id: "videos", title: qsTr("Videos"), items: all.filter(i => i.video) }
        ]
        const folders = {}
        for (const i of all)
            if (i.folder && i.folder.indexOf("Screenshots") < 0 && i.folder.indexOf("DCIM") !== 0)
                (folders[i.folder] = folders[i.folder] || []).push(i)
        for (const f of Object.keys(folders).sort())
            out.push({ id: "folder:" + f, title: f.split("/").pop(), items: folders[f] })
        return out
    }

    function openViewer(list, index, fromItem) {
        viewer.open(list, index, fromItem)
    }

    // ---- no access yet ----------------------------------------------------
    Column {
        visible: app.checked && !app.granted
        anchors.centerIn: parent
        width: parent.width - 60
        spacing: 22
        EmptyState {
            iconName: "image"
            title: qsTr("Your photos, all in one place")
            message: qsTr("Allow Gallery to see the photos and videos on this phone.")
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Allow access")
            onClicked: Permissions.request("astra.permission.MEDIA", function(ok) { if (ok) app.checkAccess() })
        }
    }

    // ---- pages ----------------------------------------------------------------
    PhotoGrid {
        id: library
        anchors.fill: parent
        visible: app.granted && app.tab === "library"
        title: qsTr("Library")
        items: app.items.slice().reverse()   // oldest first, like iOS
        startAtEnd: true
        onOpened: (list, index, item) => app.openViewer(list, index, item)
    }

    AlbumsPage {
        anchors.fill: parent
        visible: app.granted && app.tab === "albums" && !albumGrid.visible
        albums: app.albums
        onAlbumOpened: (album) => {
            albumGrid.title = album.title
            albumGrid.items = album.items
            albumGrid.visible = true
        }
    }

    PhotoGrid {
        id: albumGrid
        anchors.fill: parent
        visible: false
        showBack: true
        onBack: visible = false
        onOpened: (list, index, item) => app.openViewer(list, index, item)
    }

    // ---- floating tab bar --------------------------------------------------------
    Rectangle {
        visible: app.granted && !viewer.active
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34
        width: 236
        height: 54
        radius: 27
        color: Qt.rgba(0.16, 0.16, 0.18, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        Rectangle {
            id: tabPill
            y: 5
            height: 44
            width: 110
            radius: 22
            color: Qt.rgba(1, 1, 1, 0.14)
            x: app.tab === "library" ? 5 : parent.width - width - 5
            Behavior on x { SpringNumberAnimation { preset: Motion.bouncy } }
        }
        Row {
            anchors.fill: parent
            anchors.margins: 5
            Repeater {
                model: [ { id: "library", icon: "image", label: qsTr("Library") }, { id: "albums", icon: "folder", label: qsTr("Albums") } ]
                delegate: Item {
                    required property var modelData
                    width: 113
                    height: 44
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { name: modelData.icon; size: 18; anchors.verticalCenter: parent.verticalCenter
                               color: app.tab === modelData.id ? Theme.accent : "white" }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize + 1
                            font.weight: Font.DemiBold
                            color: app.tab === modelData.id ? Theme.accent : "white"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            app.tab = modelData.id
                            albumGrid.visible = false
                        }
                    }
                }
            }
        }
    }

    Viewer {
        id: viewer
        anchors.fill: parent
        isFavorite: (p) => app.isFavorite(p)
        onToggleFavorite: (p) => app.toggleFavorite(p)
        onDeleted: app.reload()
    }
}
