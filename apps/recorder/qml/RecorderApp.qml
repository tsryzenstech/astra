// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Recorder: voice memos in Recordings/ on the shared storage. Record,
// play back (scrub, skip 15 s, speed), rename, share and delete.
Rectangle {
    id: app
    color: Theme.background

    property bool granted: false
    readonly property string folder: Files.home + "/Recordings"
    property var recordings: []         // Files entries, newest first
    property string playing: ""         // path
    property int elapsed: 0             // recording time, seconds
    property string error: ""

    function reload() {
        recordings = Files.list(folder).filter(e => !e.dir && /\.(m4a|mp4|ogg|wav|aac|mp3)$/i.test(e.name))
                                       .sort((a, b) => b.modified - a.modified)
    }
    function clock(ms) {
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function nextName() {
        let n = 1
        while (recordings.some(r => r.name.replace(/\.[^.]+$/, "") === qsTr("New Recording %1").arg(n))) n++
        return qsTr("New Recording %1").arg(n)
    }
    function start() {
        Files.mkdir(Files.home, "Recordings")
        recorder.outputLocation = "file://" + folder + "/" + nextName() + ".m4a"
        elapsed = 0
        recorder.record()
    }
    function stop() {
        recorder.stop()
        reloadTimer.start()
    }
    Timer { id: reloadTimer; interval: 600; onTriggered: app.reload() }

    Component.onCompleted: Permissions.request("astra.permission.MICROPHONE", function(mic) {
        Permissions.request("astra.permission.MEDIA", function(media) {
            app.granted = !!mic && !!media
            if (media) app.reload()
        })
    })

    CaptureSession {
        audioInput: AudioInput {}
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            mediaFormat {
                fileFormat: MediaFormat.Mpeg4Audio
                audioCodec: MediaFormat.AudioCodec.AAC
            }
            onErrorOccurred: (error, text) => app.error = text
        }
    }
    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
    Timer { interval: 1000; repeat: true; running: app.recording; onTriggered: app.elapsed++ }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) app.playing = ""
    }

    PageStack {
        id: stack
        anchors.fill: parent
        anchors.bottomMargin: recordBar.height
        Component.onCompleted: open(listPage)
    }

    Component {
        id: listPage
        Page {
            title: qsTr("All Recordings")
            EmptyState {
                visible: app.recordings.length === 0
                iconName: "mic"
                title: app.granted ? qsTr("No Recordings") : qsTr("Recorder")
                message: app.granted ? qsTr("Tap the record button to start.") : qsTr("Allow the microphone and Files in Settings › Apps › Recorder.")
            }
            Text { visible: app.error !== ""; text: app.error; width: parent.width; wrapMode: Text.WordWrap; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
            Repeater {
                model: app.recordings
                delegate: Card {
                    id: card
                    required property var modelData
                    readonly property bool open: app.playing === modelData.path
                    width: parent.width
                    padding: 16
                    pressable: !open
                    onClicked: {
                        app.playing = modelData.path
                        player.source = "file://" + modelData.path
                        player.play()
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.name.replace(/\.[^.]+$/, ""); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                        Text {
                            text: Qt.locale().toString(new Date(card.modelData.modified), Locale.ShortFormat) + (card.open && player.duration > 0 ? "  •  " + app.clock(player.duration) : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.footnoteSize
                            color: Theme.textSecondary
                        }
                        Column {
                            visible: card.open
                            width: parent.width
                            spacing: 8
                            Slider {
                                width: parent.width
                                from: 0
                                to: Math.max(1, player.duration)
                                value: player.position
                                onMoved: player.position = value
                            }
                            Row {
                                width: parent.width
                                Text { width: parent.width / 2; text: app.clock(player.position); font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.textSecondary }
                                Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: "-" + app.clock(Math.max(0, player.duration - player.position)); font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.textSecondary }
                            }
                            Item {
                                width: parent.width
                                height: 52
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: player.playbackRate + "×"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.footnoteSize
                                    color: Theme.accent
                                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: player.playbackRate = player.playbackRate >= 2 ? 0.5 : player.playbackRate + 0.5 }
                                }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 22
                                    IconButton { iconName: "undo"; size: 44; color: "transparent"; onClicked: player.position = Math.max(0, player.position - 15000) }
                                    IconButton {
                                        iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                                        size: 52
                                        color: Theme.accent
                                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                                    }
                                    IconButton { iconName: "redo"; size: 44; color: "transparent"; onClicked: player.position = Math.min(player.duration, player.position + 15000) }
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    IconButton { iconName: "edit"; size: 36; color: "transparent"; onClicked: rename.open(card.modelData) }
                                    IconButton { iconName: "share"; size: 36; color: "transparent"; onClicked: share.open([card.modelData.path], "audio/mp4", "share", "") }
                                    IconButton {
                                        iconName: "trash"
                                        size: 36
                                        color: "transparent"
                                        iconColor: Theme.danger
                                        onClicked: {
                                            player.stop()
                                            Files.remove([card.modelData.path])
                                            app.reload()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- record bar -----------------------------------------------------------
    Rectangle {
        id: recordBar
        anchors.bottom: parent.bottom
        width: parent.width
        height: (app.recording ? 190 : 120) + Theme.homeIndicatorHeight * 0.5
        Behavior on height { SpringNumberAnimation { preset: Motion.bouncy } }
        color: Theme.surface
        radius: Theme.sheetRadius
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            spacing: 14
            Column {
                visible: app.recording
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.nextName(); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.clock(app.elapsed * 1000); font.family: Theme.fontFamily; font.pixelSize: 28; color: Theme.text }
                // Recording pulse
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 10; height: 10; radius: 5
                    color: Theme.danger
                    SequentialAnimation on opacity {
                        running: app.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
            }
            // The record button: a red dot that turns into a square.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 70; height: 70; radius: 35
                color: "transparent"
                border.width: 4
                border.color: Theme.light ? "#C7C7CC" : "#8E8E93"
                opacity: app.granted ? 1 : 0.4
                Rectangle {
                    anchors.centerIn: parent
                    width: app.recording ? 28 : 56
                    height: width
                    radius: app.recording ? 6 : 28
                    color: "#FF3B30"
                    Behavior on width { SpringNumberAnimation { preset: Motion.bouncy } }
                    Behavior on radius { SpringNumberAnimation { preset: Motion.bouncy } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: app.granted
                    onClicked: {
                        player.stop()
                        app.recording ? app.stop() : app.start()
                    }
                }
            }
        }
    }

    // Rename
    Item {
        id: rename
        property var entry
        anchors.fill: parent
        z: 60
        visible: false
        function open(e) { entry = e; nameField.text = e.name.replace(/\.[^.]+$/, ""); visible = true; nameField.focusInput() }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: rename.visible = false } }
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -120
            width: parent.width - 60
            height: col.height + 36
            radius: Theme.cardRadius
            color: Theme.sheet
            Column {
                id: col
                x: 18; y: 18
                width: parent.width - 36
                spacing: 14
                Text { text: qsTr("Rename"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                TextField { id: nameField; width: parent.width }
                Button {
                    width: parent.width
                    text: qsTr("Save")
                    enabled: nameField.text.trim() !== ""
                    onClicked: {
                        const ext = rename.entry.name.slice(rename.entry.name.lastIndexOf("."))
                        player.stop()
                        Files.rename(rename.entry.path, nameField.text.trim().replace(/[\/\\]/g, "-") + ext)
                        rename.visible = false
                        app.reload()
                    }
                }
            }
        }
    }

    ShareSheet { id: share }
}
