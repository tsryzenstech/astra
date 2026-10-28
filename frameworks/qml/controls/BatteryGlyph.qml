// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects

// Battery pill with the charge level knocked out of it, as in the status bar
// of the concepts. The fill follows the level; green while charging, red
// at 20 % and below. Scales with `height`.
Item {
    id: root

    property int level: 100
    property bool charging: false
    property bool showLevel: true
    property color color: "white"

    implicitHeight: 13
    implicitWidth: height * 2.1

    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        // The body fills up to the real charge level; the rest stays faint,
        // so the glyph has as many stages as there are percentages.
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
    }

    Item {
        id: knockout
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Text {
            x: 0
            width: body.width
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: !root.showLevel ? "" : root.charging ? "⚡" + root.level : root.level
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.height * (root.level >= 100 ? 0.86 : 0.92)
            font.letterSpacing: -0.4
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: shape
        maskEnabled: true
        maskInverted: true
        maskSource: knockout
        maskThresholdMin: 0.3
        maskSpreadAtMin: 0.3
    }
}
