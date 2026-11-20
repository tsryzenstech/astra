// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Activities: the windows that are open, live and small, and all the apps under them, with a search
// field on top. The desktop blurs behind it and the items drop in with the same springs as the phone's
// Control Center.
Item {
    id: root

    property var shell
    property var windowLayer                       // DesktopWindowLayer
    property Item blurSource
    property bool opened: false
    readonly property real reveal: spring.value

    visible: reveal > 0.002
    focus: opened

    Spring { id: spring; to: root.opened ? 1 : 0; response: 0.42; dampingFraction: 0.86 }

    function open() {
        search.text = ""
        opened = true
        search.forceActiveFocus()
    }
    function close() { opened = false }
    function toggle() { opened ? close() : open() }

    readonly property string query: search.text.trim().toLowerCase()
    readonly property var apps: {
        if (Packages.count < 0)
            return []
        const q = query
        return Packages.list()
            .filter(p => p.launcher !== false && (q === "" || (p.name || "").toLowerCase().indexOf(q) >= 0))
            .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
    }
    readonly property var openWindows: {
        const rev = windowLayer ? windowLayer.revision : 0
        return windowLayer && query === "" ? windowLayer.recents().filter(w => !w.doomed) : []
    }

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: root.reveal
        dim: 0.45
        hideSource: true
    }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    Keys.onEscapePressed: close()

    Item {
        anchors.fill: parent
        opacity: Math.min(1, root.reveal * 1.5)
        scale: 0.96 + 0.04 * Math.min(1, root.reveal)

        Rectangle {
            id: searchBox
            anchors.horizontalCenter: parent.horizontalCenter
            y: 58
            width: 380; height: 42; radius: 21
            color: Qt.rgba(1, 1, 1, 0.16)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: "white"; opacity: 0.8 }
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 44
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: 16
                color: "white"
                onAccepted: if (root.apps.length > 0) root.launch(root.apps[0].package)
                Keys.onEscapePressed: root.close()
                Text {
                    visible: !search.text
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Search")
                    font: search.font
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
            }
        }

        // The open windows.
        Row {
            id: windowsRow
            visible: root.openWindows.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: 124
            spacing: 22
            Repeater {
                model: root.openWindows
                delegate: Item {
                    id: card
                    required property var modelData
                    readonly property real ratio: Math.max(0.5, Math.min(2, modelData.width / Math.max(1, modelData.height)))
                    width: 190 * Math.min(1.35, ratio) * (ratio < 1 ? 1.0 : 1)
                    height: width / ratio
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.width: hover.hovered ? 2 : 1
                        border.color: hover.hovered ? Theme.accent : Qt.rgba(1, 1, 1, 0.2)
                        clip: true
                        ShaderEffectSource {
                            anchors.fill: parent
                            anchors.margins: 1
                            sourceItem: card.modelData
                            live: true
                            hideSource: false
                        }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: { root.close(); root.windowLayer.bringToFront(card.modelData); card.modelData.open() } }
                    Text {
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: card.modelData.title
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: "white"
                    }
                }
            }
        }

        // The apps.
        GridView {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            y: windowsRow.visible ? windowsRow.y + 170 + 34 : 130
            width: Math.min(parent.width - 120, Math.floor((parent.width - 120) / cellWidth) * cellWidth)
            height: parent.height - y - 120
            cellWidth: 130
            cellHeight: 126
            clip: true
            model: root.apps
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    scale: tap.pressed ? 0.93 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                    AppIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 68; source: cell.modelData.iconUrl || "" }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 112
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: cell.modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: "white"
                    }
                }
                TapHandler { id: tap; onTapped: root.launch(cell.modelData.package) }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.shell.dockMenu(cell.modelData.package, cell.mapToItem(root.shell, cell.width / 2, cell.height / 2)) }
            }
        }
    }

    function launch(pkg) {
        close()
        shell.launch(pkg, {}, null)
    }
}
