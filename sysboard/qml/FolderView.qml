// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// An open folder: the home screen blurs and the folder grows from its icon
// into a large rounded panel. Tap an app to open it; hold one to take it
// out; tap the name to rename; switch between small and big folder.
Item {
    id: root
    property var home
    property Item blurSource
    property string key: ""
    property string name: ""
    property var apps: []
    property bool big: false
    property rect from: Qt.rect(0, 0, 0, 0)
    property bool renaming: false

    readonly property var infos: (Packages.count >= 0 ? apps : []).map(p => Packages.get(p) || ({ package: p }))

    function open(k, n, list, isBig, fromItem) {
        key = k; name = n; apps = list; big = isBig
        from = fromItem ? fromItem.mapToItem(root, 0, 0, fromItem.width, fromItem.height) : Qt.rect(width / 2, height / 2, 0, 0)
        renaming = false
        reveal.animateTo(1, 0)
    }
    function close() {
        renaming = false
        reveal.animateTo(0, 0)
    }

    visible: reveal.value > 0.01
    Spring { id: reveal; to: 0; response: 0.42; dampingFraction: 0.8 }

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: Math.min(1, reveal.value)
        dim: 0.25
    }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        y: panel.y - 64
        visible: !root.renaming
        opacity: Math.min(1, reveal.value)
        text: root.name
        font.family: Theme.fontFamily
        font.pixelSize: 30
        font.weight: Font.Bold
        color: "white"
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.renaming = true; nameField.text = root.name; nameField.forceActiveFocus() } }
    }
    Rectangle {
        visible: root.renaming
        anchors.horizontalCenter: parent.horizontalCenter
        y: panel.y - 70
        width: panel.width
        height: 48
        radius: 24
        color: Qt.rgba(1, 1, 1, 0.2)
        TextInput {
            id: nameField
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.weight: Font.Bold
            color: "white"
            onAccepted: { root.home.renameFolder(root.key, text); root.name = text.trim() || root.name; root.renaming = false }
        }
    }

    Rectangle {
        id: panel
        readonly property rect target: Qt.rect(28, root.height * 0.24, root.width - 56, Math.min(root.height * 0.5, 40 + Math.ceil(Math.max(1, root.infos.length) / 3) * 112))
        readonly property real t: Math.max(0, reveal.value)
        x: root.from.x + (target.x - root.from.x) * t
        y: root.from.y + (target.y - root.from.y) * t
        width: Math.max(1, root.from.width + (target.width - root.from.width) * t)
        height: Math.max(1, root.from.height + (target.height - root.from.height) * t)
        radius: 38
        color: Qt.rgba(1, 1, 1, 0.2)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        clip: true
        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: grid.height
            clip: true
            opacity: Math.max(0, (reveal.value - 0.4) / 0.6)
            Grid {
                id: grid
                width: parent.width
                columns: 3
                rowSpacing: 18
                Repeater {
                    model: root.infos
                    delegate: Item {
                        id: app
                        required property var modelData
                        width: grid.width / 3
                        height: 92
                        HomeIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            iconSize: 62
                            source: app.modelData.iconUrl || ""
                            label: app.modelData.name || ""
                            pressed: area.pressed
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            pressAndHoldInterval: 450
                            onClicked: {
                                root.close()
                                root.home.shell.launch(app.modelData.package, {}, null)
                            }
                            onPressAndHold: {
                                root.home.removeFromFolder(root.key, app.modelData.package)
                                root.apps = root.apps.filter(p => p !== app.modelData.package)
                            }
                        }
                    }
                }
            }
        }
    }

    // Small / big folder, and a hint
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: panel.y + panel.height + 22
        spacing: 10
        opacity: Math.max(0, (reveal.value - 0.5) * 2)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: sizeText.implicitWidth + 32
            height: 36
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.2)
            Text {
                id: sizeText
                anchors.centerIn: parent
                text: root.big ? qsTr("Make Small Folder") : qsTr("Make Big Folder")
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.big = !root.big
                    root.home.setFolderBig(root.key, root.big)
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Hold an app to take it out of the folder")
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.7)
        }
    }
}
