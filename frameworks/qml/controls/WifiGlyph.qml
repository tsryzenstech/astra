// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Wi-Fi fan with 0-3 lit arcs for the signal strength (0-100). Unlit arcs
// stay faint so the shape reads at a glance. Scales with `height`.
Item {
    id: root

    property int strength: 100
    property bool connecting: false
    property color color: "white"
    readonly property int bars: strength >= 70 ? 3 : strength >= 40 ? 2 : strength > 0 ? 1 : 0

    implicitHeight: 13
    implicitWidth: height * 1.38

    // While connecting the arcs light up one after the other.
    property int sweep: 0
    Timer {
        running: root.connecting && root.visible
        interval: 320
        repeat: true
        onTriggered: root.sweep = (root.sweep + 1) % 4
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            const cx = w / 2, cy = h * 0.93
            const lw = h * 0.17
            const lit = root.connecting ? root.sweep : root.bars
            ctx.lineCap = "round"
            ctx.lineWidth = lw
            // Dot
            ctx.fillStyle = root.color
            ctx.globalAlpha = lit >= 0 && (root.strength > 0 || root.connecting) ? 1 : 0.3
            ctx.beginPath()
            ctx.arc(cx, cy - lw * 0.4, lw * 0.85, 0, Math.PI * 2)
            ctx.fill()
            // Arcs
            ctx.strokeStyle = root.color
            const radii = [h * 0.43, h * 0.66, h * 0.9]
            for (let i = 0; i < 3; ++i) {
                ctx.globalAlpha = i < lit ? 1 : 0.22
                ctx.beginPath()
                ctx.arc(cx, cy, radii[i], Math.PI * 1.25, Math.PI * 1.75)
                ctx.stroke()
            }
        }
    }
    onBarsChanged: canvas.requestPaint()
    onSweepChanged: canvas.requestPaint()
    onConnectingChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onStrengthChanged: canvas.requestPaint()
}
