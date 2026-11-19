// SPDX-License-Identifier: Apache-2.0
import QtQuick

// The tab bar at the bottom of an app with sections (Clock, Market, Tune...): a floating
// rounded bar with an icon and a label per tab, the selected one lit in the app's colour.
// The same in every app.
//
//   TabBar {
//       id: tabs
//       model: [{ id: "listen", icon: "play", label: qsTr("Listen Now") },
//               { id: "search", icon: "search", label: qsTr("Search"), badge: 3 }]
//       current: app.tab
//       onSelected: (id) => app.tab = id
//   }
//
// It anchors itself to the bottom of its parent, over the home indicator's place: the content
// above it ends at tabs.top (its height counts the gap below the bar), or runs on under it.
Item {
    id: root

    property var model: []
    property string current: ""          // the selected tab's id; or
    property int currentIndex: -1        // its index, for models without ids
    property color tint: Theme.accent
    signal selected(string id)
    signal activated(int index)
    signal reselected(int index)         // the current tab tapped again: back to its top

    anchors.bottom: parent ? parent.bottom : undefined
    width: parent ? parent.width : 0
    height: 60 + 30

    Rectangle {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: parent.width - 40
        height: 60
        radius: 30
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.06)

        Row {
            anchors.fill: parent
            anchors.margins: 5
            Repeater {
                model: root.model
                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.current !== "" ? root.current === (modelData.id || "") : index === root.currentIndex
                    width: parent.width / Math.max(1, root.model.length)
                    height: 50
                    radius: 25
                    color: selected ? Theme.surfacePressed : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Column {
                        anchors.centerIn: parent
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: tab.modelData.icon
                            size: 20
                            color: tab.selected ? root.tint : Theme.text
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tab.width - 6
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tab.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: tab.selected ? root.tint : Theme.textSecondary
                        }
                    }
                    Rectangle {
                        visible: (tab.modelData.badge || 0) > 0
                        x: parent.width / 2 + 6
                        y: 2
                        width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
                        color: Theme.danger
                        Text { id: badgeText; anchors.centerIn: parent; text: tab.modelData.badge || ""; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.accentText }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (tab.selected) {
                                root.reselected(tab.index)
                            } else {
                                root.currentIndex = tab.index
                                root.selected(tab.modelData.id || "")
                                root.activated(tab.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
