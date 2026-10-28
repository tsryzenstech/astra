// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Activity indicator: a rotating arc with rounded caps.
Item {
    id: root

    property real size: 24
    property bool running: true
    property color color: Theme.text

    implicitWidth: size
    implicitHeight: size
    visible: running

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = Math.max(2, root.size / 9)
            ctx.lineCap = "round"
            ctx.strokeStyle = root.color
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth, 0, Math.PI * 1.45)
            ctx.stroke()
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: root.running && root.visible
        }
    }
    onColorChanged: canvas.requestPaint()
}
