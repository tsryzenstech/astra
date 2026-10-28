// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Sound: silent mode, volumes, ringtone, notification and alarm sounds.
Page {
    id: page
    title: qsTr("Sound")

    // Sound names are the file names in /system/media/audio/<kind>/.
    function sounds(kind) {
        return System.files("/system/media/audio/" + kind, ["*.wav", "*.ogg"])
                     .map(p => p.split("/").pop().replace(/\.(wav|ogg)$/, ""))
    }

    ListGroup {
        SwitchRow {
            text: qsTr("Sound")
            subtitle: qsTr("Off: the phone is silent except for alarms.")
            iconName: "sound"
            key: "controls.sound"
            fallback: true
            separator: false
        }
    }

    ListGroup {
        title: qsTr("Volume")
        SliderRow { text: qsTr("Media"); iconName: "music"; key: "audio.volume"; fallback: 0.6 }
        SliderRow { text: qsTr("Ringtone"); iconName: "phone"; key: "audio.ring_volume"; fallback: 0.8 }
        SliderRow { text: qsTr("Notifications"); iconName: "notification"; key: "audio.notification_volume"; fallback: 0.7 }
        SliderRow { text: qsTr("Alarms"); iconName: "alarm"; key: "audio.alarm_volume"; fallback: 0.8; separator: false }
    }

    ListGroup {
        title: qsTr("Sounds")
        ListItem {
            text: qsTr("Ringtone")
            value: Settings.values["audio.ringtone"] || "Orbit"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Ringtone"), key: "audio.ringtone",
                options: page.sounds("ringtones").map(t => ({ value: t, label: t })) })
        }
        ListItem {
            text: qsTr("Notification sound")
            value: Settings.values["audio.notification_sound"] || "Pop"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Notification sound"), key: "audio.notification_sound",
                options: page.sounds("notifications").map(t => ({ value: t, label: t })) })
        }
        ListItem {
            text: qsTr("Alarm sound")
            value: Settings.values["clock.alarm_sound"] || "Blossom"
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Alarm sound"), key: "clock.alarm_sound",
                options: page.sounds("alarms").map(t => ({ value: t, label: t })) })
        }
    }
}
