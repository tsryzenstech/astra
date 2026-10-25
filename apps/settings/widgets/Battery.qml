// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Lock screen widget (small): battery level.
Item {
    BatteryGlyph {
        anchors.centerIn: parent
        height: 17
        level: System.batteryLevel
        charging: System.charging
    }
}
