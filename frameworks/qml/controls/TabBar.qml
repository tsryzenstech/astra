// SPDX-License-Identifier: Apache-2.0
import QtQuick

// The tab bar at the bottom of an app with sections (Music, Phone, Clock):
// an icon and a label per tab, the selected one in the app's colour.
//
//   TabBar {
//       id: tabs
//       model: [{ icon: "play", label: qsTr("Listen Now") }, { icon: "search", label: qsTr("Search") }]
//       onActivated: (index) => stack.currentIndex = index
//   }
//
// It anchors itself to the bottom of its parent and leaves room for the
// home indicator; put the content above it (anchors.bottom: tabs.top).
Rectangle {
    id: root

    property var model: []
    property int currentIndex: 0
    property color tint: Theme.accent
    signal activated(int index)
    signal reselected(int index)     // the current tab tapped again: back to its top

    anchors.bottom: parent ? parent.bottom : undefined
    width: parent ? parent.width : 0
    height: 54 + Theme.homeIndicatorHeight * 0.6
    color: Theme.glassPanel

    Rectangle { width: parent.width; height: 1; color: Theme.separator }

    Row {
        y: 5
        Repeater {
            model: root.model
            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool selected: index === root.currentIndex
                width: root.width / Math.max(1, root.model.length)
                height: 46
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    name: tab.modelData.icon
                    size: 24
                    color: tab.selected ? root.tint : Theme.textSecondary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 29
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tab.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize - 2
                    font.weight: tab.selected ? Font.DemiBold : Font.Normal
                    color: tab.selected ? root.tint : Theme.textSecondary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (tab.selected) {
                            root.reselected(tab.index)
                        } else {
                            root.currentIndex = tab.index
                            root.activated(tab.index)
                        }
                    }
                }
            }
        }
    }
}
