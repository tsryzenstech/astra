// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Adding to the desktop's widgets: a widget (the apps' home screen widgets, live), or the apps of a giant
// folder (tap to tick them, then Done). A card in the middle of the screen.
Item {
    id: root

    property var widgets            // DesktopWidgets
    property var shell
    property bool opened: false
    property string mode: "widget"  // "widget" | "folder"
    property var picked: []
    property string folderName: ""
    visible: appear.value > 0.01
    z: 70

    Spring { id: appear; to: root.opened ? 1 : 0; response: 0.34; dampingFraction: 0.84 }

    function openWidgets() { mode = "widget"; opened = true }
    function openFolder() {
        mode = "folder"
        const f = widgets.hasFolder ? widgets.entries[0].folder : null
        picked = f ? f.apps.slice() : []
        folderName = f ? f.name : ""
        opened = true
    }
    function close() { opened = false }

    readonly property var available: {
        if (Packages.count < 0) return []
        return Packages.widgets.filter(w => (w.home || []).indexOf("small") >= 0)
    }
    readonly property var apps: Packages.count >= 0 ? Packages.list().filter(p => p.launcher !== false).sort((a, b) => (a.name || "").localeCompare(b.name || "")) : []

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4 * Math.min(1, appear.value)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 40)
        height: Math.min(520, parent.height - 80)
        radius: Theme.sheetRadius
        color: Theme.sheet
        scale: 0.9 + 0.1 * appear.value
        opacity: Math.min(1, appear.value * 1.5)
        MouseArea { anchors.fill: parent }

        Text {
            x: 24; y: 20
            text: root.mode === "widget" ? qsTr("Add a Widget") : qsTr("Giant Folder")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize + 2
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            visible: root.mode === "widget"
            x: 24; y: 50
            width: parent.width - 48
            text: root.widgets && root.widgets.hasFolder ? qsTr("The giant folder takes the whole column: remove it to add widgets.")
                  : qsTr("Two widgets fit at a time: a third replaces the older one.")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.textSecondary
            wrapMode: Text.Wrap
        }

        // Widgets
        GridView {
            visible: root.mode === "widget"
            x: 24; y: 84
            width: parent.width - 48
            height: parent.height - 84 - 76
            cellWidth: 140
            cellHeight: 160
            clip: true
            model: root.available
            delegate: Item {
                id: wcell
                required property var modelData
                width: 140; height: 160
                Item {
                    x: 6; y: 4
                    width: 128; height: 128
                    HomeWidget {
                        width: 168; height: 168
                        scale: 128 / 168
                        transformOrigin: Item.TopLeft
                        widgetKey: wcell.modelData.key
                        size: "small"
                        shell: root.shell
                        enabled: false
                    }
                }
                Text {
                    y: 136
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: wcell.modelData.name
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    color: Theme.text
                }
                TapHandler {
                    enabled: !(root.widgets && root.widgets.hasFolder)
                    onTapped: { root.widgets.addWidget(wcell.modelData.key); root.close() }
                }
            }
        }

        // Folder apps
        GridView {
            visible: root.mode === "folder"
            x: 24; y: 60
            width: parent.width - 48
            height: parent.height - 60 - 76
            cellWidth: 96
            cellHeight: 100
            clip: true
            model: root.apps
            delegate: Item {
                id: acell
                required property var modelData
                readonly property bool on: root.picked.indexOf(modelData.package) >= 0
                width: 96; height: 100
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Item {
                        width: 52; height: 52
                        anchors.horizontalCenter: parent.horizontalCenter
                        AppIcon { size: 52; source: acell.modelData.iconUrl || "" }
                        Rectangle {
                            visible: acell.on
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.rightMargin: -4; anchors.bottomMargin: -4
                            width: 22; height: 22; radius: 11
                            color: Theme.accent
                            Icon { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.accentText }
                        }
                    }
                    Text {
                        width: 88
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: acell.modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                        color: Theme.text
                    }
                }
                TapHandler {
                    onTapped: root.picked = acell.on ? root.picked.filter(p => p !== acell.modelData.package)
                                                      : root.picked.concat([acell.modelData.package])
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            spacing: 10
            Rectangle {
                width: 110; height: 44; radius: 22
                color: Theme.surfaceRaised
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }
            Rectangle {
                visible: root.mode === "folder"
                width: 110; height: 44; radius: 22
                color: Theme.accent
                Text { anchors.centerIn: parent; text: qsTr("Done"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.accentText }
                MouseArea { anchors.fill: parent; onClicked: { root.widgets.setFolder(root.folderName, root.picked); root.close() } }
            }
        }
    }
}
