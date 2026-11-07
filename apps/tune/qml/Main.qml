// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Tune: your music and internet radio.
//  - Listen Now: recently added albums and what you play the most
//  - Radio: live stations (radio-browser.info, a free community directory)
//  - Library: songs, albums and artists from Music/ (Artist/Album/Track,
//    or "Artist - Title" names; cover.jpg / folder.jpg are album covers)
//  - YouTube Music: search and play YouTube's music catalogue. Search uses
//    the YouTube Data API v3 with the user's own API key; songs play in
//    YouTube's embedded player (YouTubePlayer.qml), shown in Now Playing.
//  - Search, a mini player above the tabs and a full Now Playing screen
//  - Files › Open with: plays the audio files it is given
// The media session drives the lock screen player and Control Center.
Rectangle {
    id: app
    color: Theme.background

    readonly property color tint: "#FF375F"
    property bool granted: false
    property var songs: []           // [{ path, url, title, artist, album, cover, added }]
                                     // YouTube songs: { path: "yt:<id>", yt: id, title, artist, album: "", thumb }
    property var queue: []
    property int index: -1
    property var station: null      // the radio station playing, if any
    property string tab: "listen"
    property bool shuffle: false
    property bool repeatAll: false
    readonly property var song: station ? null : (index >= 0 && index < queue.length ? queue[index] : null)
    readonly property var yt: ytLoader.item                 // the YouTube player, once loaded
    readonly property bool ytMode: song !== null && !!song.yt
    readonly property bool playing: ytMode ? !!(yt && (yt.playing || yt.buffering)) : player.playbackState === MediaPlayer.PlayingState
    readonly property real position: ytMode ? (yt ? yt.position : 0) : player.position
    readonly property real duration: ytMode ? (yt ? yt.duration : 0) : player.duration
    readonly property bool active: song !== null || station !== null
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
    function artOf(s) { return !s ? "" : s.thumb ? s.thumb : cover(s.dir) }

    // ---- YouTube Music ------------------------------------------------------------
    // The key is the user's own (Google Cloud › YouTube Data API v3) and
    // stays in Tune's private folder. Each search costs 100 of the 10,000
    // daily quota units Google gives a key for free.
    property string ytKey: ""
    property bool ytWanted: false                      // load the player even without a key (queue from Recents)
    property string ytStatus: ""
    readonly property string ytKeyFile: Files.appData + "/youtube-api-key"
    readonly property var ytRecent: Settings.values["app.com.astra.tune.ytRecent"] || []
    function setYtKey(key) {
        ytKey = key.trim()
        Files.writeText(ytKeyFile, ytKey)
    }
    function decodeHtml(t) {
        return (t || "").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }
    // "Artist - Topic" channels carry the album tracks: the title is the
    // song. Elsewhere titles are usually "Artist - Song (Official Video)".
    function ytSong(item) {
        const id = item.id.videoId
        let title = decodeHtml(item.snippet.title)
        const channel = decodeHtml(item.snippet.channelTitle)
        let artist = channel.replace(/ - Topic$/, "").replace(/VEVO$/, "").trim()
        if (!/ - Topic$/.test(channel)) {
            const dash = title.indexOf(" - ")
            if (dash > 0) { artist = title.slice(0, dash).trim(); title = title.slice(dash + 3) }
        }
        title = title.replace(/\s*[([](official|lyrics?|audio|video|music video|visuali[sz]er|hd|hq|4k|testo)[^)\]]*[)\]]/gi, "").trim()
        return { path: "yt:" + id, yt: id, title: title, artist: artist, album: "", dir: "",
                 thumb: "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg" }
    }
    function ytSearch(query, done) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            let r = null
            try { r = JSON.parse(xhr.responseText) } catch (e) { }
            if (xhr.status === 200 && r && r.items) {
                done(r.items.filter(i => i.id && i.id.videoId).map(app.ytSong), "")
                return
            }
            const reason = r && r.error && r.error.errors && r.error.errors.length ? r.error.errors[0].reason : ""
            done([], reason === "quotaExceeded" || reason === "dailyLimitExceeded" ? qsTr("Today's YouTube quota for your API key is used up. It resets at midnight Pacific time.")
                   : xhr.status === 400 || xhr.status === 403 ? qsTr("YouTube refused the API key. Check it in YouTube Music settings.")
                   : qsTr("YouTube is not reachable right now."))
        }
        // Music category, only videos YouTube lets other apps embed.
        xhr.open("GET", "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10"
                 + "&videoEmbeddable=true&videoSyndicated=true&maxResults=25&q=" + encodeURIComponent(query))
        xhr.setRequestHeader("X-Goog-Api-Key", app.ytKey)  // in a header: out of URLs and logs
        xhr.send()
    }
    function rememberYt(s) {
        const list = [s].concat(ytRecent.filter(r => r.yt !== s.yt)).slice(0, 30)
        Settings.setValue("app.com.astra.tune.ytRecent", list)
    }

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
        station = null
        queue = shuffle ? list.slice().sort(() => Math.random() - 0.5) : list
        playAt(shuffle ? 0 : i)
    }
    function playAt(i) {
        if (!queue.length) return
        if (i >= queue.length) { if (!repeatAll) { stopAll(); return } i = 0 }
        index = (i + queue.length) % queue.length
        const s = queue[index]
        if (s.yt) {
            player.stop()
            ytWanted = true
            session.setArtworkImage("https://i.ytimg.com/vi/" + s.yt + "/hqdefault.jpg")
            if (yt) yt.load(s.yt)
            rememberYt(s)
        } else {
            if (yt) yt.stop()
            player.source = s.url
            player.play()
            session.setArtworkImage(cover(s.dir))      // the file's own cover, if any, replaces it
        }
        const c = Object.assign({}, counts)
        c[queue[index].path] = (c[queue[index].path] || 0) + 1
        Settings.setValue("app.com.astra.tune.plays", c)
    }
    function playStation(s) {
        if (yt) yt.stop()
        station = s
        index = -1
        player.source = s.url_resolved || s.url
        player.play()
        session.setArtworkImage(s.favicon || "")
    }
    function stopAll() { player.stop(); if (yt) yt.stop() }
    function toggle() {
        if (ytMode) { yt.playing ? yt.pause() : yt.play(); return }
        playing ? player.pause() : (active ? player.play() : playList(songs, 0))
    }
    function seek(ms) { ytMode ? (yt && yt.seek(ms)) : player.setPosition(ms); session.position = ms }
    function next() { if (!station) playAt(index + 1) }
    function previous() { if (!station) position > 3000 ? seek(0) : playAt(index - 1) }
    function clock(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }

    Component.onCompleted: {
        ytKey = Files.readText(ytKeyFile).trim()
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
            if (app.station || app.ytMode) return
            const art = metaData.value(MediaMetaData.CoverArtImage) || metaData.value(MediaMetaData.ThumbnailImage)
            if (art) session.setArtworkImage(art)
        }
    }
    // YouTube's player, loaded once YouTube Music is set up (it needs Qt
    // WebEngine: without it Tune still plays local music and radio).
    // Visible while it plays: big in Now Playing, small in the mini player.
    Loader {
        id: ytLoader
        active: app.ytKey !== "" || app.ytWanted
        source: "YouTubePlayer.qml"
        z: 31
        visible: app.ytMode && status === Loader.Ready
        readonly property bool big: np.value > 0.02
        x: big ? art.x + (1 - art.scale) * art.width / 2 : mini.x + 10
        y: big ? nowPlaying.y + art.y + (1 - art.scale) * art.height / 2 : mini.y + 9
        width: big ? art.width * art.scale : 44
        height: width
        onLoaded: {
            item.volume = output.volume
            if (app.ytMode) item.load(app.song.yt)
        }
        onStatusChanged: if (status === Loader.Error) app.ytStatus = qsTr("YouTube playback needs Qt WebEngine, which this build of astraOS lacks.")
    }
    Connections {
        target: app.yt
        function onEnded() { app.next() }
        function onFailed(code) {
            app.ytStatus = code === 101 || code === 150 ? qsTr("This song can only be played on YouTube.") : qsTr("YouTube could not play this song.")
            if (app.queue.length > 1) app.next()
        }
        function onPlayingChanged() { session.position = app.position }
    }
    MediaSession {
        id: session
        active: app.active
        title: app.station ? app.station.name : !app.song ? "" : app.song.yt ? app.song.title
               : (player.metaData.stringValue(MediaMetaData.Title) || app.song.title)
        artist: app.station ? qsTr("Live Radio") : !app.song ? "" : app.song.yt ? app.song.artist
                : (player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist) || app.song.artist)
        album: !app.song ? "" : app.song.yt ? "YouTube Music" : (player.metaData.stringValue(MediaMetaData.AlbumTitle) || app.song.album)
        duration: app.station ? 0 : app.duration
        playing: app.playing
        onCommand: (action, position) => {
            switch (action) {
            case "play": app.ytMode ? app.yt.play() : player.play(); break
            case "pause": app.ytMode ? app.yt.pause() : player.pause(); break
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
                RadioPage { anchors.fill: parent; visible: app.tab === "radio" }
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
                Icon { anchors.centerIn: parent; visible: !row.song || !row.song.thumb || row.current; name: row.current && app.playing ? "waveform" : "music"; size: 20; color: row.current ? app.tint : Theme.textTertiary }
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
            onClicked: {
                app.playList(row.list, row.at)
                // YouTube's player has to be seen: Now Playing shows it.
                if (row.song && row.song.yt) nowPlaying.open()
            }
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
                visible: app.songs.length === 0 && app.ytRecent.length === 0
                width: parent.width
                iconName: "music"
                title: app.granted ? qsTr("No Music Yet") : qsTr("Tune")
                message: app.granted ? qsTr("Copy songs to the Music folder (Artist/Album/Song.mp3) and they show up here. Or try Radio.")
                                     : qsTr("Allow Files in Settings › Apps › Tune to play your music.")
            }
            ListItem {
                visible: app.ytKey === ""
                width: parent.width
                text: qsTr("Set Up YouTube Music")
                subtitle: qsTr("Search and play YouTube's music catalogue")
                iconName: "play"
                iconTile: 32
                tileColor: "#FF0033"
                chevron: true
                onClicked: stack.open(ytSetupPage)
            }
            Section { visible: app.ytRecent.length > 0; text: qsTr("Recently Played on YouTube Music") }
            Repeater {
                model: app.ytRecent.slice(0, 6)
                delegate: SongRow { required property var modelData; required property int index; song: modelData; list: app.ytRecent; at: index }
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

    // Radio
    component RadioPage: Flickable {
        id: radio
        property var stations: []
        property bool loading: false
        property string error: ""
        function load() {
            if (stations.length || loading) return
            loading = true
            const cc = Qt.locale().name.split("_")[1] || "IT"
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                radio.loading = false
                try { radio.stations = JSON.parse(xhr.responseText).filter(s => s.url_resolved && s.codec !== "") }
                catch (e) { radio.error = qsTr("Radio is not reachable right now.") }
            }
            xhr.open("GET", "https://de1.api.radio-browser.info/json/stations/bycountrycodeexact/" + cc + "?order=clickcount&reverse=true&hidebroken=true&limit=40")
            xhr.send()
        }
        onVisibleChanged: if (visible) load()
        contentHeight: rc.height + 40
        Column {
            id: rc
            x: 20; y: Theme.statusBarHeight + 16
            width: parent.width - 40
            spacing: 10
            Heading { text: qsTr("Radio") }
            Text { text: qsTr("Live stations near you"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            Spinner { visible: radio.loading; anchors.horizontalCenter: parent.horizontalCenter }
            Text { visible: radio.error !== ""; text: radio.error; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
            Grid {
                width: parent.width
                columns: 2
                spacing: 12
                Repeater {
                    model: radio.stations
                    delegate: Rectangle {
                        required property var modelData
                        width: (rc.width - 12) / 2
                        height: 120
                        radius: 16
                        color: Qt.hsla((modelData.name.length * 37 % 360) / 360, 0.55, 0.42, 1)
                        clip: true
                        Image { x: 12; y: 12; width: 44; height: 44; source: modelData.favicon || ""; fillMode: Image.PreserveAspectFit; asynchronous: true; visible: status === Image.Ready }
                        Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; width: parent.width - 24; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; text: modelData.name.trim(); font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold; color: "white" }
                        Icon { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; visible: app.station && app.station.stationuuid === modelData.stationuuid; name: "waveform"; size: 20 }
                        MouseArea { anchors.fill: parent; onClicked: app.playStation(modelData) }
                    }
                }
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
        property string source: app.ytKey !== "" ? "youtube" : "library"
        property var results: []
        property bool loading: false
        property string error: ""
        // YouTube searches cost quota: they run on Enter, not on every key.
        function run() {
            if (source !== "youtube" || q.text.trim() === "") return
            loading = true
            error = ""
            app.ytSearch(q.text.trim(), function(list, err) { search.loading = false; search.results = list; search.error = err })
        }
        contentHeight: sc.height + 40
        Column {
            id: sc
            x: 20; y: Theme.statusBarHeight + 16
            width: parent.width - 40
            spacing: 12
            Heading { text: qsTr("Search") }
            SegmentedControl {
                visible: app.ytKey !== ""
                width: parent.width
                model: [qsTr("YouTube Music"), qsTr("Your Library")]
                currentIndex: search.source === "youtube" ? 0 : 1
                onActivated: (i) => { search.source = i === 0 ? "youtube" : "library"; search.run() }
            }
            TextField {
                id: q
                width: parent.width
                placeholder: search.source === "youtube" ? qsTr("Search YouTube Music") : qsTr("Artists, songs, albums")
                onAccepted: search.run()
            }
            Spinner { visible: search.loading; anchors.horizontalCenter: parent.horizontalCenter }
            Text { visible: search.error !== ""; width: parent.width; wrapMode: Text.Wrap; text: search.error; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
            Repeater {
                model: search.source === "youtube" ? search.results : []
                delegate: SongRow { required property var modelData; required property int index; song: modelData; list: search.results; at: index }
            }
            Repeater {
                model: search.source === "library" && q.text ? app.songs.filter(s => (s.title + " " + s.artist + " " + s.album).toLowerCase().indexOf(q.text.toLowerCase()) >= 0).slice(0, 50) : []
                delegate: SongRow { required property var modelData; song: modelData; list: [modelData]; at: 0 }
            }
            ListItem {
                width: parent.width
                text: qsTr("YouTube Music Settings")
                iconName: "settings"
                chevron: true
                onClicked: stack.open(ytSetupPage)
            }
        }
    }

    // YouTube Music setup: the user's own API key.
    Component {
        id: ytSetupPage
        Page {
            id: setup
            title: qsTr("YouTube Music")
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("YouTube has no public API for YouTube Music. Tune searches YouTube's music catalogue with the YouTube Data API v3 and plays songs in YouTube's own player, so it needs an API key of yours:")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("1. Open console.cloud.google.com and create a project.\n2. Enable “YouTube Data API v3”.\n3. Credentials › Create credentials › API key.\n4. Paste the key here.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize + 1
                color: Theme.textSecondary
                lineHeight: 1.15
            }
            TextField {
                id: keyField
                width: parent.width
                placeholder: qsTr("API key")
                echoMode: TextInput.Password
                text: app.ytKey
            }
            Button {
                width: parent.width
                text: qsTr("Save")
                enabled: keyField.text.trim() !== ""
                onClicked: { app.setYtKey(keyField.text); stack.pop() }
            }
            Button {
                visible: app.ytKey !== ""
                width: parent.width
                primary: false
                text: qsTr("Remove Key")
                onClicked: { app.setYtKey(""); keyField.text = "" }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("The key stays on this phone, in Tune's private storage. A free key allows about 100 searches a day; playing songs does not count. Your YouTube Music library and playlists are not available: YouTube offers no API for them. Like on any website, YouTube's player shows its own ads and needs to stay visible in Now Playing; some songs can only be played on YouTube itself.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
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
                Image { anchors.fill: parent; source: app.song ? (app.song.yt ? app.artOf(app.song) : (session.artwork || app.cover(app.song.dir))) : (app.station ? app.station.favicon : ""); fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                Icon { anchors.centerIn: parent; name: app.station ? "signal" : "music"; size: 20; color: Theme.textTertiary }
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
            IconButton { iconName: "next"; size: 44; color: "transparent"; opacity: app.station ? 0.3 : 1; onClicked: app.next() }
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
                model: [{ id: "listen", icon: "play", label: qsTr("Listen Now") }, { id: "radio", icon: "signal", label: qsTr("Radio") },
                        { id: "library", icon: "music", label: qsTr("Library") }, { id: "search", icon: "search", label: qsTr("Search") }]
                delegate: Item {
                    required property var modelData
                    readonly property bool on: app.tab === modelData.id
                    width: tabs.width / 4
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
            Icon { anchors.centerIn: parent; name: app.station ? "signal" : "music"; size: 90; color: Qt.rgba(1, 1, 1, 0.5) }
            Image { anchors.fill: parent; source: app.song ? (app.song.yt ? "" : (session.artwork || app.cover(app.song.dir))) : (app.station ? app.station.favicon : ""); fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
            Image { anchors.fill: parent; visible: !!app.song && !!app.song.yt && !app.yt; source: app.song && app.song.yt ? (session.artwork || "https://i.ytimg.com/vi/" + app.song.yt + "/mqdefault.jpg") : ""; fillMode: Image.PreserveAspectCrop }
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
                Text { visible: app.ytStatus !== "" && app.ytMode; width: parent.width; wrapMode: Text.Wrap; text: app.ytStatus; font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
            }
            Slider {
                visible: !app.station
                width: parent.width
                from: 0
                to: Math.max(1, app.duration)
                value: app.position
                onMoved: app.seek(value)
            }
            Row {
                visible: !app.station
                width: parent.width
                Text { width: parent.width / 2; text: app.clock(app.position); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
                Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: "-" + app.clock(Math.max(0, app.duration - app.position)); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
            }
            Text { visible: !!app.station; text: "● " + qsTr("LIVE"); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold; color: app.tint }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 36
                IconButton { iconName: "previous"; size: 60; color: "transparent"; opacity: app.station ? 0.3 : 1; onClicked: app.previous() }
                IconButton { iconName: app.playing ? "pause" : "play"; size: 76; color: "transparent"; onClicked: app.toggle() }
                IconButton { iconName: "next"; size: 60; color: "transparent"; opacity: app.station ? 0.3 : 1; onClicked: app.next() }
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
                    onMoved: { output.volume = value; if (app.yt) app.yt.volume = value; Settings.setValue("app.com.astra.tune.volume", value) }
                }
                Icon { name: "volume"; size: 18; anchors.verticalCenter: parent.verticalCenter; opacity: 0.7 }
            }
            Row {
                visible: !app.station
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 60
                IconButton { iconName: "shuffle"; size: 40; color: app.shuffle ? Qt.rgba(1, 1, 1, 0.25) : "transparent"; onClicked: app.shuffle = !app.shuffle }
                IconButton { iconName: "repeat"; size: 40; color: app.repeatAll ? Qt.rgba(1, 1, 1, 0.25) : "transparent"; onClicked: app.repeatAll = !app.repeatAll }
            }
        }
    }
}
