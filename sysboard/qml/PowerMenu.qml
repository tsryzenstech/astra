// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Hold the power button: slide to power off, or restart. The screen blurs
// in place and the controls drop in with a spring, like the panels.
Item {
    id: root

    property Item blurSource
    readonly property bool active: reveal.to > 0.5

    visible: reveal.value > 0.005
    Spring { id: reveal; to: 0; response: 0.45; dampingFraction: 0.72 }

    function open() { reveal.animateTo(1, 0); knob.snap(0) }
    function close() { reveal.animateTo(0, 0) }

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: Math.min(1, reveal.value)
        dim: 0.5
    }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Spring { id: knob; to: 0; response: 0.35; dampingFraction: 0.75 }

    // Slide to power off
    Rectangle {
        id: track
        anchors.horizontalCenter: parent.horizontalCenter
        y: 120 - 80 * (1 - reveal.value)
        width: parent.width - 48
        height: 72
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.16)
        opacity: Math.min(1, reveal.value * 1.3)
        readonly property real travel: width - height

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 26
            text: qsTr("slide to power off")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize + 1
            font.weight: Font.Medium
            color: "white"
            opacity: 1 - knob.value * 1.6
            // A soft shimmer invites the slide.
            SequentialAnimation on opacity {
                running: root.visible && knob.value < 0.01
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            x: 6 + knob.value * (track.travel)
            y: 6
            width: track.height - 12
            height: width
            radius: width / 2
            color: "white"
            Icon { anchors.centerIn: parent; name: "power"; size: 28; color: Theme.danger }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                preventStealing: true
                property real startX
                property real startValue
                onPressed: (m) => {
                    startX = mapToItem(track, m.x, m.y).x
                    startValue = knob.value
                }
                onPositionChanged: (m) => {
                    const x = mapToItem(track, m.x, m.y).x
                    knob.value = Math.max(0, Math.min(1, startValue + (x - startX) / track.travel))
                }
                onReleased: {
                    if (knob.value > 0.9) {
                        knob.animateTo(1, 0)
                        System.power("poweroff")
                    } else {
                        knob.animateTo(0, 0)
                    }
                }
            }
        }
    }

    // Restart and Cancel
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 90 - 60 * (1 - reveal.value)
        spacing: 26
        opacity: Math.min(1, reveal.value * 1.3)

        Repeater {
            model: [
                { id: "restart", icon: "refresh", label: QT_TR_NOOP("Restart") },
                { id: "cancel", icon: "close", label: QT_TR_NOOP("Cancel") }
            ]
            delegate: Column {
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 68
                    height: 68
                    radius: 34
                    color: area.pressed ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.18)
                    scale: area.pressed ? 0.9 : 1
                    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                    Icon { anchors.centerIn: parent; name: modelData.icon; size: 30 }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.id === "restart")
                                System.power("reboot")
                            else
                                root.close()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr(modelData.label)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize + 1
                    color: "white"
                }
            }
        }
    }
}
