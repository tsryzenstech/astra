// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Part of SysBoard and fixed on screen everywhere: it never moves, blurs or
// animates with the content below it.
Item {
    id: root

    property bool showClock: true
    // Content colour: white over wallpapers and dark apps, black over light apps.
    property color tint: "white"
    Behavior on tint { ColorAnimation { duration: 200 } }
    property bool inCall: false
    signal callPillClicked()

    readonly property var wifi: Network.state.wifi || {}
    readonly property var cell: Network.state.cellular || {}
    readonly property bool airplane: !!Network.state.airplane
    readonly property int cellBars: !cell.registered ? 0 : Math.max(1, Math.min(4, Math.ceil((cell.signal || 0) / 25)))

    height: Theme.statusBarHeight

    // Clock, or a green pill with the clock during a call.
    Rectangle {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        width: clock.implicitWidth + 24
        height: 26
        radius: 13
        color: "#30D158"
        opacity: root.inCall ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; enabled: root.inCall; onClicked: root.callPillClicked() }
    }
    Text {
        id: clock
        x: 30
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        text: SystemClock.time
        font.family: Theme.fontFamily
        font.pixelSize: 17
        font.weight: Font.DemiBold
        color: root.inCall ? "white" : root.tint
        opacity: root.showClock || root.inCall ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        spacing: 7

        // Focus (moon, bed, briefcase...) and Personal Hotspot
        Icon {
            visible: FocusModes.currentMode !== null
            anchors.verticalCenter: parent.verticalCenter
            name: FocusModes.currentMode ? FocusModes.currentMode.icon : ""
            size: 14
            color: FocusModes.currentMode ? FocusModes.currentMode.color : root.tint
        }
        Icon {
            visible: !!(Network.state.hotspot || {}).active
            anchors.verticalCenter: parent.verticalCenter
            name: "hotspot"
            size: 14
            color: "#34D058"
        }
        Icon {
            visible: root.airplane
            anchors.verticalCenter: parent.verticalCenter
            name: "airplane"
            size: 15
            color: root.tint
        }
        CellularGlyph {
            visible: !root.airplane && !!root.cell.available && !!root.cell.simPresent
            anchors.verticalCenter: parent.verticalCenter
            barHeight: 11
            color: root.tint
            bars: root.cellBars
            // The technology only shows when mobile data is in use.
            technology: root.cell.dataConnected && !(root.wifi.state === "connected") ? (root.cell.technology || "") : ""
        }
        WifiGlyph {
            visible: !!root.wifi.powered && (root.wifi.state === "connected" || root.wifi.state === "connecting")
            anchors.verticalCenter: parent.verticalCenter
            height: 12.5
            color: root.tint
            strength: root.wifi.strength || 0
            connecting: root.wifi.state === "connecting"
        }
        BatteryGlyph {
            visible: System.batteryLevel >= 0
            anchors.verticalCenter: parent.verticalCenter
            height: 13
            color: root.tint
            level: System.batteryLevel
            charging: System.charging
            showLevel: Settings.values["battery.show_percentage"] !== false
        }
    }
}
