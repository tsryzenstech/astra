// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Scrollable page with an astraOS large title (SettingsHome.png).
// Pages pushed on a PageStack get a back button automatically.
Item {
    id: root

    property string title
    property bool showBack: stack !== null && stack.depth > 1
    property var stack: null // set by PageStack
    default property alias content: column.data
    property alias actions: actionRow.data // buttons at the right of the navigation bar
    property real spacing: 18
    property bool centeredTitle: false // compact bar: back button + centred title (AboutFinal.png)
    property Component background: null // replaces the black page background
    property alias flickable: flick

    Rectangle {
        anchors.fill: parent
        color: Theme.background
        visible: root.background === null
    }
    Loader {
        anchors.fill: parent
        sourceComponent: root.background
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: header.height + column.implicitHeight + 60
        boundsBehavior: Flickable.DragOverBounds
        flickDeceleration: 2600
        maximumFlickVelocity: 5000

        Item {
            id: header
            width: parent.width
            height: root.centeredTitle ? Theme.statusBarHeight + 56
                                       : Theme.statusBarHeight + (root.showBack ? 44 : 30) + titleText.height + 18

            Item {
                id: back
                visible: root.showBack
                x: 6
                y: Theme.statusBarHeight + 4
                width: backRow.width + 16
                height: 36
                Row {
                    id: backRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: 4
                    spacing: 2
                    Icon { name: "chevron-left"; size: root.centeredTitle ? 28 : 24; color: root.centeredTitle ? Theme.text : Theme.accent
                           anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.centeredTitle ? "" : qsTr("Back")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.headlineSize
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: if (root.stack) root.stack.pop()
                }
            }

            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.rightMargin: Theme.margin
                y: Theme.statusBarHeight + 4
                height: 36
                spacing: 12
            }

            Text {
                visible: root.centeredTitle
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.statusBarHeight + 6
                width: parent.width - 140
                horizontalAlignment: Text.AlignHCenter
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 1
                font.weight: Font.DemiBold
                color: Theme.text
            }

            Text {
                id: titleText
                visible: !root.centeredTitle
                x: Theme.margin
                y: Theme.statusBarHeight + (root.showBack ? 44 : 30)
                width: parent.width - 2 * Theme.margin
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: root.showBack ? 34 : Theme.largeTitleSize
                font.weight: Font.DemiBold
                color: Theme.text
                // Large titles stretch slightly when over-scrolled, like iOS.
                transform: Scale {
                    origin.x: 0
                    origin.y: titleText.height
                    xScale: 1 + Math.max(0, -flick.contentY) / 1200
                    yScale: xScale
                }
            }
        }

        Column {
            id: column
            y: header.height
            x: Theme.margin
            width: parent.width - 2 * Theme.margin
            spacing: root.spacing
        }
    }

    // Keeps scrolled content from running under the system status bar.
    Rectangle {
        width: parent.width
        height: Theme.statusBarHeight
        color: Theme.background
        visible: root.background === null
        opacity: Math.max(0, Math.min(0.94, (flick.contentY - 8) / 30))
    }
}
