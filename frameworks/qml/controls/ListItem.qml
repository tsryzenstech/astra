// SPDX-License-Identifier: Apache-2.0
import QtQuick

// A row inside a ListGroup: label, optional subtitle/value, and an
// accessory (chevron, switch or nothing). Child items are placed with the
// trailing accessories (e.g. a signal glyph).
Item {
    id: root

    default property alias accessories: extra.data

    property string text
    property string subtitle
    property string value
    property string iconName
    property url iconSource
    property bool chevron: false
    property bool selected: false      // trailing accent check mark (choices)
    property bool busy: false          // trailing spinner
    property color iconColor: Theme.text
    property real iconTile: 0          // >0: symbolic icon on a rounded colour tile of this size
    property color tileColor: Theme.accent
    property bool showSwitch: false
    property alias checked: toggle.checked
    property bool destructive: false
    property bool enabled: true
    property bool separator: true
    property color textColor: destructive ? Theme.danger : Theme.text

    signal clicked()
    signal toggled(bool checked)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(Theme.rowHeight, labels.implicitHeight + 24)
    opacity: enabled ? 1 : 0.45

    // Press feedback is an inset rounded pill: no square corners even on
    // the first and last row of a group.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.radius - 4
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08)
        opacity: area.pressed && (root.chevron || !root.showSwitch) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Row {
        id: leading
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Loader {
            active: root.iconName !== "" || root.iconSource.toString() !== ""
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: root.iconSource.toString() !== "" ? appIcon : symbolic
            Component { id: appIcon; AppIcon { source: root.iconSource; size: 30 } }
            Component {
                id: symbolic
                Rectangle {
                    width: root.iconTile > 0 ? root.iconTile : 22
                    height: width
                    radius: width * 0.32
                    color: root.iconTile > 0 ? root.tileColor : "transparent"
                    Icon { anchors.centerIn: parent; name: root.iconName; size: root.iconTile > 0 ? root.iconTile * 0.62 : 22; color: root.iconTile > 0 ? Theme.accentText : root.iconColor }
                }
            }
        }

        Column {
            id: labels
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - leading.x - trailing.width - 44 - (root.iconName || root.iconSource.toString() ? 42 : 0)
            Text {
                width: parent.width
                text: root.text
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.Medium
                color: root.textColor
            }
            Text {
                visible: root.subtitle !== ""
                width: parent.width
                text: root.subtitle
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
        }
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Row {
            id: extra
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
        }
        Text {
            visible: root.value !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width * 0.55)
            elide: Text.ElideMiddle
            text: root.value
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }
        Icon {
            visible: root.selected
            name: "check"
            size: 22
            color: Theme.accent
            anchors.verticalCenter: parent.verticalCenter
        }
        Spinner {
            visible: root.busy
            running: root.busy
            size: 20
            anchors.verticalCenter: parent.verticalCenter
        }
        Switch {
            id: toggle
            visible: root.showSwitch
            enabled: root.enabled
            anchors.verticalCenter: parent.verticalCenter
            onToggled: (c) => root.toggled(c)
        }
        Icon {
            visible: root.chevron
            name: "chevron-right"
            color: Theme.textTertiary
            size: 24
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        visible: root.separator
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16 + (root.iconName || root.iconSource.toString() ? 42 : 0)
        anchors.rightMargin: 16
        height: 1
        color: Theme.separator
    }

    MouseArea {
        id: area
        anchors.fill: parent
        z: -1
        enabled: root.enabled
        onClicked: {
            if (root.showSwitch && !root.chevron)
                root.toggled(!toggle.checked)
            root.clicked()
        }
    }
}
