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
    readonly property var entry: index >= 0 && index < model.count ? model.get(index) : null
    property rect iconRect: Qt.rect(0, 0, 0, 0)

    function show(i) {
        const d = repeater.itemAt(i)
        if (!d)
            return
        index = i
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

    // Room for the (enlarged) icon and its label before the menu starts.
    readonly property real labelSpace: entry && entry.container >= 0 ? 34 : 0
    readonly property real gap: 18 + iconRect.height * 0.05
    readonly property bool below: iconRect.y + iconRect.height + labelSpace + gap + menu.height < height - 60

    Rectangle {
        id: menu
        width: 236
        height: column.height
        radius: Theme.cardRadius
        color: Qt.rgba(0.09, 0.09, 0.1, 0.86)
        x: Math.max(14, Math.min(root.width - width - 14, root.iconRect.x + root.iconRect.width / 2 - width / 2))
        y: root.below ? root.iconRect.y + root.iconRect.height + root.labelSpace + root.gap
                      : root.iconRect.y - root.iconRect.height * 0.05 - height - root.gap
        transformOrigin: root.below ? Item.Top : Item.Bottom
        scale: 0.7 + 0.3 * reveal.value
        opacity: reveal.value

        Column {
            id: column
            width: parent.width

            Repeater {
                model: [
                    { id: "info", text: qsTr("App Info"), icon: "info" },
                    { id: "edit", text: qsTr("Edit Home Screen"), icon: "grid" },
                    { id: "uninstall", text: qsTr("Uninstall"), icon: "trash-red" }
                ]
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool disabled: modelData.id === "uninstall" && root.entry !== null && root.entry.system
                    width: column.width
                    height: disabled ? 62 : 52

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: Theme.radius - 5
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
                            text: qsTr("Can't uninstall System Apps")
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
                        size: 21
                        opacity: row.disabled ? 0.4 : 1
                    }
                    Rectangle {
                        visible: row.index < 2
                        anchors.bottom: parent.bottom
                        x: 18
                        width: parent.width - 36
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
                                root.dismiss()
                                Dialogs.show({
                                    title: qsTr("Uninstall %1?").arg(root.entry.name),
                                    message: qsTr("The app and all of its data will be removed from this phone."),
                                    icon: "trash",
                                    buttons: [ { id: "cancel", label: qsTr("Cancel") },
                                               { id: "uninstall", label: qsTr("Uninstall"), style: "destructive" } ]
                                }, function(button) {
                                    if (button === "uninstall")
                                        Packages.uninstall(pkg)
                                })
                                break
                            }
                        }
                    }
                }
            }
        }
    }
}
