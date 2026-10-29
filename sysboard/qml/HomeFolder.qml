// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// A folder on the home screen. Small (one cell): a glass tile with up to
// nine tiny icons. Big (2 x 2): its first apps as large icons you can open
// right away; with more than four, the last quarter is a tiny grid of the rest.
Item {
    id: root
    property string name
    property var apps: []
    property bool big: false
    property bool pressed: false

    readonly property var infos: (Packages.count >= 0 ? apps : []).map(p => Packages.get(p) || ({}))

    Rectangle {
        id: tile
        width: parent.width
        height: parent.height
        radius: root.big ? Theme.cardRadius : width * Theme.iconRadiusRatio
        color: Qt.rgba(1, 1, 1, 0.22)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        scale: root.pressed ? 0.94 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }

        // Small: 3 x 3 tiny icons
        Grid {
            visible: !root.big
            anchors.centerIn: parent
            columns: 3
            spacing: tile.width * 0.06
            Repeater {
                model: root.infos.slice(0, 9)
                delegate: AppIcon { required property var modelData; size: tile.width * 0.22; source: modelData.iconUrl || "" }
            }
        }

        // Big: 2 x 2 large icons (the 4th is a mini grid when there are more)
        Grid {
            visible: root.big
            anchors.centerIn: parent
            columns: 2
            spacing: tile.width * 0.08
            readonly property real cell: (tile.width - spacing * 3) / 2
            Repeater {
                model: root.big ? Math.min(4, root.infos.length) : 0
                delegate: Item {
                    required property int index
                    width: parent.cell
                    height: parent.cell
                    readonly property bool more: index === 3 && root.infos.length > 4
                    AppIcon {
                        visible: !parent.more
                        anchors.fill: parent
                        size: parent.width
                        source: root.infos[parent.index] ? root.infos[parent.index].iconUrl || "" : ""
                    }
                    Grid {
                        visible: parent.more
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 3
                        Repeater {
                            model: parent.parent.more ? root.infos.slice(3, 7) : []
                            delegate: AppIcon { required property var modelData; size: (parent.parent.width - 6) / 2; source: modelData.iconUrl || "" }
                        }
                    }
                }
            }
        }
    }
    Text {
        anchors.top: tile.bottom
        anchors.topMargin: 7
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(parent.width + 30, 90)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.name
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: "white"
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.25)
    }
}
