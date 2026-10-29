// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: an analog clock (small) or the time in your cities (medium).
Item {
    id: root
    property string size: "small"
    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.now = new Date() }
    readonly property var cities: (Settings.values["app.com.astra.clock.cities"] || []).slice(0, 3)

    Item {
        visible: root.size === "small"
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height); height: width
        Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
        Repeater {
            model: 12
            Rectangle {
                required property int index
                x: parent.width / 2 - 1; y: 6; width: 2; height: 8; radius: 1; color: "#3A3A3C"
                transform: Rotation { origin.x: 1; origin.y: parent.height / 2 - 6; angle: index * 30 }
            }
        }
        Rectangle {
            x: parent.width / 2 - 2; y: parent.height * 0.24; width: 4; height: parent.height * 0.26; radius: 2; color: "#1C1C1E"
            transform: Rotation { origin.x: 2; origin.y: parent.height * 0.26; angle: (root.now.getHours() % 12 + root.now.getMinutes() / 60) * 30 }
        }
        Rectangle {
            x: parent.width / 2 - 1.5; y: parent.height * 0.12; width: 3; height: parent.height * 0.38; radius: 1.5; color: "#1C1C1E"
            transform: Rotation { origin.x: 1.5; origin.y: parent.height * 0.38; angle: root.now.getMinutes() * 6 }
        }
        Rectangle {
            x: parent.width / 2 - 0.75; y: parent.height * 0.1; width: 1.5; height: parent.height * 0.4; color: "#FF7A00"
            transform: Rotation { origin.x: 0.75; origin.y: parent.height * 0.4; angle: root.now.getSeconds() * 6 }
        }
    }
    Row {
        visible: root.size !== "small"
        anchors.centerIn: parent
        spacing: 18
        Repeater {
            model: [""].concat(root.cities)
            delegate: Column {
                required property string modelData
                spacing: 4
                readonly property var z: { root.now; return modelData ? System.zone(modelData) : null }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.z ? (parent.z.city || modelData) : qsTr("Here"); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.7) }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.z ? parent.z.time : Qt.locale().toString(root.now, "HH:mm")
                    font.family: Theme.fontFamily; font.pixelSize: 26; font.weight: Font.Light; color: "white"
                }
            }
        }
    }
}
