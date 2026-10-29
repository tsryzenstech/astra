// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Markup for a fresh screenshot: draw with a pen, a highlighter or erase,
// pick a colour, undo and redo, crop, then save over the file or delete it.
Item {
    id: root

    property string path: ""
    readonly property bool active: open.to > 0.5

    property var strokes: []      // [{ tool, color, width, points: [[u, v], ...] }] in image coordinates
    property var redoStack: []
    property string tool: "pen"   // pen, marker, eraser
    property color color: "#FF453A"
    property bool cropping: false
    property rect crop: Qt.rect(0, 0, 1, 1)
    readonly property rect view: cropping ? Qt.rect(0, 0, 1, 1) : crop
    property bool exporting: false

    readonly property var palette: ["#FFFFFF", "#111111", "#FF453A", "#FFB020", "#34D058", "#2F80FF", Theme.accent]

    visible: open.value > 0.005
    Spring { id: open; to: 0; response: 0.45; dampingFraction: 0.86 }

    function edit(p) {
        path = p
        strokes = []
        redoStack = []
        crop = Qt.rect(0, 0, 1, 1)
        cropping = false
        tool = "pen"
        img.source = ""
        img.source = "file://" + p
        open.animateTo(1, 0)
    }
    function close() { open.animateTo(0, 0) }

    function undo() {
        if (!strokes.length)
            return
        redoStack = redoStack.concat([strokes[strokes.length - 1]])
        strokes = strokes.slice(0, -1)
    }
    function redo() {
        if (!redoStack.length)
            return
        strokes = strokes.concat([redoStack[redoStack.length - 1]])
        redoStack = redoStack.slice(0, -1)
    }
    function save() {
        exporting = true
        const w = Math.round(img.sourceSize.width * crop.width)
        const h = Math.round(img.sourceSize.height * crop.height)
        stage.grabToImage(function(result) {
            result.saveToFile(root.path)
            root.exporting = false
            root.close()
        }, Qt.size(w, h))
    }
    function remove() {
        Host.removeScreenshot(path)
        close()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: open.value
        MouseArea { anchors.fill: parent }
    }

    Item {
        anchors.fill: parent
        opacity: open.value
        scale: 0.94 + 0.06 * open.value

        // ---- top bar ----------------------------------------------------
        Row {
            x: 16
            y: Theme.statusBarHeight + 4
            spacing: 10
            IconButton { iconName: "trash"; iconColor: Theme.danger; color: Qt.rgba(1, 1, 1, 0.1); onClicked: root.remove() }
            IconButton { iconName: "undo"; color: Qt.rgba(1, 1, 1, 0.1); enabled: root.strokes.length > 0; onClicked: root.undo() }
            IconButton { iconName: "redo"; color: Qt.rgba(1, 1, 1, 0.1); enabled: root.redoStack.length > 0; onClicked: root.redo() }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: Theme.statusBarHeight + 4
            width: doneText.implicitWidth + 36
            height: 44
            radius: 22
            color: doneArea.pressed ? Theme.accentDeep : Theme.accent
            Text {
                id: doneText
                anchors.centerIn: parent
                text: root.cropping ? qsTr("Apply") : qsTr("Done")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.Bold
                color: "white"
            }
            MouseArea {
                id: doneArea
                anchors.fill: parent
                onClicked: {
                    if (root.cropping)
                        root.cropping = false
                    else
                        root.save()
                }
            }
        }

        // ---- the picture -----------------------------------------------
        Item {
            id: area
            x: 16
            y: Theme.statusBarHeight + 64
            width: parent.width - 32
            height: parent.height - y - 170

            Image {
                id: img
                visible: false
                cache: false
                asynchronous: false
            }

            // What is shown (and exported): the cropped part of the shot.
            Item {
                id: stage
                readonly property real aspect: img.sourceSize.width > 0
                    ? (img.sourceSize.width * root.view.width) / (img.sourceSize.height * root.view.height) : 0.46
                width: Math.min(area.width, area.height * aspect)
                height: width / aspect
                anchors.centerIn: parent
                clip: true

                Image {
                    source: img.source
                    x: -root.view.x * width
                    y: -root.view.y * height
                    width: stage.width / root.view.width
                    height: stage.height / root.view.height
                    fillMode: Image.Stretch
                    cache: false
                    smooth: true
                    mipmap: true
                }

                Canvas {
                    id: ink
                    anchors.fill: parent
                    renderStrategy: Canvas.Immediate
                    function px(p) {
                        return [(p[0] - root.view.x) / root.view.width * width, (p[1] - root.view.y) / root.view.height * height]
                    }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        const scale = width / root.view.width / 400
                        for (const s of root.strokes.concat(drawing.current ? [drawing.current] : [])) {
                            if (s.points.length < 1)
                                continue
                            ctx.globalCompositeOperation = s.tool === "eraser" ? "destination-out" : "source-over"
                            ctx.globalAlpha = s.tool === "marker" ? 0.4 : 1
                            ctx.strokeStyle = s.color
                            ctx.lineWidth = s.width * scale
                            ctx.beginPath()
                            const first = px(s.points[0])
                            ctx.moveTo(first[0], first[1])
                            for (let i = 1; i < s.points.length; i++) {
                                const q = px(s.points[i])
                                ctx.lineTo(q[0], q[1])
                            }
                            if (s.points.length === 1)
                                ctx.lineTo(first[0] + 0.1, first[1])
                            ctx.stroke()
                        }
                    }
                    Connections {
                        target: root
                        function onStrokesChanged() { ink.requestPaint() }
                        function onViewChanged() { ink.requestPaint() }
                    }
                }

                MouseArea {
                    id: drawing
                    anchors.fill: parent
                    enabled: !root.cropping
                    preventStealing: true
                    property var current: null
                    function uv(m) {
                        return [root.view.x + m.x / width * root.view.width, root.view.y + m.y / height * root.view.height]
                    }
                    onPressed: (m) => {
                        current = { tool: root.tool, color: root.color.toString(),
                                    width: root.tool === "marker" ? 18 : root.tool === "eraser" ? 22 : 4, points: [uv(m)] }
                        ink.requestPaint()
                    }
                    onPositionChanged: (m) => {
                        if (!current)
                            return
                        current.points.push(uv(m))
                        ink.requestPaint()
                    }
                    onReleased: {
                        if (current) {
                            root.strokes = root.strokes.concat([current])
                            root.redoStack = []
                        }
                        current = null
                    }
                }

                // Crop frame: drag the corners.
                Item {
                    anchors.fill: parent
                    visible: root.cropping
                    Rectangle {
                        id: frame
                        x: root.crop.x * parent.width
                        y: root.crop.y * parent.height
                        width: root.crop.width * parent.width
                        height: root.crop.height * parent.height
                        color: "transparent"
                        border.width: 2
                        border.color: "white"
                        radius: 4
                    }
                    Repeater {
                        model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                        delegate: Rectangle {
                            required property var modelData
                            width: 26
                            height: 26
                            radius: 13
                            color: "white"
                            x: frame.x + modelData[0] * frame.width - 13
                            y: frame.y + modelData[1] * frame.height - 13
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -12
                                preventStealing: true
                                onPositionChanged: (m) => {
                                    const p = mapToItem(stage, m.x, m.y)
                                    const u = Math.max(0, Math.min(1, p.x / stage.width))
                                    const v = Math.max(0, Math.min(1, p.y / stage.height))
                                    let x0 = root.crop.x, y0 = root.crop.y
                                    let x1 = x0 + root.crop.width, y1 = y0 + root.crop.height
                                    if (modelData[0] === 0) x0 = Math.min(u, x1 - 0.1); else x1 = Math.max(u, x0 + 0.1)
                                    if (modelData[1] === 0) y0 = Math.min(v, y1 - 0.1); else y1 = Math.max(v, y0 + 0.1)
                                    root.crop = Qt.rect(x0, y0, x1 - x0, y1 - y0)
                                }
                            }
                        }
                    }
                }
            }

            // Rounded frame around the picture (not exported).
            Rectangle {
                visible: !root.exporting
                anchors.fill: stage
                anchors.margins: -2
                radius: 14
                color: "transparent"
                border.width: 3
                border.color: "black"
            }
        }

        // ---- tools -------------------------------------------------------
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36
            width: parent.width - 32
            height: 118
            radius: Theme.sheetRadius
            color: Qt.rgba(1, 1, 1, 0.08)

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                spacing: 12
                Repeater {
                    model: [ { id: "pen", icon: "pen" }, { id: "marker", icon: "marker" },
                             { id: "eraser", icon: "eraser" }, { id: "crop", icon: "crop" } ]
                    delegate: IconButton {
                        required property var modelData
                        size: 46
                        iconName: modelData.icon
                        readonly property bool current: modelData.id === "crop" ? root.cropping : !root.cropping && root.tool === modelData.id
                        color: current ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
                        onClicked: {
                            if (modelData.id === "crop") {
                                root.cropping = !root.cropping
                            } else {
                                root.cropping = false
                                root.tool = modelData.id
                            }
                        }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 72
                spacing: 12
                opacity: root.tool === "eraser" || root.cropping ? 0.35 : 1
                Repeater {
                    model: root.palette
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: Qt.colorEqual(modelData, root.color)
                        width: 30
                        height: 30
                        radius: 15
                        color: modelData
                        border.width: current ? 3 : 1
                        border.color: current ? "white" : Qt.rgba(1, 1, 1, 0.3)
                        scale: current ? 1.15 : 1
                        Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                        MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: root.color = modelData }
                    }
                }
            }
        }
    }
}
