// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Push notifications: a new notification drops in under the status bar
// with a bouncy spring, stays for a few seconds and goes back up. Tap it to
// open the app, swipe it up to put it away (it stays in Notification
// Center). Not shown while Notification Center is open, on the lock screen
// or with Do Not Disturb on.
Item {
    id: root

    property var shell
    property bool suppressed: false
    property var current: null
    property var pending: []

    width: parent.width
    height: card.height + Theme.statusBarHeight + 10
    visible: drop.value > 0.005

    Spring { id: drop; to: 0; response: 0.5; dampingFraction: 0.66 }
    Spring { id: pull; to: 0; response: 0.3; dampingFraction: 0.9 }

    SoundEffect {
        id: chime
        source: System.fileUrl("/system/media/audio/notifications/" + (Settings.values["audio.notification_sound"] || "Pop") + ".wav")
        volume: Number(Settings.values["audio.notification_volume"] ?? 0.7)
    }

    function present(n) {
        current = n
        if (Settings.values["controls.sound"] !== false)
            chime.play()
        pull.snap(0)
        drop.snap(0)
        drop.animateTo(1, 0)
        hideTimer.restart()
    }
    function hide() {
        hideTimer.stop()
        drop.animateTo(0, 0)
        nextTimer.restart()
    }
    Timer { id: hideTimer; interval: 4500; onTriggered: if (!area.pressed) root.hide() }
    Timer {
        id: nextTimer
        interval: 420
        onTriggered: {
            root.current = null
            if (root.pending.length) {
                const n = root.pending[0]
                root.pending = root.pending.slice(1)
                root.present(n)
            }
        }
    }

    Connections {
        target: Notifications
        function onPosted(id) {
            if (root.suppressed || Settings.values["controls.dnd"])
                return
            const n = Notifications.get(id)
            if (!n || !n.notificationId)
                return
            if (root.current)
                root.pending = root.pending.concat([n]).slice(-3)
            else
                root.present(n)
        }
    }
    onSuppressedChanged: if (suppressed && current) hide()

    Rectangle {
        id: card
        x: 10
        width: parent.width - 20
        height: 76
        y: Theme.statusBarHeight + 2 - (1 - drop.value) * (height + Theme.statusBarHeight + 20) + Math.min(0, pull.value)
        radius: height / 2
        color: Qt.rgba(0.1, 0.1, 0.12, 0.94)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        scale: area.pressed ? 0.97 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

        AppIcon {
            id: art
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            size: 52
            round: true
            source: root.current ? root.current.icon : ""
        }
        Column {
            anchors.left: art.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Row {
                spacing: 6
                Text {
                    id: appText
                    text: root.current ? root.current.appName : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.weight: Font.Bold
                    color: "white"
                }
                Text {
                    anchors.baseline: appText.baseline
                    text: qsTr("now")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize + 1
                    color: Theme.textSecondary
                }
            }
            Text {
                width: parent.width
                text: root.current ? (root.current.title + (root.current.body ? " · " + root.current.body : "")) : ""
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Qt.rgba(1, 1, 1, 0.88)
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            property real startY
            property bool moved: false
            onPressed: (m) => {
                startY = m.y
                moved = false
            }
            onPositionChanged: (m) => {
                const dy = m.y - startY
                if (Math.abs(dy) > 8)
                    moved = true
                pull.value = dy < 0 ? dy : Motion.rubberband(dy, 120)
            }
            onReleased: {
                if (pull.value < -24) {
                    root.hide()
                } else if (!moved && root.current) {
                    const n = root.current
                    root.hide()
                    root.shell.launch(n.packageName, { notification: n.notificationId }, null)
                } else {
                    pull.animateTo(0, 0)
                    hideTimer.restart()
                }
            }
        }
    }
}
