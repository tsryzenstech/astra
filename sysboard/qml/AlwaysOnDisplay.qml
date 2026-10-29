// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Always On Display: instead of turning the panel off, the screen goes
// black with the clock, the date, the battery and the apps that have
// notifications, dimmed. Double tap (or the power button) wakes the phone.
// The content moves a few pixels every minute against burn-in.
Rectangle {
    id: root
    signal wakeRequested()
    property bool active: false

    color: "black"
    visible: opacity > 0.01
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }

    property point shift: Qt.point(0, 0)
    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root.shift = Qt.point(Math.round(Math.random() * 16 - 8), Math.round(Math.random() * 24 - 12))
    }

    Column {
        x: (parent.width - width) / 2 + root.shift.x
        y: parent.height * 0.22 + root.shift.y
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SystemClock.time
            font.family: Settings.values["lockscreen.clock_font"] || Theme.fontFamily
            font.pixelSize: 84
            font.weight: Font.Light
            color: Qt.rgba(1, 1, 1, 0.82)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SystemClock.longDate
            font.family: Theme.fontFamily
            font.pixelSize: 17
            color: Qt.rgba(1, 1, 1, 0.6)
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 18
            spacing: 10
            Repeater {
                model: Notifications
                delegate: AppIcon { required property url icon; required property int index; visible: index < 6; size: 26; source: icon; round: true; opacity: 0.7 }
            }
        }
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.shift.x
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 70
        spacing: 6
        visible: System.batteryLevel >= 0
        BatteryGlyph { anchors.verticalCenter: parent.verticalCenter; height: 12; color: Qt.rgba(1, 1, 1, 0.6); level: System.batteryLevel; charging: System.charging }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: System.charging ? qsTr("Charging • %1%").arg(System.batteryLevel) : System.batteryLevel + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.6)
        }
    }

    // Double tap anywhere wakes the phone; nothing reaches the screen below.
    MouseArea {
        anchors.fill: parent
        enabled: root.active
        onDoubleClicked: root.wakeRequested()
    }
}
