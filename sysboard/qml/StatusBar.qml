// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Part of SysBoard and fixed on screen everywhere: it never moves, blurs or
// animates with the content below it.
Item {
    id: root

    property bool showClock: true

    height: Theme.statusBarHeight

    Text {
        x: 30
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        text: SystemClock.time
        font.family: Theme.fontFamily
        font.pixelSize: 17
        font.weight: Font.DemiBold
        color: "white"
        opacity: root.showClock ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        spacing: 7

        Image {
            visible: System.cellular
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/qt/qml/Astra/Controls/icons/cellular-5g.svg"
            sourceSize.height: 26
            height: 13
            fillMode: Image.PreserveAspectFit
        }
        Image {
            visible: System.wifi
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/qt/qml/Astra/Controls/icons/wifi.svg"
            sourceSize.height: 26
            height: 12.5
            fillMode: Image.PreserveAspectFit
        }
        BatteryGlyph {
            anchors.verticalCenter: parent.verticalCenter
            height: 13
            level: System.batteryLevel
            charging: System.charging
        }
    }
}
