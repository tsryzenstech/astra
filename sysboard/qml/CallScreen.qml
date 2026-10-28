// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Incoming and ongoing calls. An incoming call takes the whole screen (also
// over the lock screen); once answered, the Phone app shows the call and
// this collapses to a green pill in the status bar area while elsewhere.
Item {
    id: root

    property var shell
    readonly property var calls: Telephony.state.calls || []
    readonly property var incoming: {
        for (const c of calls)
            if (c.state === "ringing" || c.state === "incoming")
                return c
        return null
    }
    readonly property var ongoing: {
        for (const c of calls)
            if (c.state === "active" || c.state === "dialing" || c.state === "held")
                return c
        return null
    }
    readonly property bool ringingFull: incoming !== null

    // Name of a number from the address book.
    function nameOf(number) {
        for (const c of (Contacts.state.contacts || []))
            for (const p of (c.phones || []))
                if ((p.number || p).replace(/\s/g, "") === String(number).replace(/\s/g, ""))
                    return c.name
        return ""
    }

    visible: reveal.value > 0.005
    Spring { id: reveal; to: 0; response: 0.5; dampingFraction: 0.82 }
    onRingingFullChanged: {
        reveal.animateTo(ringingFull ? 1 : 0, 0)
        if (ringingFull)
            Host.setScreenOn(true)
        if (ringingFull && Settings.values["controls.sound"] !== false)
            ringtone.play()
        else
            ringtone.stop()
    }

    SoundEffect {
        id: ringtone
        source: System.fileUrl("/system/media/audio/ringtones/" + (Settings.values["audio.ringtone"] || "Orbit") + ".wav")
        loops: SoundEffect.Infinite
        volume: Number(Settings.values["audio.ring_volume"] ?? 0.8)
    }

    Rectangle {
        anchors.fill: parent
        opacity: reveal.value
        gradient: Gradient {
            GradientStop { position: 0; color: "#0E3B2A" }
            GradientStop { position: 0.6; color: "#06110C" }
            GradientStop { position: 1; color: "#000000" }
        }
        MouseArea { anchors.fill: parent }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 130 - 40 * (1 - reveal.value)
        width: parent.width - 60
        spacing: 8
        opacity: reveal.value

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 104
            height: 104
            radius: 52
            color: Qt.rgba(1, 1, 1, 0.12)
            Text {
                anchors.centerIn: parent
                visible: !!root.incoming && root.nameOf(root.incoming.number) !== ""
                text: root.incoming ? root.nameOf(root.incoming.number).charAt(0).toUpperCase() : ""
                font.family: Theme.fontFamily
                font.pixelSize: 44
                font.weight: Font.DemiBold
                color: "white"
            }
            Icon {
                anchors.centerIn: parent
                visible: !root.incoming || root.nameOf(root.incoming.number) === ""
                name: "person"
                size: 48
            }
        }
        Item { width: 1; height: 12 }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.incoming ? (root.nameOf(root.incoming.number) || root.incoming.number) : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize + 6
            font.weight: Font.DemiBold
            color: "white"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Incoming call")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 90 - 60 * (1 - reveal.value)
        spacing: 110
        opacity: reveal.value

        Repeater {
            model: [
                { id: "decline", icon: "phone-hangup", color: "#FF3B30", label: QT_TR_NOOP("Decline") },
                { id: "accept", icon: "phone", color: "#34C759", label: QT_TR_NOOP("Accept") }
            ]
            delegate: Column {
                required property var modelData
                spacing: 10
                Rectangle {
                    width: 76
                    height: 76
                    radius: 38
                    color: modelData.color
                    scale: callArea.pressed ? 0.9 : 1
                    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                    Icon { anchors.centerIn: parent; name: modelData.icon; size: 36 }
                    SequentialAnimation on anchors.verticalCenterOffset {
                        running: modelData.id === "accept" && root.ringingFull
                        loops: Animation.Infinite
                        NumberAnimation { to: -6; duration: 300; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 0; duration: 500; easing.type: Easing.OutBounce }
                        PauseAnimation { duration: 600 }
                    }
                    MouseArea {
                        id: callArea
                        anchors.fill: parent
                        onClicked: {
                            const call = root.incoming
                            if (!call)
                                return
                            if (modelData.id === "accept") {
                                Telephony.call("accept", { id: call.id }, null)
                                // Without a PIN the phone unlocks; with one the call
                                // goes on over the lock screen.
                                if (root.shell.unlockForCall())
                                    root.shell.launch("com.astra.phone", { call: call.id }, null)
                            } else {
                                Telephony.call("hangup", { id: call.id }, null)
                            }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr(modelData.label)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize + 1
                    color: "white"
                }
            }
        }
    }
}
