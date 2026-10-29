// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: battery level (and charging).
Item {
    id: root
    property string size: "small"
    readonly property int level: System.batteryLevel
    Item {
        anchors.centerIn: root.size === "small" ? parent : undefined
        width: 96; height: 96
        Rectangle { anchors.fill: parent; radius: 48; color: "transparent"; border.width: 8; border.color: Qt.rgba(1, 1, 1, 0.15) }
        Canvas {
            anchors.fill: parent
            property int lv: root.level
            onLvChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d"); ctx.reset()
                if (lv < 0) return
                ctx.lineWidth = 8; ctx.lineCap = "round"
                ctx.strokeStyle = System.charging ? "#34D058" : lv <= 20 ? "#FF453A" : "#34D058"
                ctx.beginPath(); ctx.arc(48, 48, 44, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * lv / 100); ctx.stroke()
            }
        }
        Icon { anchors.centerIn: parent; name: System.charging ? "flash" : "battery"; size: 28 }
    }
    Column {
        visible: root.size !== "small"
        x: 116
        anchors.verticalCenter: parent.verticalCenter
        Text { text: root.level >= 0 ? root.level + "%" : qsTr("No battery"); font.family: Theme.fontFamily; font.pixelSize: 30; font.weight: Font.Light; color: "white" }
        Text { text: System.charging ? qsTr("Charging") : qsTr("Battery"); font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.7) }
    }
}
