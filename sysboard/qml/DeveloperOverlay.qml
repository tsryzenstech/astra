// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Developer Options overlays: a dot under every finger (Show taps) and a
// frame counter (Frame rate). Neither takes input.
Item {
    id: root
    readonly property bool devOn: !!Settings.values["developer.enabled"]
    readonly property bool showTaps: devOn && !!Settings.values["developer.show_taps"]
    readonly property bool showFps: devOn && !!Settings.values["developer.show_fps"]

    PointHandler {
        id: taps
        enabled: root.showTaps
        acceptedDevices: PointerDevice.AllDevices
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
    }
    Rectangle {
        visible: taps.active
        x: taps.point.position.x - width / 2
        y: taps.point.position.y - height / 2
        width: 44
        height: 44
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.35)
        border.color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 2
    }

    property int frames: 0
    property int fps: 0
    Connections {
        target: root.showFps ? root.Window.window : null
        function onFrameSwapped() { root.frames++ }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.showFps
        onTriggered: { root.fps = root.frames; root.frames = 0 }
    }
    Rectangle {
        visible: root.showFps
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 64
        width: fpsText.width + 18
        height: 26
        radius: 13
        color: Qt.rgba(0, 0, 0, 0.6)
        Text {
            id: fpsText
            anchors.centerIn: parent
            text: root.fps + " fps"
            color: root.fps >= 55 ? "#34D058" : root.fps >= 30 ? "#FFB020" : "#FF453A"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
