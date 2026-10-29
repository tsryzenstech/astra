// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Power + volume down: a white flash, then the shot shrinks with a spring
// into a rounded thumbnail in the bottom-left corner. Tap the thumbnail to
// mark it up, swipe it left to put it away (it is already saved).
Item {
    id: root

    signal editRequested(string path)

    property string path: ""
    property url source: ""
    readonly property bool showing: shrink.to > -0.5 && path !== ""

    // 0 = full screen, 1 = thumbnail
    Spring { id: shrink; to: -1; value: -1; response: 0.55; dampingFraction: 0.72 }
    Spring { id: away; to: 0; response: 0.35; dampingFraction: 0.85 }
    readonly property real t: Math.max(0, shrink.value)

    visible: path !== "" && shrink.value > -0.5

    function capture() {
        const p = Host.newScreenshotPath()
        if (!Host.saveScreenshot(p))
            return
        path = p
        source = ""
        source = "file://" + p
        away.snap(0)
        shrink.snap(0)
        flash.opacity = 0.85
        flashOut.restart()
        shrinkTimer.restart()
        hideTimer.restart()
    }
    function dismiss() {
        hideTimer.stop()
        away.animateTo(-1, 0)
        resetTimer.restart()
    }
    Timer { id: shrinkTimer; interval: 120; onTriggered: shrink.animateTo(1, 0) }
    Timer { id: hideTimer; interval: 5000; onTriggered: if (!area.pressed) root.dismiss() }
    Timer { id: resetTimer; interval: 450; onTriggered: { shrink.snap(-1); root.path = "" } }

    // Shutter flash
    Rectangle {
        id: flash
        anchors.fill: parent
        color: "white"
        opacity: 0
        NumberAnimation on opacity { id: flashOut; running: false; to: 0; duration: 380; easing.type: Easing.OutCubic }
    }

    // The shot, morphing from full screen to the corner.
    Item {
        id: shot
        readonly property real thumbW: 112
        readonly property real thumbH: thumbW * root.height / Math.max(1, root.width)
        readonly property real targetX: 16 + away.value * (thumbW + 40)
        readonly property real targetY: root.height - 34 - thumbH
        x: targetX * root.t
        y: targetY * root.t
        width: root.width + (thumbW - root.width) * root.t
        height: root.height + (thumbH - root.height) * root.t
        opacity: 1 + away.value * 0.9

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4 * root.t
            radius: 18 * root.t + 4
            color: "white"
            opacity: root.t
        }
        Image {
            id: img
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            cache: false
            visible: false
        }
        Rectangle { id: mask; anchors.fill: parent; radius: 16 * root.t + Theme.screenRadius * (1 - root.t); visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: img
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        MouseArea {
            id: area
            anchors.fill: parent
            enabled: root.t > 0.9
            property real startX
            property bool moved: false
            onPressed: (m) => {
                startX = m.x
                moved = false
                hideTimer.stop()
            }
            onPositionChanged: (m) => {
                const dx = m.x - startX
                if (Math.abs(dx) > 8)
                    moved = true
                away.value = Math.min(0, dx / (shot.thumbW + 40))
            }
            onReleased: {
                if (away.value < -0.35) {
                    root.dismiss()
                } else if (!moved) {
                    const p = root.path
                    hideTimer.stop()
                    shrink.snap(-1)
                    root.editRequested(p)
                    root.path = ""
                } else {
                    away.animateTo(0, 0)
                    hideTimer.restart()
                }
            }
        }
    }
}
