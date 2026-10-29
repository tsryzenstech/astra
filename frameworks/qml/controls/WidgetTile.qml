// SPDX-License-Identifier: Apache-2.0
import QtQuick

// The common layout of a home screen widget: a glyph, a big title and a
// line of detail, sized for small / medium / large.
Item {
    id: root
    property string size: "small"
    property string iconName
    property url iconSource
    property color accent: Theme.accent
    property string title
    property string subtitle
    property string caption        // small caps line at the top
    default property alias extra: more.data

    Text {
        visible: root.caption !== ""
        text: root.caption.toUpperCase()
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        color: root.accent
    }
    Rectangle {
        visible: root.iconName !== "" || root.iconSource.toString() !== ""
        y: root.caption !== "" ? 20 : 0
        width: 38; height: 38; radius: 12
        color: root.iconSource.toString() !== "" ? "transparent" : root.accent
        Icon { visible: root.iconSource.toString() === ""; anchors.centerIn: parent; name: root.iconName; size: 22 }
        AppIcon { visible: root.iconSource.toString() !== ""; anchors.fill: parent; size: 38; source: root.iconSource }
    }
    Column {
        anchors.bottom: root.size === "small" ? parent.bottom : undefined
        y: root.size === "small" ? 0 : 50
        x: root.size === "small" ? 0 : 0
        width: parent.width
        Text { width: parent.width; text: root.title; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: root.size === "small" ? 17 : 20; font.weight: Font.Bold; color: "white" }
        Text { width: parent.width; text: root.subtitle; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; visible: text !== ""; font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.7) }
    }
    Item {
        id: more
        visible: root.size !== "small"
        anchors.fill: parent
    }
}
