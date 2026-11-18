// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Tune: the music on your phone, and only that.
//  - Listen Now: recently added albums and what you play the most
//  - Library: songs, albums and artists from Music/ (Artist/Album/Track,
//    or "Artist - Title" names; cover.jpg / folder.jpg are album covers)
//  - Search, a mini player above the tabs and a full Now Playing screen
//  - Files › Open with: plays the audio files it is given
// The media session drives the lock screen player and Control Center.
Rectangle {
    id: app
    color: Theme.background

    readonly property color tint: "#FF375F"
    property bool granted: false
    property var songs: []           // [{ path, url, title, artist, album, cover, added }]
    property var queue: []
    property int index: -1
    property string tab: "listen"
    property bool shuffle: false
    property bool repeatAll: false
    readonly property var song: index >= 0 && index < queue.length ? queue[index] : null
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property real position: player.position
    readonly property real duration: player.duration
    readonly property bool active: song !== null
    readonly property var counts: Settings.values["app.com.astra.tune.plays"] || ({})

    // ---- library ------------------------------------------------------------
    function parse(e) {
        const rel = e.path.split("/Music/").pop()
        const parts = rel.split("/")
        const base = parts[parts.length - 1].replace(/\.[^.]+$/, "")
        const dash = base.indexOf(" - ")
        const title = (dash > 0 ? base.slice(dash + 3) : base).replace(/^\d+[ ._-]+/, "")
        const artist = parts.length >= 3 ? parts[parts.length - 3] : dash > 0 ? base.slice(0, dash) : qsTr("Unknown Artist")
        const album = parts.length >= 2 ? parts[parts.length - 2] : qsTr("Singles")
        const dir = e.path.slice(0, e.path.lastIndexOf("/"))
        return { path: e.path, url: e.url, title: title, artist: artist, album: album, dir: dir, added: e.modified }
    }
    function reload() {
        Application.mediaAsync(["*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.wav", "cover.jpg", "cover.png", "folder.jpg"], function(list) {
            const music = list.filter(e => e.path.indexOf("/Music/") >= 0)
            const covers = {}
            for (const e of music)
                if (/\/(cover|folder)\.(jpg|png)$/i.test(e.path))
                    covers[e.path.slice(0, e.path.lastIndexOf("/"))] = e.url
            app.covers = covers
            app.songs = music.filter(e => !/\.(jpg|png)$/i.test(e.path)).map(app.parse).sort((a, b) => a.title.localeCompare(b.title))
        })
    }
    property var covers: ({})        // album folder -> cover image url
    readonly property var albums: {
        const by = {}
        for (const s of songs) {
            const k = s.artist + "/" + s.album
            if (!by[k]) by[k] = { name: s.album, artist: s.artist, dir: s.dir, songs: [], added: 0 }
            by[k].songs.push(s)
            by[k].added = Math.max(by[k].added, new Date(s.added).getTime())
        }
        return Object.values(by)
    }
    readonly property var artists: [...new Set(songs.map(s => s.artist))].sort()
    function cover(dir) { return covers[dir] || "" }
    function artOf(s) { return !s ? "" : cover(s.dir) }

    // ---- files from Files › Open with -------------------------------------------
    function fileSong(path) {
        const base = path.slice(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")
        const dash = base.indexOf(" - ")
        return { path: path, url: "file://" + path.split("/").map(encodeURIComponent).join("/"), dir: path.slice(0, path.lastIndexOf("/")), album: "",
                 title: (dash > 0 ? base.slice(dash + 3) : base).replace(/^\d+[ ._-]+/, ""), artist: dash > 0 ? base.slice(0, dash) : "" }
    }
    function openFiles(args) {
        if (!args || args.action !== "open" || !args.files || !args.files.length) return
        const files = args.files.filter(f => /\.(mp3|wav|flac|ogg|oga|opus|m4a|aac)$/i.test(f))
        if (!files.length) return
        Permissions.request("astra.permission.MEDIA", function(ok) {
            if (!ok) return
            app.granted = true
            app.shuffle = false
            app.playList(files.map(app.fileSong), 0)
            nowPlaying.open()
        })
    }
    Connections {
        target: Application
        function onIntent(args) { app.openFiles(args) }
    }

    function playList(list, i) {
        queue = shuffle ? list.slice().sort(() => Math.random() - 0.5) : list
        playAt(shuffle ? 0 : i)
    }
    function playAt(i) {
        if (!queue.length) return
        if (i >= queue.length) { if (!repeatAll) { stopAll(); return } i = 0 }
        index = (i + queue.length) % queue.length
        const s = queue[index]
        player.source = s.url
        player.play()
        session.setArtworkImage(cover(s.dir))      // the file's own cover, if any, replaces it
        const c = Object.assign({}, counts)
        c[queue[index].path] = (c[queue[index].path] || 0) + 1
        Settings.setValue("app.com.astra.tune.plays", c)
    }
    function stopAll() { player.stop() }
    function toggle() {
        playing ? player.pause() : (active ? player.play() : playList(songs, 0))
    }
    function seek(ms) { player.setPosition(ms); session.position = ms }
    function next() { playAt(index + 1) }
    function previous() { position > 3000 ? seek(0) : playAt(index - 1) }
    function clock(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }

    Component.onCompleted: {
        Permissions.request("astra.permission.MEDIA", function(ok) {
            app.granted = !!ok
            if (!ok) return
            app.reload()
            app.openFiles(Application.args)   // started from Files › Open with
        })
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput { id: output; volume: Number(Settings.values["app.com.astra.tune.volume"] ?? 0.8) }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) app.next()
        // The song's own cover (embedded in the file) beats the folder's.
        onMetaDataChanged: {
            const art = metaData.value(MediaMetaData.CoverArtImage) || metaData.value(MediaMetaData.ThumbnailImage)
            if (art) session.setArtworkImage(art)
        }
    }
    MediaSession {
        id: session
        active: app.active
        title: !app.song ? "" : (player.metaData.stringValue(MediaMetaData.Title) || app.song.title)
        artist: !app.song ? "" : (player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist) || app.song.artist)
        album: !app.song ? "" : (player.metaData.stringValue(MediaMetaData.AlbumTitle) || app.song.album)
        duration: app.duration
        playing: app.playing
        onCommand: (action, position) => {
            switch (action) {
            case "play": player.play(); break
            case "pause": player.pause(); break
            case "toggle": app.toggle(); break
            case "next": app.next(); break
            case "previous": app.previous(); break
            case "seek": app.seek(position); break
            }
        }
    }
    Timer { interval: 5000; running: app.playing; repeat: true; onTriggered: session.position = app.position }

    // ---- pages ----------------------------------------------------------------
    PageStack {
        id: stack
        anchors.fill: parent
        anchors.bottomMargin: tabs.height + (app.active ? mini.height + 8 : 0)
        initialItem: Component {
            Item {
                ListenNow { anchors.fill: parent; visible: app.tab === "listen" }
                LibraryPage { anchors.fill: parent; visible: app.tab === "library" }
                SearchPage { anchors.fill: parent; visible: app.tab === "search" }
            }
        }
    }

    component Heading: Text { font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
    component Section: Text { width: parent ? parent.width : 0; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize - 2; font.weight: Font.Bold; color: Theme.text; topPadding: 10 }
    component AlbumTile: Column {
        id: tile
        property var album
        width: 160
        spacing: 6
        Rectangle {
            width: tile.width; height: tile.width; radius: 12
            color: Theme.surfaceRaised
            clip: true
            Icon { anchors.centerIn: parent; name: "music"; size: 44; color: Theme.textTertiary }
            Image { anchors.fill: parent; source: tile.album ? app.cover(tile.album.dir) : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(320, 320); visible: status === Image.Ready }
            MouseArea { anchors.fill: parent; onClicked: stack.open(albumPage, { album: tile.album }) }
        }
        Text { width: tile.width; elide: Text.ElideRight; text: tile.album ? tile.album.name : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.text }
        Text { width: tile.width; elide: Text.ElideRight; text: tile.album ? tile.album.artist : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
    }
    component SongRow: Item {
        id: row
        property var song
        property var list: []
        property int at: 0
        width: parent ? parent.width : 300
        height: 60
        readonly property bool current: app.song && app.song.path === (song ? song.path : "")
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Rectangle {
                width: 46; height: 46; radius: 8
                color: Theme.surfaceRaised
                clip: true
                Image { anchors.fill: parent; source: app.artOf(row.song); fillMode: Image.PreserveAspectCrop; sourceSize.height: 92; asynchronous: true; visible: status === Image.Ready }
                Icon { anchors.centerIn: parent; visible: !row.song || row.current || app.artOf(row.song) === ""; name: row.current && app.playing ? "waveform" : "music"; size: 20; color: row.current ? app.tint : Theme.textTertiary }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: row.width - 70
                Text { width: parent.width; elide: Text.ElideRight; text: row.song ? row.song.title : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: row.current ? app.tint : Theme.text }
                Text { width: parent.width; elide: Text.ElideRight; text: row.song ? row.song.artist : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; x: 58; width: parent.width - 58; height: 1; color: Theme.separator }
        MouseArea {
            anchors.fill: parent
            onClicked: app.playList(row.list, row.at)
        }
    }

    // Listen Now
    component ListenNow: Flickable {
        contentHeight: ln.height + 40
        Column {
            id: ln
            x: 20; y: Theme.statusBarHeight + 16
            width: parent.width - 40
            spacing: 12
            Heading { text: qsTr("Listen Now") }
            EmptyState {
                visible: app.songs.length === 0
                width: parent.width
                iconName: "music"
                title: app.granted ? qsTr("No Music Yet") : qsTr("Tune")
                message: app.granted ? qsTr("Copy songs to the Music folder (Artist/Album/Song.mp3) and they show up here.")
                                     : qsTr("Allow Files in Settings › Apps › Tune to play your music.")
            }
            Section { visible: app.albums.length > 0; text: qsTr("Recently Added") }
            ListView {
                visible: app.albums.length > 0
                width: parent.width
                height: 220
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                model: app.albums.slice().sort((a, b) => b.added - a.added).slice(0, 12)
                delegate: AlbumTile { required property var modelData; album: modelData }
            }
            Section { visible: topPicks.count > 0; text: qsTr("Top Picks") }
            Repeater {
                id: topPicks
                model: app.songs.filter(s => app.counts[s.path]).sort((a, b) => app.counts[b.path] - app.counts[a.path]).slice(0, 6)
                delegate: SongRow { required property var modelData; required property int index; song: modelData; list: [modelData]; at: 0 }
            }
        }
    }

    // Library
    component LibraryPage: Flickable {
        id: lib
        property string view: "songs"
        contentHeight: lc.height + 40
        Column {
            id: lc
            x: 20; y: Theme.statusBarHeight + 16
            width: parent.width - 40
            spacing: 12
            Heading { text: qsTr("Library") }
            SegmentedControl {
                width: parent.width
                model: [qsTr("Songs"), qsTr("Albums"), qsTr("Artists")]
                currentIndex: ["songs", "albums", "artists"].indexOf(lib.view)
                onActivated: (i) => lib.view = ["songs", "albums", "artists"][i]
            }
            Button {
                visible: lib.view === "songs" && app.songs.length > 0
                width: parent.width
                primary: false
                iconName: "shuffle"
                text: qsTr("Shuffle")
                onClicked: { app.shuffle = true; app.playList(app.songs, 0) }
            }
            Repeater {
                model: lib.view === "songs" ? app.songs : []
                delegate: SongRow { required property var modelData; required property int index; song: modelData; list: app.songs; at: index }
            }
            Grid {
                visible: lib.view === "albums"
                width: parent.width
                columns: 2
                spacing: 14
                Repeater {
                    model: lib.view === "albums" ? app.albums : []
                    delegate: AlbumTile { required property var modelData; album: modelData; width: (lc.width - 14) / 2 }
                }
            }
            Repeater {
                model: lib.view === "artists" ? app.artists : []
                delegate: ListItem {
                    required property string modelData
                    width: lc.width
                    text: modelData
                    iconName: "person"
                    chevron: true
                    onClicked: stack.open(albumPage, { album: { name: modelData, artist: qsTr("%n songs", "", app.songs.filter(s => s.artist === modelData).length), dir: "", songs: app.songs.filter(s => s.artist === modelData) } })
                }
            }
        }
    }

    // Search
    component SearchPage: Flickable {
        id: search
        contentHeight: sc.height + 40
        Column {
            id: sc
            x: 20; y: Theme.statusBarHeight + 16
            width: parent.width - 40
            spacing: 12
            Heading { text: qsTr("Search") }
            TextField {
                id: q
                width: parent.width
                placeholder: qsTr("Artists, songs, albums")
            }
            Repeater {
                model: q.text ? app.songs.filter(s => (s.title + " " + s.artist + " " + s.album).toLowerCase().indexOf(q.text.toLowerCase()) >= 0).slice(0, 50) : []
                delegate: SongRow { required property var modelData; song: modelData; list: [modelData]; at: 0 }
            }
        }
    }

    Component {
        id: albumPage
        Page {
            id: ap
            property var album
            title: ""
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240; height: 240; radius: 16
                color: Theme.surfaceRaised
                clip: true
                Icon { anchors.centerIn: parent; name: "music"; size: 60; color: Theme.textTertiary }
                Image { anchors.fill: parent; source: ap.album.dir ? app.cover(ap.album.dir) : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
            }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: ap.album.name; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: ap.album.artist; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: app.tint }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Button { text: qsTr("Play"); iconName: "play"; width: 150; onClicked: { app.shuffle = false; app.playList(ap.album.songs, 0) } }
                Button { text: qsTr("Shuffle"); iconName: "shuffle"; primary: false; width: 150; onClicked: { app.shuffle = true; app.playList(ap.album.songs, 0) } }
            }
            Repeater {
                model: ap.album.songs
                delegate: SongRow { required property var modelData; required property int index; song: modelData; list: ap.album.songs; at: index }
            }
        }
    }

    // ---- mini player ------------------------------------------------------------
    Rectangle {
        id: mini
        visible: app.active
        anchors.bottom: tabs.top
        anchors.bottomMargin: 8
        x: 10
        width: parent.width - 20
        height: 62
        radius: 16
        color: Theme.glassPanel
        border.color: Theme.separator
        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Rectangle {
                width: 44; height: 44; radius: 8
                color: Theme.surfaceRaised
                clip: true
                Image { anchors.fill: parent; source: app.song ? (session.artwork || app.cover(app.song.dir)) : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                Icon { anchors.centerIn: parent; name: "music"; size: 20; color: Theme.textTertiary }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: mini.width - 44 - 12 - 120
                elide: Text.ElideRight
                text: session.title || qsTr("Not Playing")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
            }
        }
        MouseArea { anchors.fill: parent; onClicked: nowPlaying.open() }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            IconButton { iconName: app.playing ? "pause" : "play"; size: 44; color: "transparent"; onClicked: app.toggle() }
            IconButton { iconName: "next"; size: 44; color: "transparent"; onClicked: app.next() }
        }
    }

    // ---- tab bar --------------------------------------------------------------------
    Rectangle {
        id: tabs
        anchors.bottom: parent.bottom
        width: parent.width
        height: 58 + Theme.homeIndicatorHeight * 0.6
        color: Theme.glassPanel
        Rectangle { width: parent.width; height: 1; color: Theme.separator }
        Row {
            y: 6
            Repeater {
                model: [{ id: "listen", icon: "play", label: qsTr("Listen Now") },
                        { id: "library", icon: "music", label: qsTr("Library") }, { id: "search", icon: "search", label: qsTr("Search") }]
                delegate: Item {
                    required property var modelData
                    readonly property bool on: app.tab === modelData.id
                    width: tabs.width / 3
                    height: 48
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; y: 2; name: parent.modelData.icon; size: 24; color: parent.on ? app.tint : Theme.textSecondary }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 30; text: parent.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 11; color: parent.on ? app.tint : Theme.textSecondary }
                    MouseArea { anchors.fill: parent; onClicked: { app.tab = parent.modelData.id; if (stack.depth > 1) stack.pop(null) } }
                }
            }
        }
    }

    // ---- Now Playing ------------------------------------------------------------------
    Rectangle {
        id: nowPlaying
        function open() { np.animateTo(1, 0) }
        function close() { np.animateTo(0, 0) }
        Spring { id: np; to: 0; response: 0.45; dampingFraction: 0.84 }
        width: parent.width
        height: parent.height
        y: (1 - np.value) * parent.height
        visible: np.value > 0.01
        z: 30
        radius: Theme.screenRadius
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(((session.title || "").length * 29 % 360) / 360, 0.45, 0.32, 1) }
            GradientStop { position: 1; color: "#0B0B0F" }
        }
        MouseArea {
            anchors.fill: parent
            property real startY
            onPressed: (m) => startY = m.y
            onReleased: (m) => { if (m.y - startY > 80) nowPlaying.close() }
        }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: Theme.statusBarHeight + 6; width: 40; height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.4) }

        // The artwork shrinks a little when paused, like a record lifting off.
        Rectangle {
            id: art
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.statusBarHeight + 50 + (1 - scale) * width / 2
            width: parent.width - 60
            height: width
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.1)
            clip: true
            scale: app.playing ? 1 : 0.82
            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
            Icon { anchors.centerIn: parent; name: "music"; size: 90; color: Qt.rgba(1, 1, 1, 0.5) }
            Image { anchors.fill: parent; source: app.song ? (session.artwork || app.cover(app.song.dir)) : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
        }
        Column {
            x: 30
            y: art.y + art.width + 26
            width: parent.width - 60
            spacing: 14
            Column {
                width: parent.width
                Text { width: parent.width; elide: Text.ElideRight; text: session.title || qsTr("Not Playing"); font.family: Theme.fontFamily; font.pixelSize: 22; font.weight: Font.Bold; color: "white" }
                Text { width: parent.width; elide: Text.ElideRight; text: session.artist; font.family: Theme.fontFamily; font.pixelSize: 18; color: Qt.rgba(1, 1, 1, 0.7) }
            }
            Slider {
                width: parent.width
                from: 0
                to: Math.max(1, app.duration)
                value: app.position
                onMoved: app.seek(value)
            }
            Row {
                width: parent.width
                Text { width: parent.width / 2; text: app.clock(app.position); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
                Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: "-" + app.clock(Math.max(0, app.duration - app.position)); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 36
                IconButton { iconName: "previous"; size: 60; color: "transparent"; onClicked: app.previous() }
                IconButton { iconName: app.playing ? "pause" : "play"; size: 76; color: "transparent"; onClicked: app.toggle() }
                IconButton { iconName: "next"; size: 60; color: "transparent"; onClicked: app.next() }
            }
            Row {
                width: parent.width
                spacing: 10
                Icon { name: "volume-off"; size: 18; anchors.verticalCenter: parent.verticalCenter; opacity: 0.7 }
                Slider {
                    width: parent.width - 56
                    fillColor: "white"
                    from: 0; to: 1
                    value: output.volume
                    onMoved: { output.volume = value; Settings.setValue("app.com.astra.tune.volume", value) }
                }
                Icon { name: "volume"; size: 18; anchors.verticalCenter: parent.verticalCenter; opacity: 0.7 }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 60
                IconButton { iconName: "shuffle"; size: 40; color: app.shuffle ? Qt.rgba(1, 1, 1, 0.25) : "transparent"; onClicked: app.shuffle = !app.shuffle }
                IconButton { iconName: "repeat"; size: 40; color: app.repeatAll ? Qt.rgba(1, 1, 1, 0.25) : "transparent"; onClicked: app.repeatAll = !app.repeatAll }
            }
        }
    }
}
