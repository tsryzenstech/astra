// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// What iOS shows when the charger is plugged in: the screen wakes, a ring springs in the middle of
// a blurred, darkened screen, a lightning bolt lights up, and the ring fills to the battery level
// with the percentage counting up. It tucks itself away after a moment, and the phone goes back
// to sleep if it was asleep.
Item {
    id: root

    property Item blurSource: null
    property bool wokeTheScreen: false
    readonly property int level: Math.max(0, Math.min(100, System.batteryLevel))
    property real shown: 0           // 0..1, the whole thing's presence
    property real ring: 0            // 0..1 of the level, filled with a spring
    property int count: 0            // the percentage that counts up

    anchors.fill: parent
    visible: shown > 0.01
    // Over everything except the screen-off black.
    z: 90

    signal wantsWake()
    signal doneShowing(bool wokeIt)

    function play() {
        wokeTheScreen = !Host.screenOn
        if (wokeTheScreen)
            wantsWake()
        ring = 0
        count = 0
        reveal.animateTo(1, 0)
        fillTimer.restart()
        hideTimer.restart()
    }

    Spring { id: reveal; to: 0; response: 0.5; dampingFraction: 0.68 }
    Spring { id: fill; to: root.ring; response: 0.9; dampingFraction: 0.9 }
    Binding { target: root; property: "shown"; value: reveal.value }
    Timer { id: fillTimer; interval: 380; onTriggered: root.ring = root.level / 100 }
    Timer {
        id: hideTimer
        interval: 3300
        onTriggered: {
            reveal.animateTo(0, 0)
            doneTimer.restart()
        }
    }
    Timer { id: doneTimer; interval: 700; onTriggered: root.doneShowing(root.wokeTheScreen) }
    // The count follows the ring.
    Timer {
        interval: 16
        repeat: true
        running: root.visible
        onTriggered: root.count = Math.round(fill.value * 100)
    }

    // The screen under it, blurred and dimmed.
    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: root.shown
        dim: 0.45
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: 230
        height: 230
        scale: 0.6 + 0.4 * root.shown
        opacity: Math.min(1, root.shown * 1.4)

        // The track and the ring.
        Canvas {
            id: arc
            anchors.fill: parent
            property real progress: fill.value
            property color tint: root.level <= 20 ? Theme.danger : Theme.success
            onProgressChanged: requestPaint()
            onTintChanged: requestPaint()
            onPaint: {
                const c = getContext("2d")
                c.reset()
                const r = width / 2 - 12
                c.lineWidth = 14
                c.lineCap = "round"
                c.strokeStyle = Qt.rgba(1, 1, 1, 0.16)
                c.beginPath()
                c.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                c.stroke()
                if (progress > 0.002) {
                    c.strokeStyle = tint
                    c.beginPath()
                    c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, progress))
                    c.stroke()
                }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 4
            // The bolt.
            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 36
                height: 52
                property color tint: arc.tint
                onTintChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.fillStyle = tint
                    c.beginPath()
                    c.moveTo(21, 0)
                    c.lineTo(2, 30)
                    c.lineTo(16, 30)
                    c.lineTo(12, 52)
                    c.lineTo(34, 18)
                    c.lineTo(19, 18)
                    c.closePath()
                    c.fill()
                }
                // A soft pulse while it charges.
                SequentialAnimation on opacity {
                    running: root.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.55; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.55; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.count + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 40
                font.weight: Font.DemiBold
                color: "white"
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: card.bottom
        anchors.topMargin: 22
        opacity: card.opacity
        text: qsTr("Charging")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headlineSize
        font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.85)
    }
}
