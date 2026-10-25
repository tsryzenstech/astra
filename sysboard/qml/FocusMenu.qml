// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Long press on an app: the icon comes forward, everything else (except the
// status bar) blurs, and a menu opens below or above the icon, wherever
// there is room.
Item {
    id: root

    property var home
    property Item blurSource
    property var repeater
    property var model

    property int index: -1
    property bool confirmUninstall: false
    readonly property var entry: index >= 0 && index < model.count ? model.get(index) : null
    property rect iconRect: Qt.rect(0, 0, 0, 0)

    function show(i) {
        const d = repeater.itemAt(i)
        if (!d)
            return
        index = i
        confirmUninstall = false
        iconRect = d.mapToItem(root, 0, 0, d.iconSize, d.iconSize)
        reveal.animateTo(1, 0)
    }
    function dismiss() {
        reveal.animateTo(0, 0)
    }

    visible: reveal.value > 0.01
    Spring { id: reveal; to: 0; response: 0.36; dampingFraction: 0.8 }
    onVisibleChanged: if (!visible) index = -1

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: reveal.value
        dim: 0.2
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
    }

    HomeIcon {
        x: root.iconRect.x
        y: root.iconRect.y
        iconSize: root.iconRect.width
        source: root.entry ? root.entry.icon : ""
        label: root.entry ? root.entry.name : ""
        showLabel: root.entry ? root.entry.container >= 0 : false
        scale: 1 + 0.1 * reveal.value
    }

    readonly property bool below: iconRect.y + iconRect.height + 30 + menu.height < height - 60

    Rectangle {
        id: menu
        width: 236
        height: column.height
        radius: 18
        color: Qt.rgba(0.08, 0.08, 0.08, 0.82)
        x: Math.max(14, Math.min(root.width - width - 14, root.iconRect.x + root.iconRect.width / 2 - width / 2))
        y: root.below ? root.iconRect.y + root.iconRect.height + 30 : root.iconRect.y - height - 14
        transformOrigin: root.below ? Item.Top : Item.Bottom
        scale: 0.7 + 0.3 * reveal.value
        opacity: reveal.value
        clip: true

        Column {
            id: column
            width: parent.width

            Repeater {
                model: [
                    { id: "info", text: "App Info", icon: "info" },
                    { id: "edit", text: "Edit Home Screen", icon: "grid" },
                    { id: "uninstall", icon: "trash",
                      text: root.entry && root.entry.system ? "Uninstall" : root.confirmUninstall ? "Tap again to uninstall" : "Uninstall" }
                ]
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool disabled: modelData.id === "uninstall" && root.entry !== null && root.entry.system
                    width: column.width
                    height: disabled ? 58 : 48

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(1, 1, 1, rowArea.pressed && !row.disabled ? 0.1 : 0)
                    }
                    Column {
                        x: 18
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: row.modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: row.modelData.id === "uninstall" ? Theme.danger : "white"
                            opacity: row.disabled ? 0.4 : 1
                        }
                        Text {
                            visible: row.disabled
                            text: "Installed by root"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textTertiary
                        }
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.icon
                        size: 20
                        color: row.modelData.id === "uninstall" ? Theme.danger : "white"
                        opacity: row.disabled ? 0.4 : 1
                    }
                    Rectangle {
                        visible: row.index < 2
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        enabled: !row.disabled
                        onClicked: {
                            const pkg = root.entry.pkg
                            switch (row.modelData.id) {
                            case "info":
                                root.dismiss()
                                root.home.shell.launch("com.astra.settings", { page: "appinfo", package: pkg }, null)
                                break
                            case "edit":
                                root.dismiss()
                                root.home.editing = true
                                break
                            case "uninstall":
                                if (!root.confirmUninstall) {
                                    root.confirmUninstall = true
                                    return
                                }
                                root.dismiss()
                                Packages.uninstall(pkg)
                                break
                            }
                        }
                    }
                }
            }
        }
    }
}
