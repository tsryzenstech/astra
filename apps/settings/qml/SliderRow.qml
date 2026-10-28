// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// A labelled slider bound to a numeric setting (or to `value` + moved()).
Item {
    id: root

    property string text
    property string iconName
    property string key
    property real fallback: 0.5
    property real from: 0
    property real to: 1
    property real stepSize: 0
    property real value: key ? Number(Settings.values[key] ?? fallback) : 0
    property string valueText: Math.round((value - from) / (to - from) * 100) + "%"
    property bool separator: true
    signal moved(real value)

    width: parent ? parent.width : 300
    height: 84

    Row {
        x: 16
        y: 12
        spacing: 10
        Icon { visible: root.iconName !== ""; name: root.iconName; size: 20; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.Medium
            color: Theme.text
        }
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 14
        text: root.valueText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.textSecondary
    }
    Slider {
        x: 16
        y: 44
        width: parent.width - 32
        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value
        onMoved: (v) => {
            if (root.key)
                Settings.setValue(root.key, v)
            root.moved(v)
        }
    }
    Rectangle {
        visible: root.separator
        anchors.bottom: parent.bottom
        x: 16
        width: parent.width - 32
        height: 1
        color: Theme.separator
    }
}
