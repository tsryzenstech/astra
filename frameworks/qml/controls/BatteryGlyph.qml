// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Battery pill with the charge level on it. The fill follows the level; green
// while charging, red at 20 % and below. Scales with `height`.
//
// Plain rectangles and text, no effects: the status bar must always show it, and
// the masked version this was did not on the phone.
Item {
    id: root

    property int level: 100
    property bool charging: false
    property bool showLevel: true
    property color color: "white"

    implicitHeight: 13
    implicitWidth: height * 2.1

    // The body fills up to the real charge level; the rest stays faint, so the
    // glyph has as many stages as there are percentages.
    Rectangle {
        id: body
        width: parent.width - root.height * 0.18
        height: parent.height
        radius: height * 0.31
        color: root.color
        opacity: 0.38
    }
    Rectangle {
        width: Math.max(height * 0.62, body.width * Math.max(0, Math.min(100, root.level)) / 100)
        height: parent.height
        radius: height * 0.31
        color: root.charging ? "#34D058" : root.level <= 20 ? "#FF453A" : root.color
    }
    Rectangle {
        anchors.left: body.right
        anchors.leftMargin: root.height * 0.06
        anchors.verticalCenter: parent.verticalCenter
        width: root.height * 0.12
        height: root.height * 0.34
        radius: width / 2
        color: root.color
        opacity: 0.45
    }
    Text {
        width: body.width
        height: parent.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        visible: root.showLevel
        text: root.level
        font.family: Theme.fontFamily
        font.weight: Font.Bold
        font.pixelSize: root.height * (root.level >= 100 ? 0.8 : 0.86)
        font.letterSpacing: -0.4
        // Dark on the light glyph of dark backgrounds, and the other way round.
        color: root.color.hslLightness > 0.5 ? "#101014" : "white"
    }
}
