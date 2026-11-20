// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// A menu that opens at the pointer (right click). It covers its parent (give it `anchors.fill: parent` in the
// app's root) so that a click anywhere else closes it.
//
//   ContextMenu { id: menu; anchors.fill: parent; onTriggered: (id) => ... }
//   menu.popup(mouse.x, mouse.y, [{ id: "open", label: qsTr("Open"), icon: "folder" },
//                                 { separator: true },
//                                 { id: "delete", label: qsTr("Delete"), danger: true }])
Item {
    id: root

    property var items: []
    property bool opened: false
    signal triggered(string id)

    visible: opened || appear.value > 0.01
    z: 900

    Spring { id: appear; to: root.opened ? 1 : 0; response: 0.26; dampingFraction: 0.82 }

    function popup(x, y, entries) {
        items = entries || items
        panel.x = Math.max(8, Math.min(width - panel.width - 8, x))
        panel.y = Math.max(8, Math.min(height - panel.height - 8, y))
        opened = true
    }
    function close() { opened = false }

    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    Rectangle {
        id: panel
        width: 232
        height: column.implicitHeight + 12
        radius: Theme.radius
        color: Theme.sheet
        border.width: 1
        border.color: Theme.separator
        opacity: Math.min(1, appear.value * 1.5)
        scale: 0.94 + 0.06 * Math.min(1, appear.value)
        transformOrigin: Item.TopLeft

        Column {
            id: column
            x: 6
            y: 6
            width: parent.width - 12
            Repeater {
                model: root.items
                delegate: Item {
                    id: entry
                    required property var modelData
                    width: column.width
                    height: modelData.separator ? 9 : 36

                    Rectangle {
                        visible: entry.modelData.separator === true
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        width: parent.width - 16
                        height: 1
                        color: Theme.separator
                    }
                    Rectangle {
                        visible: !entry.modelData.separator
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: area.containsMouse ? Theme.surfaceRaised : "transparent"
                        opacity: entry.modelData.disabled ? 0.4 : 1
                        Icon {
                            visible: !!entry.modelData.icon
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: entry.modelData.icon || ""
                            size: 18
                            color: entry.modelData.danger ? Theme.danger : Theme.text
                        }
                        Text {
                            x: 38
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.label || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            color: entry.modelData.danger ? Theme.danger : Theme.text
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.shortcut || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.captionSize
                            color: Theme.textTertiary
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !entry.modelData.disabled
                            onClicked: {
                                root.close()
                                root.triggered(entry.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
