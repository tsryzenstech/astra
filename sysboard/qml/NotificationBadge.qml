// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// The badge on an app's icon: how many notifications it has, in red. An
// Android app (MyDroid) always shows its badge, green, and empty with none:
// it says the app runs in the Android environment.
Rectangle {
    id: root

    property int count: 0
    property bool android: false
    property real iconSize: 62

    readonly property bool shown: count > 0 || android

    height: Math.round(iconSize * 0.36)
    width: count > 9 ? Math.max(height, number.implicitWidth + height * 0.6) : height
    radius: height / 2
    x: iconSize - width * 0.7
    y: -height * 0.3
    color: android ? "#30D158" : "#FF3B30"
    visible: scale > 0.01
    scale: shown ? 1 : 0
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
    Behavior on width { SpringNumberAnimation { preset: Motion.snappy } }

    Text {
        id: number
        anchors.centerIn: parent
        text: root.count > 99 ? "99+" : root.count > 0 ? String(root.count) : ""
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(root.height * 0.6)
        font.weight: Font.DemiBold
        color: "white"
    }
}
