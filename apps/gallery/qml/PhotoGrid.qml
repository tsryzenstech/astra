// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Square thumbnails edge to edge with hairline gaps (iOS Photos). "Select"
// switches to multiple selection to delete several items at once.
Item {
    id: root

    property string title
    property var items: []
    property bool showBack: false
    property bool startAtEnd: false
    property bool selecting: false
    property var selected: ({})
    readonly property int selectedCount: Object.keys(selected).length
    readonly property int columns: 3

    signal opened(var list, int index, Item item)
    signal back()

    function toggle(path) {
        const s = Object.assign({}, selected)
        if (s[path])
            delete s[path]
        else
            s[path] = true
        selected = s
    }
    onItemsChanged: if (startAtEnd) Qt.callLater(() => grid.positionViewAtEnd())

    GridView {
        id: grid
        anchors.fill: parent
        topMargin: Theme.statusBarHeight + 92
        bottomMargin: 120
        cellWidth: width / root.columns
        cellHeight: cellWidth
        model: root.items
        boundsBehavior: Flickable.DragOverBounds
        flickDeceleration: 2400
        maximumFlickVelocity: 6000
        cacheBuffer: 1600

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight

            Image {
                id: thumb
                anchors.fill: parent
                anchors.margins: 1
                source: cell.modelData.video ? "" : cell.modelData.url
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                visible: cell.modelData.video || thumb.status !== Image.Ready
                color: "#1C1C1E"
                Icon { anchors.centerIn: parent; visible: cell.modelData.video; name: "video"; size: 30; opacity: 0.8 }
            }
            Icon {
                visible: cell.modelData.video
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                name: "play"
                size: 14
            }
            // Selection
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                visible: root.selecting && !!root.selected[cell.modelData.path]
                color: Qt.rgba(1, 1, 1, 0.25)
            }
            Rectangle {
                visible: root.selecting
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 7
                width: 24
                height: 24
                radius: 12
                color: root.selected[cell.modelData.path] ? Theme.accent : Qt.rgba(0, 0, 0, 0.3)
                border.width: 1.5
                border.color: "white"
                Icon { anchors.centerIn: parent; visible: !!root.selected[cell.modelData.path]; name: "check"; size: 15 }
            }

            scale: area.pressed ? 0.94 : 1
            Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
            MouseArea {
                id: area
                anchors.fill: parent
                onClicked: {
                    if (root.selecting)
                        root.toggle(cell.modelData.path)
                    else
                        root.opened(root.items, cell.index, cell)
                }
                onPressAndHold: {
                    root.selecting = true
                    root.toggle(cell.modelData.path)
                }
            }
        }

        EmptyState {
            visible: root.items.length === 0
            y: 140
            width: grid.width - 60
            x: 30
            iconName: "image"
            title: qsTr("No photos or videos")
            message: qsTr("Photos you take, screenshots and downloaded images appear here.")
        }
    }

    // Header over a gradient so thumbnails fade under it.
    Rectangle {
        width: parent.width
        height: Theme.statusBarHeight + 92
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.92) }
            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.6) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
        }

        Row {
            x: 12
            y: Theme.statusBarHeight + 6
            visible: root.showBack
            spacing: 2
            Icon { name: "chevron-left"; size: 24; color: Theme.accent }
            Text { text: qsTr("Albums"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; color: Theme.accent }
            MouseArea { width: 100; height: 36; onClicked: root.back() }
        }
        Column {
            x: 18
            y: Theme.statusBarHeight + (root.showBack ? 34 : 10)
            Text {
                text: root.selecting ? qsTr("%n selected", "", root.selectedCount) : root.title
                font.family: Theme.fontFamily
                font.pixelSize: root.showBack ? 28 : 34
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                visible: !root.selecting && root.items.length > 0
                text: qsTr("%n items", "", root.items.length)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                color: Theme.textSecondary
            }
        }
        Rectangle {
            visible: root.items.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: Theme.statusBarHeight + 14
            width: selText.implicitWidth + 28
            height: 32
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.16)
            Text {
                id: selText
                anchors.centerIn: parent
                text: root.selecting ? qsTr("Cancel") : qsTr("Select")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                font.weight: Font.DemiBold
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.selecting = !root.selecting
                    root.selected = {}
                }
            }
        }
    }

    // Delete the selection
    Rectangle {
        visible: root.selecting
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        width: 200
        height: 48
        radius: 24
        color: root.selectedCount ? Theme.danger : Qt.rgba(1, 1, 1, 0.12)
        Row {
            anchors.centerIn: parent
            spacing: 8
            Icon { name: "trash"; size: 18; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Delete")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: "white"
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.selectedCount > 0
            onClicked: Dialogs.show({
                title: qsTr("Delete %n items?", "", root.selectedCount), icon: "trash",
                message: qsTr("They are removed from this phone."),
                buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" } ]
            }, function(b) {
                if (b !== "delete")
                    return
                for (const p of Object.keys(root.selected))
                    Application.removeMedia(p)
                root.selected = {}
                root.selecting = false
            })
        }
    }
}
