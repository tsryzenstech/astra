// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Full screen alarm / finished timer, over everything including the lock
// screen. Slide or tap Stop to dismiss; Snooze for alarms.
Item {
    id: root

    readonly property var ringing: Alarms.state.ringing || null
    readonly property bool active: !!ringing && !!ringing.kind

    visible: reveal.value > 0.005
    Spring { id: reveal; to: root.active ? 1 : 0; response: 0.5; dampingFraction: 0.8 }
    onActiveChanged: {
        reveal.animateTo(active ? 1 : 0, 0)
        if (active)
            Host.setScreenOn(true)
    }

    SoundEffect {
        id: tone
        source: System.fileUrl("/system/media/audio/alarms/" + (Settings.values["clock.alarm_sound"] || "Blossom") + ".wav")
        loops: SoundEffect.Infinite
        volume: Math.max(0.3, Number(Settings.values["audio.alarm_volume"] ?? 0.8))
        Component.onCompleted: if (root.active) play()
    }
    Connections {
        target: root
        function onActiveChanged() { root.active ? tone.play() : tone.stop() }
    }

    Rectangle {
        anchors.fill: parent
        opacity: reveal.value
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(Theme.accentDeep, 2.2) }
            GradientStop { position: 0.55; color: "#0B0B10" }
            GradientStop { position: 1; color: "#000000" }
        }
        MouseArea { anchors.fill: parent }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 150 - 40 * (1 - reveal.value)
        width: parent.width - 60
        spacing: 10
        opacity: reveal.value

        // Pulsing glyph
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 92
            height: 92
            radius: 46
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accentDeep }
            }
            Icon { anchors.centerIn: parent; name: root.ringing && root.ringing.kind === "timer" ? "timer" : "alarm"; size: 46 }
            SequentialAnimation on scale {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation { to: 1.08; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
            }
        }
        Item { width: 1; height: 16 }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: SystemClock.time
            font.family: Theme.fontFamily
            font.pixelSize: 84
            font.weight: Font.Light
            color: "white"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: !root.ringing ? "" : root.ringing.label ? root.ringing.label
                  : root.ringing.kind === "timer" ? qsTr("Time's up") : qsTr("Alarm")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize
            font.weight: Font.DemiBold
            color: "white"
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 70 - 60 * (1 - reveal.value)
        spacing: 16
        opacity: reveal.value

        Rectangle {
            visible: root.ringing && root.ringing.kind === "alarm"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            height: 56
            radius: 28
            color: Qt.rgba(1, 1, 1, snoozeArea.pressed ? 0.24 : 0.14)
            Text {
                anchors.centerIn: parent
                text: qsTr("Snooze")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.DemiBold
                color: "white"
            }
            MouseArea { id: snoozeArea; anchors.fill: parent; onClicked: Alarms.call("snooze", {}, null) }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            height: 56
            radius: 28
            color: stopArea.pressed ? Theme.accentDeep : Theme.accent
            scale: stopArea.pressed ? 0.95 : 1
            Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
            Text {
                anchors.centerIn: parent
                text: qsTr("Stop")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.Bold
                color: "white"
            }
            MouseArea { id: stopArea; anchors.fill: parent; onClicked: Alarms.call("dismiss", {}, null) }
        }
    }
}
