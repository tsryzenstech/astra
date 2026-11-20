// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The bar on top of astraOS Desktop: Activities and the app in front on the left, the clock in the
// middle (it opens the Notification Center), the status on the right (it opens the Control Center).
// It is transparent over the wallpaper, as on the phone's status bar.
Item {
    id: root

    property string tint: "white"
    property string appName: ""
    property bool recording: false
    property bool locked: false
    signal activitiesClicked()
    signal clockClicked()
    signal statusClicked()
    readonly property var wifi: Network.state.wifi || {}

    height: 36

    Row {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18
        visible: !root.locked
        Text {
            visible: !Host.installer
            id: activities
            text: qsTr("Activities")
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: root.tint
            opacity: activitiesArea.pressed ? 0.6 : 1
            MouseArea { id: activitiesArea; anchors.fill: parent; anchors.margins: -8; onClicked: root.activitiesClicked() }
        }
        Text {
            visible: root.appName !== ""
            text: root.appName
            font.family: Theme.fontFamily
            font.pixelSize: 15
            color: root.tint
            opacity: 0.8
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.locked
        text: SystemClock.time
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: root.tint
        MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !root.locked; onClicked: root.clockClicked() }
    }

    // The Control Center button: a pill that lights under the pointer.
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: status.width + 22
        height: 26
        radius: 13
        color: Qt.rgba(1, 1, 1, ccArea.pressed ? 0.28 : ccArea.containsMouse ? 0.16 : 0)
        visible: !root.locked
        MouseArea { id: ccArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.statusClicked() }
    }
    Row {
        id: status
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        // Screen or microphone in use (the red pill of the design).
        Rectangle {
            visible: root.recording
            anchors.verticalCenter: parent.verticalCenter
            width: 46; height: 22; radius: 11
            color: "#FF1111"
            Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: "transparent"; border.width: 2; border.color: "white"
                        Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "white" } }
        }
        Icon {
            visible: !!(Network.state.hotspot || {}).active
            anchors.verticalCenter: parent.verticalCenter
            name: "hotspot"; size: 14; color: "#34D058"
        }
        Icon {
            visible: FocusModes.currentMode !== null
            anchors.verticalCenter: parent.verticalCenter
            name: FocusModes.currentMode ? FocusModes.currentMode.icon : ""
            size: 14
            color: FocusModes.currentMode ? FocusModes.currentMode.color : root.tint
        }
        // The status as on the phone: always there, dimmed when there is nothing to report (no battery,
        // Wi-Fi or Bluetooth off).
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "bluetooth"
            size: 14
            color: root.tint
            opacity: (Network.state.bluetooth || {}).powered ? 1 : 0.4
        }
        WifiGlyph {
            opacity: root.wifi.state === "connected" ? 1 : 0.4
            anchors.verticalCenter: parent.verticalCenter
            height: 13
            color: root.tint
            strength: root.wifi.strength || 0
            connecting: root.wifi.state === "connecting"
        }
        BatteryGlyph {
            opacity: System.batteryLevel >= 0 ? 1 : 0.4
            anchors.verticalCenter: parent.verticalCenter
            height: 14
            color: root.tint
            level: Math.max(0, System.batteryLevel)
            charging: System.charging
            showLevel: Settings.values["battery.show_percentage"] !== false && System.batteryLevel >= 0
        }
    }
    MouseArea {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: status.width + 36
        enabled: !root.locked
        onClicked: root.statusClicked()
        z: -1
    }
}
