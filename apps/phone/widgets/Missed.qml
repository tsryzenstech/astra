// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Lock screen widget (small): missed calls.
Item {
    Column {
        anchors.centerIn: parent
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "phone"; size: 20 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "0"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "white"
        }
    }
}
