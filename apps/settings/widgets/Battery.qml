// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Lock screen widget (small): battery level.
Item {
    BatteryGlyph {
        visible: System.batteryLevel >= 0
        anchors.centerIn: parent
        height: 17
        level: System.batteryLevel
        charging: System.charging
    }
    Text {
        visible: System.batteryLevel < 0
        anchors.centerIn: parent
        text: qsTr("No battery")
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: "white"
        opacity: 0.7
    }
}
