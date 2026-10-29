// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Volume slider shown by the volume buttons. It springs in from the right
// edge (where the buttons are), bounces with every press, stretches when
// pushed past either end, can be dragged, and tucks itself away after a
// moment of rest.
Item {
    id: root

    readonly property real level: Number(Settings.values["audio.volume"] ?? 0.6)
    readonly property bool muted: Settings.values["controls.sound"] === false
    readonly property real step: 1 / 16
    property bool shown: false

    width: 64
    height: 220

    Spring { id: reveal; to: 0; response: 0.42; dampingFraction: 0.62 }
    Spring { id: bump; to: 0; response: 0.26; dampingFraction: 0.45 }   // squash on each press
    Spring { id: stretch; to: 0; response: 0.3; dampingFraction: 0.5 }  // over-pull at the ends
    Spring { id: fill; to: root.muted ? 0 : root.level; response: 0.3; dampingFraction: 0.82 }

    visible: reveal.value > 0.01
    x: parent ? parent.width - 14 - width + (1 - reveal.value) * (width + 30) : 0

    function show() {
        shown = true
        reveal.animateTo(1, 0)
        hideTimer.restart()
    }
    function hide() {
        shown = false
        reveal.animateTo(0, 0)
    }
    Timer { id: hideTimer; interval: 1800; onTriggered: if (!drag.pressed) root.hide() }

    function setLevel(v) {
        v = Math.max(0, Math.min(1, v))
        Settings.setValue("audio.volume", Math.round(v * 1000) / 1000)
        // Volume up out of silence turns the sound back on.
        if (v > 0 && root.muted)
            Settings.setValue("controls.sound", true)
    }
    // A press of the volume buttons.
    function press(delta) {
        show()
        const before = muted ? 0 : level
        const after = Math.max(0, Math.min(1, before + delta * step))
        if (after === before) {
            // Already at the end: the pill stretches and springs back.
            stretch.value = delta * 0.08
            stretch.animateTo(0, 0)
        } else {
            setLevel(after)
            bump.value = 0.06
            bump.animateTo(0, 0)
        }
    }

    Item {
        id: pill
        anchors.fill: parent
        transformOrigin: stretch.value >= 0 ? Item.Bottom : Item.Top
        scale: 1 - bump.value * 0.5
        transform: Scale {
            origin.y: stretch.value >= 0 ? pill.height : 0
            yScale: 1 + Math.abs(stretch.value)
            xScale: 1 - Math.abs(stretch.value) * 0.4
            origin.x: pill.width / 2
        }
        opacity: Math.min(1, reveal.value * 1.4)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(0.12, 0.12, 0.14, 0.92)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }
        // The fill is a pill of its own: round at every level.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.width + Math.max(0, Math.min(1, fill.value)) * (parent.height - parent.width)
            radius: width / 2
            color: "white"
            opacity: fill.value <= 0.001 ? 0.18 : 1
        }
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            name: root.muted || fill.value <= 0.001 ? "volume-off" : "volume"
            size: 26
            color: fill.value > 0.12 ? "#26262A" : "white"
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.margins: -10
        preventStealing: true
        property real startY
        property real startLevel
        onPressed: (m) => {
            startY = m.y
            startLevel = root.muted ? 0 : root.level
            hideTimer.stop()
        }
        onPositionChanged: (m) => {
            const v = startLevel + (startY - m.y) / root.height
            if (v > 1 || v < 0)
                stretch.value = Motion.rubberband(v > 1 ? v - 1 : v, 1, 0.2) * 0.4
            root.setLevel(v)
        }
        onReleased: {
            stretch.animateTo(0, 0)
            hideTimer.restart()
        }
    }
}
