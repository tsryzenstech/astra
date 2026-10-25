// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel
import Astra.Core
import Astra.Controls
import Astra.Animation

// Tune: a minimal music player. Plays the songs in /sdcard/Music and
// publishes a media session, so the lock screen player and Control Center
// show what is playing (with metadata and artwork) and can control it.
Rectangle {
    id: app
    color: Theme.background

    property int current: -1
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property string musicDir: Application.mediaDir + "/Music"

    function trackTitle(i) {
        const name = files.get(i, "fileBaseName") || ""
        const dash = name.indexOf(" - ")
        return dash > 0 ? name.slice(dash + 3) : name
    }
    function trackArtist(i) {
        const name = files.get(i, "fileBaseName") || ""
        const dash = name.indexOf(" - ")
        return dash > 0 ? name.slice(0, dash) : ""
    }
    function play(i) {
        if (files.count === 0)
            return
        current = (i + files.count) % files.count
        player.source = files.get(current, "fileUrl")
        player.play()
    }
    function toggle() {
        if (current < 0)
            play(0)
        else if (playing)
            player.pause()
        else
            player.play()
    }

    FolderListModel {
        id: files
        folder: "file://" + app.musicDir
        nameFilters: ["*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.wav"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput { volume: Settings.values["audio.volume"] ?? 0.6 }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) app.play(app.current + 1)
        onMetaDataChanged: {
            const art = metaData.value(MediaMetaData.CoverArtImage) || metaData.value(MediaMetaData.ThumbnailImage)
            session.setArtworkImage(art ? art : Qt.resolvedUrl("../icon.svg"))
        }
        onPlaybackStateChanged: session.position = position
    }

    // Published to astrad; SysBoard renders it and sends commands back.
    MediaSession {
        id: session
        active: app.current >= 0
        title: player.metaData.value(MediaMetaData.Title) || (app.current >= 0 ? app.trackTitle(app.current) : "")
        artist: player.metaData.value(MediaMetaData.ContributingArtist)
                || player.metaData.value(MediaMetaData.AlbumArtist) || (app.current >= 0 ? app.trackArtist(app.current) : "")
        album: player.metaData.value(MediaMetaData.AlbumTitle) || ""
        duration: player.duration
        playing: app.playing
        onCommand: (action, position) => {
            switch (action) {
            case "play": player.play(); break
            case "pause": player.pause(); break
            case "toggle": app.toggle(); break
            case "next": app.play(app.current + 1); break
            case "previous": player.position > 3000 ? player.setPosition(0) : app.play(app.current - 1); break
            case "seek": player.setPosition(position); session.position = position; break
            }
        }
    }
    Timer {
        // Keep the published position fresh without flooding the IPC.
        interval: 5000
        running: app.playing
        repeat: true
        onTriggered: session.position = player.position
    }

    Page {
        id: page
        anchors.fill: parent
        anchors.bottomMargin: mini.height + 24
        title: "Tune"

        Text {
            visible: files.count === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "No music yet.\nCopy songs to /sdcard/Music to listen to them here. File names like “Artist - Title.mp3” are recognised when a song has no tags."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }

        ListGroup {
            visible: files.count > 0
            Repeater {
                model: files
                delegate: ListItem {
                    required property int index
                    text: app.trackTitle(index)
                    subtitle: app.trackArtist(index)
                    textColor: index === app.current ? Theme.accent : Theme.text
                    separator: index < files.count - 1
                    onClicked: app.play(index)
                }
            }
        }
    }

    // Mini player
    Rectangle {
        id: mini
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.bottomMargin: 34
        height: 72
        radius: 36
        color: Theme.surfaceRaised
        visible: app.current >= 0

        AppIcon {
            id: cover
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            size: 52
            round: true
            source: session.artwork || Qt.resolvedUrl("../icon.svg")
            RotationAnimator on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite; running: app.playing }
        }
        Column {
            anchors.left: cover.right
            anchors.leftMargin: 12
            anchors.right: controls.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: session.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                color: "white"
            }
            Text {
                width: parent.width
                text: session.artist
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textSecondary
            }
        }
        Row {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            Icon { name: "previous"; size: 18; anchors.verticalCenter: parent.verticalCenter
                   MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: session.command("previous", -1) } }
            Icon { name: app.playing ? "pause" : "play"; size: 26; anchors.verticalCenter: parent.verticalCenter
                   MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: app.toggle() } }
            Icon { name: "next"; size: 18; anchors.verticalCenter: parent.verticalCenter
                   MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: app.play(app.current + 1) } }
        }
    }
}
